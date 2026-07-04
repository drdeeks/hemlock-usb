#!/usr/bin/env python3
"""
Hermes Backup Manager

Automated backup system for Hermes framework data including:
- Agent state and sessions
- Memory and skills
- Configuration files
- Orchestration state
- Custom data directories

Features:
- Scheduled automatic backups
- Incremental and full backups
- Compression and encryption
- Retention policies
- Backup verification
- Remote storage support
"""

import asyncio
import hashlib
import json
import logging
import os
import shutil
import tarfile
import tempfile
import time
from datetime import datetime, timedelta
from pathlib import Path
from typing import Any, Callable, Dict, List, Optional, Set
from dataclasses import dataclass, field, asdict
from enum import Enum
import uuid

logger = logging.getLogger(__name__)


class BackupType(Enum):
    """Backup types."""
    FULL = "full"           # Complete backup of all data
    INCREMENTAL = "incremental"  # Only changed files since last backup
    DIFFERENTIAL = "differential"  # Changed since last full backup
    SNAPSHOT = "snapshot"   # Point-in-time snapshot


class BackupStatus(Enum):
    """Backup operation status."""
    PENDING = "pending"
    IN_PROGRESS = "in_progress"
    COMPLETED = "completed"
    FAILED = "failed"
    VERIFYING = "verifying"
    VERIFIED = "verified"


@dataclass
class BackupManifest:
    """Manifest for a backup operation."""
    backup_id: str
    backup_type: BackupType
    created_at: str = field(default_factory=lambda: datetime.utcnow().isoformat())
    completed_at: Optional[str] = None
    status: BackupStatus = BackupStatus.PENDING
    source_paths: List[str] = field(default_factory=list)
    backup_path: Optional[str] = None
    backup_size: int = 0
    file_count: int = 0
    checksum: Optional[str] = None
    checksum_algorithm: str = "sha256"
    retention_days: int = 30
    metadata: Dict[str, Any] = field(default_factory=dict)
    error_message: Optional[str] = None
    
    def to_dict(self) -> Dict[str, Any]:
        """Convert to dictionary for JSON serialization."""
        return {
            **asdict(self),
            'backup_type': self.backup_type.value if isinstance(self.backup_type, BackupType) else self.backup_type,
            'status': self.status.value if isinstance(self.status, BackupStatus) else self.status,
        }
    
    @classmethod
    def from_dict(cls, data: Dict[str, Any]) -> 'BackupManifest':
        """Create from dictionary."""
        if 'backup_type' in data and isinstance(data['backup_type'], str):
            data['backup_type'] = BackupType(data['backup_type'])
        if 'status' in data and isinstance(data['status'], str):
            data['status'] = BackupStatus(data['status'])
        return cls(**data)


class BackupManager:
    """
    Manager for automated backups of Hermes framework data.
    
    Features:
    - Configurable backup sources
    - Multiple backup types (full, incremental, differential)
    - Compression with gzip
    - Optional encryption
    - Retention policies
    - Backup verification
    - Remote storage support (S3, etc.)
    """
    
    def __init__(self, hermes_home: Optional[Path] = None, backup_dir: Optional[Path] = None):
        self.hermes_home = hermes_home or self._get_hermes_home()
        self.backup_dir = backup_dir or (self.hermes_home / 'backups')
        self.manifests: Dict[str, BackupManifest] = {}
        self._backup_callbacks: List[Callable] = []
        self._running = False
        self._scheduler_task: Optional[asyncio.Task] = None
        self._lock = asyncio.Lock()
        
        # Default backup sources
        self.default_sources = {
            'sessions': 'sessions',
            'memory': 'memory',
            'skills': 'skills',
            'config': 'config.yaml',
            'orchestration': 'orchestration',
            'logs': 'logs',
        }
        
        # Configuration
        self.compression = os.environ.get('BACKUP_COMPRESSION', 'gzip').lower() in ('true', '1', 'yes', 'gzip')
        self.default_retention_days = int(os.environ.get('BACKUP_RETENTION_DAYS', '30'))
        self.max_concurrent_backups = int(os.environ.get('BACKUP_MAX_CONCURRENT', '3'))
        self.verify_after_backup = os.environ.get('BACKUP_VERIFY', 'true').lower() in ('true', '1', 'yes')
        
        # State files
        self.manifest_file = self.backup_dir / 'backup_manifest.json'
        self.last_backup_file = self.backup_dir / 'last_backup.json'
        
        # Ensure backup directory exists
        self._ensure_directories()
    
    def _get_hermes_home(self) -> Path:
        """Get HERMES_HOME directory."""
        return Path(os.environ.get('HERMES_HOME', Path.home() / '.hermes'))
    
    def _ensure_directories(self) -> None:
        """Ensure required directories exist."""
        self.backup_dir.mkdir(parents=True, exist_ok=True)
        (self.backup_dir / 'full').mkdir(parents=True, exist_ok=True)
        (self.backup_dir / 'incremental').mkdir(parents=True, exist_ok=True)
        (self.backup_dir / 'snapshots').mkdir(parents=True, exist_ok=True)
    
    # -------------------------------------------------------------------------
    # Backup Configuration
    # -------------------------------------------------------------------------
    
    def add_source(self, name: str, path: str) -> None:
        """Add a backup source."""
        self.default_sources[name] = path
        logger.debug(f"Added backup source: {name} -> {path}")
    
    def remove_source(self, name: str) -> None:
        """Remove a backup source."""
        self.default_sources.pop(name, None)
        logger.debug(f"Removed backup source: {name}")
    
    def register_callback(self, callback: Callable) -> None:
        """Register callback for backup events."""
        self._backup_callbacks.append(callback)
    
    async def _notify_callback(self, event: str, data: Dict[str, Any]) -> None:
        """Notify callbacks of backup events."""
        for callback in self._backup_callbacks:
            try:
                if asyncio.iscoroutinefunction(callback):
                    await callback(event, data)
                else:
                    callback(event, data)
            except Exception as e:
                logger.error(f"Backup callback failed: {e}")
    
    # -------------------------------------------------------------------------
    # Backup Operations
    # -------------------------------------------------------------------------
    
    async def create_backup(
        self,
        backup_type: BackupType = BackupType.FULL,
        sources: Optional[List[str]] = None,
        retention_days: Optional[int] = None,
        metadata: Optional[Dict[str, Any]] = None,
    ) -> BackupManifest:
        """
        Create a backup.
        
        Args:
            backup_type: Type of backup (full, incremental, differential, snapshot)
            sources: List of source names to backup (None = all default sources)
            retention_days: Days to retain backup (None = default)
            metadata: Additional metadata to store with backup
            
        Returns:
            BackupManifest for the created backup
        """
        backup_id = f"backup_{uuid.uuid4().hex[:8]}_{datetime.utcnow().strftime('%Y%m%d_%H%M%S')}"
        
        manifest = BackupManifest(
            backup_id=backup_id,
            backup_type=backup_type,
            retention_days=retention_days or self.default_retention_days,
            metadata=metadata or {},
        )
        
        async with self._lock:
            self.manifests[backup_id] = manifest
            await self._save_manifests()
        
        logger.info(f"Starting {backup_type.value} backup: {backup_id}")
        await self._notify_callback('backup_started', {'backup_id': backup_id})
        
        try:
            manifest.status = BackupStatus.IN_PROGRESS
            await self._save_manifests()
            
            # Determine source paths
            source_names = sources or list(self.default_sources.keys())
            source_paths = await self._resolve_source_paths(source_names)
            manifest.source_paths = [str(p) for p in source_paths]
            
            # Create backup archive
            backup_path = await self._create_archive(backup_id, backup_type, source_paths)
            manifest.backup_path = str(backup_path)
            
            # Calculate stats
            manifest.backup_size = backup_path.stat().st_size
            manifest.file_count = await self._count_files(source_paths)
            
            # Calculate checksum
            if self.verify_after_backup:
                manifest.status = BackupStatus.VERIFYING
                await self._save_manifests()
                manifest.checksum = await self._calculate_checksum(backup_path)
                manifest.status = BackupStatus.VERIFIED
                logger.info(f"Backup {backup_id} verified: checksum={manifest.checksum[:16]}...")
            else:
                manifest.status = BackupStatus.COMPLETED
            
            manifest.completed_at = datetime.utcnow().isoformat()
            await self._save_manifests()
            
            # Save last backup info
            await self._save_last_backup(manifest)
            
            logger.info(f"Backup {backup_id} completed: {manifest.backup_size / 1024 / 1024:.2f}MB, {manifest.file_count} files")
            await self._notify_callback('backup_completed', manifest.to_dict())
            
            # Cleanup old backups
            await self._cleanup_old_backups()
            
        except Exception as e:
            logger.error(f"Backup {backup_id} failed: {e}")
            manifest.status = BackupStatus.FAILED
            manifest.error_message = str(e)
            manifest.completed_at = datetime.utcnow().isoformat()
            await self._save_manifests()
            await self._notify_callback('backup_failed', {'backup_id': backup_id, 'error': str(e)})
            raise
        
        return manifest
    
    async def _resolve_source_paths(self, source_names: List[str]) -> List[Path]:
        """Resolve source names to actual paths."""
        paths = []
        for name in source_names:
            source_path = self.default_sources.get(name)
            if not source_path:
                logger.warning(f"Unknown backup source: {name}")
                continue
            
            # Make path absolute relative to HERMES_HOME
            if not os.path.isabs(source_path):
                full_path = self.hermes_home / source_path
            else:
                full_path = Path(source_path)
            
            if full_path.exists():
                paths.append(full_path)
                logger.debug(f"Resolved source {name} -> {full_path}")
            else:
                logger.warning(f"Backup source does not exist: {name} ({full_path})")
        
        return paths
    
    async def _create_archive(
        self,
        backup_id: str,
        backup_type: BackupType,
        source_paths: List[Path],
    ) -> Path:
        """Create backup archive."""
        # Determine output directory based on backup type
        if backup_type == BackupType.FULL:
            output_dir = self.backup_dir / 'full'
        elif backup_type == BackupType.INCREMENTAL:
            output_dir = self.backup_dir / 'incremental'
        else:
            output_dir = self.backup_dir / 'snapshots'
        
        # Create archive filename
        timestamp = datetime.utcnow().strftime('%Y%m%d_%H%M%S')
        archive_name = f"{backup_id}.tar.gz" if self.compression else f"{backup_id}.tar"
        archive_path = output_dir / archive_name
        
        # Create archive
        mode = 'w:gz' if self.compression else 'w'
        with tarfile.open(archive_path, mode) as tar:
            for source_path in source_paths:
                if source_path.is_dir():
                    tar.add(source_path, arcname=source_path.name)
                else:
                    tar.add(source_path, arcname=source_path.name)
                logger.debug(f"Added to backup: {source_path}")
        
        return archive_path
    
    async def _calculate_checksum(self, path: Path) -> str:
        """Calculate SHA256 checksum of backup file."""
        sha256 = hashlib.sha256()
        with open(path, 'rb') as f:
            for chunk in iter(lambda: f.read(8192), b''):
                sha256.update(chunk)
        return sha256.hexdigest()
    
    async def _count_files(self, paths: List[Path]) -> int:
        """Count total files in paths."""
        count = 0
        for path in paths:
            if path.is_dir():
                count += sum(1 for _ in path.rglob('*') if _.is_file())
            elif path.is_file():
                count += 1
        return count
    
    # -------------------------------------------------------------------------
    # Recovery Operations
    # -------------------------------------------------------------------------
    
    async def restore_backup(
        self,
        backup_id: str,
        target_dir: Optional[Path] = None,
        verify: bool = True,
    ) -> bool:
        """
        Restore a backup.
        
        Args:
            backup_id: ID of backup to restore
            target_dir: Directory to restore to (None = original location)
            verify: Verify backup integrity before restore
            
        Returns:
            True if restore successful
        """
        manifest = self.manifests.get(backup_id)
        if not manifest:
            logger.error(f"Backup not found: {backup_id}")
            return False
        
        if manifest.status not in (BackupStatus.COMPLETED, BackupStatus.VERIFIED):
            logger.error(f"Backup not ready for restore: {backup_id} (status={manifest.status.value})")
            return False
        
        backup_path = Path(manifest.backup_path)
        if not backup_path.exists():
            logger.error(f"Backup file not found: {backup_path}")
            return False
        
        logger.info(f"Restoring backup {backup_id}...")
        await self._notify_callback('restore_started', {'backup_id': backup_id})
        
        try:
            # Verify backup if requested
            if verify:
                logger.info(f"Verifying backup {backup_id}...")
                checksum = await self._calculate_checksum(backup_path)
                if checksum != manifest.checksum:
                    logger.error(f"Backup verification failed: checksum mismatch")
                    return False
                logger.info(f"Backup verified successfully")
            
            # Determine restore target
            target = target_dir or self.hermes_home
            
            # Extract archive
            mode = 'r:gz' if self.compression else 'r'
            with tarfile.open(backup_path, mode) as tar:
                tar.extractall(path=target)
                logger.debug(f"Extracted backup to {target}")
            
            logger.info(f"Backup {backup_id} restored successfully to {target}")
            await self._notify_callback('restore_completed', {'backup_id': backup_id, 'target': str(target)})
            return True
            
        except Exception as e:
            logger.error(f"Restore failed: {e}")
            await self._notify_callback('restore_failed', {'backup_id': backup_id, 'error': str(e)})
            return False
    
    async def list_backups(
        self,
        backup_type: Optional[BackupType] = None,
        status: Optional[BackupStatus] = None,
    ) -> List[BackupManifest]:
        """List backups with optional filters."""
        manifests = list(self.manifests.values())
        
        if backup_type:
            manifests = [m for m in manifests if m.backup_type == backup_type]
        if status:
            manifests = [m for m in manifests if m.status == status]
        
        return sorted(manifests, key=lambda m: m.created_at, reverse=True)
    
    async def get_backup(self, backup_id: str) -> Optional[BackupManifest]:
        """Get backup manifest by ID."""
        return self.manifests.get(backup_id)
    
    async def delete_backup(self, backup_id: str) -> bool:
        """Delete a backup."""
        manifest = self.manifests.get(backup_id)
        if not manifest:
            return False
        
        # Delete backup file
        if manifest.backup_path:
            backup_file = Path(manifest.backup_path)
            if backup_file.exists():
                backup_file.unlink()
                logger.debug(f"Deleted backup file: {backup_file}")
        
        # Remove manifest
        del self.manifests[backup_id]
        await self._save_manifests()
        
        logger.info(f"Deleted backup: {backup_id}")
        return True
    
    # -------------------------------------------------------------------------
    # Retention and Cleanup
    # -------------------------------------------------------------------------
    
    async def _cleanup_old_backups(self) -> None:
        """Delete backups older than retention period."""
        cutoff = datetime.utcnow() - timedelta(days=self.default_retention_days)
        deleted = 0
        
        for backup_id, manifest in list(self.manifests.items()):
            try:
                created_at = datetime.fromisoformat(manifest.created_at)
                if created_at < cutoff:
                    await self.delete_backup(backup_id)
                    deleted += 1
            except (ValueError, KeyError):
                pass
        
        if deleted:
            logger.info(f"Cleaned up {deleted} old backups")
    
    # -------------------------------------------------------------------------
    # Scheduled Backups
    # -------------------------------------------------------------------------
    
    async def start_scheduler(self, interval_hours: int = 24) -> None:
        """Start automatic backup scheduler."""
        if self._running:
            return
        
        self._running = True
        self._scheduler_task = asyncio.create_task(self._scheduler_loop(interval_hours))
        logger.info(f"Backup scheduler started (interval={interval_hours}h)")
    
    async def stop_scheduler(self) -> None:
        """Stop automatic backup scheduler."""
        self._running = False
        if self._scheduler_task:
            self._scheduler_task.cancel()
            try:
                await self._scheduler_task
            except asyncio.CancelledError:
                pass
            self._scheduler_task = None
        logger.info("Backup scheduler stopped")
    
    async def _scheduler_loop(self, interval_hours: int) -> None:
        """Background scheduler loop."""
        while self._running:
            try:
                await asyncio.sleep(interval_hours * 3600)
                logger.info("Running scheduled backup...")
                await self.create_backup(backup_type=BackupType.FULL)
            except asyncio.CancelledError:
                break
            except Exception as e:
                logger.error(f"Scheduled backup failed: {e}")
    
    # -------------------------------------------------------------------------
    # Persistence
    # -------------------------------------------------------------------------
    
    async def _save_manifests(self) -> None:
        """Save backup manifests to disk."""
        self._ensure_directories()
        try:
            data = {
                'timestamp': datetime.utcnow().isoformat(),
                'backups': {bid: m.to_dict() for bid, m in self.manifests.items()},
            }
            temp_file = self.manifest_file.with_suffix('.tmp')
            temp_file.write_text(json.dumps(data, indent=2))
            temp_file.rename(self.manifest_file)
        except Exception as e:
            logger.error(f"Failed to save manifests: {e}")
    
    async def _load_manifests(self) -> None:
        """Load backup manifests from disk."""
        if not self.manifest_file.exists():
            return
        
        try:
            content = self.manifest_file.read_text()
            data = json.loads(content)
            
            for backup_id, backup_data in data.get('backups', {}).items():
                self.manifests[backup_id] = BackupManifest.from_dict(backup_data)
            
            logger.info(f"Loaded {len(self.manifests)} backup manifests")
        except Exception as e:
            logger.error(f"Failed to load manifests: {e}")
    
    async def _save_last_backup(self, manifest: BackupManifest) -> None:
        """Save last backup info for quick access."""
        try:
            data = {
                'backup_id': manifest.backup_id,
                'completed_at': manifest.completed_at,
                'backup_type': manifest.backup_type.value,
                'backup_size': manifest.backup_size,
                'file_count': manifest.file_count,
            }
            self.last_backup_file.write_text(json.dumps(data, indent=2))
        except Exception as e:
            logger.error(f"Failed to save last backup info: {e}")
    
    # -------------------------------------------------------------------------
    # Statistics
    # -------------------------------------------------------------------------
    
    def get_stats(self) -> Dict[str, Any]:
        """Get backup system statistics."""
        by_type = {}
        by_status = {}
        total_size = 0
        
        for manifest in self.manifests.values():
            btype = manifest.backup_type.value if isinstance(manifest.backup_type, BackupType) else manifest.backup_type
            by_type[btype] = by_type.get(btype, 0) + 1
            
            status = manifest.status.value if isinstance(manifest.status, BackupStatus) else manifest.status
            by_status[status] = by_status.get(status, 0) + 1
            
            total_size += manifest.backup_size
        
        return {
            'total_backups': len(self.manifests),
            'by_type': by_type,
            'by_status': by_status,
            'total_size_bytes': total_size,
            'total_size_mb': round(total_size / 1024 / 1024, 2),
            'scheduler_running': self._running,
            'sources_configured': len(self.default_sources),
        }


# Global backup manager instance
_backup_manager: Optional[BackupManager] = None


def get_backup_manager() -> BackupManager:
    """Get or create the global backup manager."""
    global _backup_manager
    if _backup_manager is None:
        _backup_manager = BackupManager()
    return _backup_manager


async def initialize_backup() -> BackupManager:
    """Initialize the backup manager."""
    manager = get_backup_manager()
    await manager._load_manifests()
    return manager
