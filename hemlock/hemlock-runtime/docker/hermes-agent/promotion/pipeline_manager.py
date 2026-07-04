#!/usr/bin/env python3
"""
Hermes Promotion Pipeline Manager

Manages promotion of framework updates through stages:
  dev → staging → prod

Features:
- Multi-stage promotion workflow
- Automated validation at each stage
- Rollback capabilities
- Release versioning
- Deployment audit logging
"""

import asyncio
import json
import logging
import os
import shutil
import subprocess
import sys
import time
from datetime import datetime, timedelta
from enum import Enum
from pathlib import Path
from typing import Any, Callable, Dict, List, Optional, Set
from dataclasses import dataclass, field, asdict
import uuid
import hashlib

logger = logging.getLogger(__name__)


class PromotionStage(Enum):
    """Promotion pipeline stages."""
    DEV = "dev"
    STAGING = "staging"
    PROD = "prod"


class PromotionStatus(Enum):
    """Promotion operation status."""
    PENDING = "pending"
    IN_PROGRESS = "in_progress"
    VALIDATING = "validating"
    APPROVED = "approved"
    REJECTED = "rejected"
    COMPLETED = "completed"
    FAILED = "failed"
    ROLLED_BACK = "rolled_back"


@dataclass
class Release:
    """Represents a framework release."""
    release_id: str
    version: str
    stage: PromotionStage = PromotionStage.DEV
    status: PromotionStatus = PromotionStatus.PENDING
    created_at: str = field(default_factory=lambda: datetime.utcnow().isoformat())
    promoted_at: Optional[str] = None
    image_tag: Optional[str] = None
    image_digest: Optional[str] = None
    source_commit: Optional[str] = None
    changelog: List[str] = field(default_factory=list)
    validation_results: Dict[str, Any] = field(default_factory=dict)
    approved_by: Optional[str] = None
    metadata: Dict[str, Any] = field(default_factory=dict)
    previous_version: Optional[str] = None
    
    def to_dict(self) -> Dict[str, Any]:
        """Convert to dictionary for JSON serialization."""
        return {
            **asdict(self),
            'stage': self.stage.value if isinstance(self.stage, PromotionStage) else self.stage,
            'status': self.status.value if isinstance(self.status, PromotionStatus) else self.status,
        }
    
    @classmethod
    def from_dict(cls, data: Dict[str, Any]) -> 'Release':
        """Create from dictionary."""
        if 'stage' in data and isinstance(data['stage'], str):
            data['stage'] = PromotionStage(data['stage'])
        if 'status' in data and isinstance(data['status'], str):
            data['status'] = PromotionStatus(data['status'])
        return cls(**data)


@dataclass
class RollbackPoint:
    """Represents a rollback point for a stage."""
    rollback_id: str
    stage: PromotionStage
    release_version: str
    release_id: str
    created_at: str = field(default_factory=lambda: datetime.utcnow().isoformat())
    image_tag: Optional[str] = None
    config_backup: Optional[str] = None
    state_backup: Optional[str] = None
    
    def to_dict(self) -> Dict[str, Any]:
        """Convert to dictionary."""
        return {
            **asdict(self),
            'stage': self.stage.value if isinstance(self.stage, PromotionStage) else self.stage,
        }
    
    @classmethod
    def from_dict(cls, data: Dict[str, Any]) -> 'RollbackPoint':
        """Create from dictionary."""
        if 'stage' in data and isinstance(data['stage'], str):
            data['stage'] = PromotionStage(data['stage'])
        return cls(**data)


class PromotionPipeline:
    """
    Pipeline for promoting framework releases through stages.
    
    Stages:
    - dev: Development and initial testing
    - staging: Pre-production validation
    - prod: Production deployment
    
    Features:
    - Automated validation at each stage
    - Manual approval gates
    - Rollback capabilities
    - Release versioning (semver)
    - Audit logging
    """
    
    def __init__(self, hermes_home: Optional[Path] = None):
        self.hermes_home = hermes_home or self._get_hermes_home()
        self.releases: Dict[str, Release] = {}
        self.rollback_points: Dict[str, RollbackPoint] = {}
        self._validation_handlers: Dict[str, Callable] = {}
        self._approval_handlers: Dict[str, Callable] = {}
        self._running = False
        self._lock = asyncio.Lock()
        
        # Configuration
        self.auto_promote_dev_to_staging = os.environ.get('PIPELINE_AUTO_PROMOTE_DEV', 'false').lower() in ('true', '1', 'yes')
        self.require_prod_approval = os.environ.get('PIPELINE_REQUIRE_PROD_APPROVAL', 'true').lower() in ('true', '1', 'yes')
        self.max_rollback_points = int(os.environ.get('PIPELINE_MAX_ROLLBACKS', '5'))
        
        # Paths
        self.releases_dir = self.hermes_home / 'promotion' / 'releases'
        self.rollback_dir = self.hermes_home / 'promotion' / 'rollbacks'
        self.manifest_file = self.hermes_home / 'promotion' / 'pipeline_manifest.json'
        self.audit_file = self.hermes_home / 'logs' / 'promotion_audit.jsonl'
        
        # Ensure directories exist
        self._ensure_directories()
        
        # Register default validators
        self._register_default_validators()
    
    def _get_hermes_home(self) -> Path:
        """Get HERMES_HOME directory."""
        return Path(os.environ.get('HERMES_HOME', Path.home() / '.hermes'))
    
    def _ensure_directories(self) -> None:
        """Ensure required directories exist."""
        self.releases_dir.mkdir(parents=True, exist_ok=True)
        self.rollback_dir.mkdir(parents=True, exist_ok=True)
        (self.hermes_home / 'logs').mkdir(parents=True, exist_ok=True)
    
    # -------------------------------------------------------------------------
    # Validation Registration
    # -------------------------------------------------------------------------
    
    def _register_default_validators(self) -> None:
        """Register default validation handlers."""
        self.register_validator('health_check', self._validate_health_check)
        self.register_validator('image_exists', self._validate_image_exists)
        self.register_validator('config_valid', self._validate_config)
        self.register_validator('backup_exists', self._validate_backup_exists)
    
    def register_validator(self, name: str, handler: Callable) -> None:
        """Register a validation handler."""
        self._validation_handlers[name] = handler
        logger.debug(f"Registered validator: {name}")
    
    def register_approval_handler(self, stage: PromotionStage, handler: Callable) -> None:
        """Register an approval handler for a stage."""
        self._approval_handlers[stage.value] = handler
        logger.debug(f"Registered approval handler for {stage.value}")
    
    # -------------------------------------------------------------------------
    # Default Validators
    # -------------------------------------------------------------------------
    
    async def _validate_health_check(self, release: Release) -> bool:
        """Validate framework health checks pass."""
        logger.info(f"Running health checks for {release.release_id}...")
        # TODO: Implement actual health check validation
        await asyncio.sleep(0.1)  # Simulate validation
        return True
    
    async def _validate_image_exists(self, release: Release) -> bool:
        """Validate Docker image exists."""
        if not release.image_tag:
            logger.warning(f"No image tag for {release.release_id}")
            return False
        
        # Check if image exists
        try:
            result = await asyncio.create_subprocess_exec(
                'docker', 'image', 'inspect', release.image_tag,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE
            )
            stdout, stderr = await result.communicate()
            return result.returncode == 0
        except Exception as e:
            logger.error(f"Image validation failed: {e}")
            return False
    
    async def _validate_config(self, release: Release) -> bool:
        """Validate configuration files."""
        config_path = self.hermes_home / 'config.yaml'
        if not config_path.exists():
            logger.warning("No config.yaml found")
            return True  # Config is optional
        
        try:
            import yaml
            with open(config_path) as f:
                yaml.safe_load(f)
            return True
        except Exception as e:
            logger.error(f"Config validation failed: {e}")
            return False
    
    async def _validate_backup_exists(self, release: Release) -> bool:
        """Validate recent backup exists before promotion."""
        backup_dir = self.hermes_home / 'backups'
        if not backup_dir.exists():
            logger.warning("No backup directory found")
            return True
        
        # Check for recent backups (within 24 hours)
        cutoff = datetime.utcnow() - timedelta(hours=24)
        for backup_file in backup_dir.glob('*.tar*'):
            mtime = datetime.fromtimestamp(backup_file.stat().st_mtime)
            if mtime > cutoff:
                return True
        
        logger.warning("No recent backup found")
        return True  # Don't block promotion
    
    # -------------------------------------------------------------------------
    # Release Management
    # -------------------------------------------------------------------------
    
    async def create_release(
        self,
        version: str,
        image_tag: Optional[str] = None,
        source_commit: Optional[str] = None,
        changelog: Optional[List[str]] = None,
        metadata: Optional[Dict[str, Any]] = None,
    ) -> Release:
        """
        Create a new release.
        
        Args:
            version: Semver version string (e.g., "1.2.0")
            image_tag: Docker image tag
            source_commit: Git commit hash
            changelog: List of changes
            metadata: Additional metadata
            
        Returns:
            Created Release object
        """
        release_id = f"release_{uuid.uuid4().hex[:8]}"
        
        # Find previous version
        previous_version = None
        for r in self.releases.values():
            if r.stage == PromotionStage.DEV and r.status == PromotionStatus.COMPLETED:
                previous_version = r.version
                break
        
        release = Release(
            release_id=release_id,
            version=version,
            image_tag=image_tag,
            source_commit=source_commit,
            changelog=changelog or [],
            metadata=metadata or {},
            previous_version=previous_version,
        )
        
        async with self._lock:
            self.releases[release_id] = release
            await self._save_manifest()
        
        logger.info(f"Created release {release_id}: {version}")
        await self._log_audit('release_created', release.to_dict())
        
        return release
    
    async def promote_release(
        self,
        release_id: str,
        target_stage: PromotionStage,
        approved_by: Optional[str] = None,
    ) -> bool:
        """
        Promote a release to the next stage.
        
        Args:
            release_id: Release to promote
            target_stage: Target promotion stage
            approved_by: User approving the promotion
            
        Returns:
            True if promotion successful
        """
        release = self.releases.get(release_id)
        if not release:
            logger.error(f"Release not found: {release_id}")
            return False
        
        # Validate stage transition
        if not self._is_valid_transition(release.stage, target_stage):
            logger.error(f"Invalid stage transition: {release.stage.value} → {target_stage.value}")
            return False
        
        logger.info(f"Promoting {release_id} from {release.stage.value} to {target_stage.value}")
        
        try:
            release.status = PromotionStatus.IN_PROGRESS
            await self._save_manifest()
            
            # Create rollback point before promotion
            rollback = await self._create_rollback_point(release.stage, release)
            
            # Run validations
            release.status = PromotionStatus.VALIDATING
            await self._save_manifest()
            
            validation_results = await self._run_validations(release, target_stage)
            release.validation_results = validation_results
            
            if not all(validation_results.values()):
                logger.error(f"Validation failed for {release_id}: {validation_results}")
                release.status = PromotionStatus.REJECTED
                await self._save_manifest()
                return False
            
            # Check approval requirements
            if target_stage == PromotionStage.PROD and self.require_prod_approval:
                if not approved_by:
                    logger.error("Production promotion requires approval")
                    release.status = PromotionStatus.PENDING
                    await self._save_manifest()
                    return False
                
                # Run approval handler
                approval_handler = self._approval_handlers.get('prod')
                if approval_handler:
                    approved = await approval_handler(release, approved_by)
                    if not approved:
                        logger.error(f"Production approval denied for {release_id}")
                        release.status = PromotionStatus.REJECTED
                        await self._save_manifest()
                        return False
            
            # Perform promotion
            await self._execute_promotion(release, target_stage)
            
            release.stage = target_stage
            release.status = PromotionStatus.COMPLETED
            release.promoted_at = datetime.utcnow().isoformat()
            release.approved_by = approved_by
            
            await self._save_manifest()
            
            logger.info(f"Successfully promoted {release_id} to {target_stage.value}")
            await self._log_audit('release_promoted', release.to_dict())
            
            return True
            
        except Exception as e:
            logger.error(f"Promotion failed: {e}")
            release.status = PromotionStatus.FAILED
            await self._save_manifest()
            await self._log_audit('promotion_failed', {
                'release_id': release_id,
                'error': str(e),
            })
            return False
    
    def _is_valid_transition(self, from_stage: PromotionStage, to_stage: PromotionStage) -> bool:
        """Check if stage transition is valid."""
        valid_transitions = {
            PromotionStage.DEV: [PromotionStage.STAGING],
            PromotionStage.STAGING: [PromotionStage.PROD, PromotionStage.DEV],  # Can rollback to dev
            PromotionStage.PROD: [PromotionStage.STAGING],  # Can only rollback
        }
        return to_stage in valid_transitions.get(from_stage, [])
    
    async def _run_validations(self, release: Release, target_stage: PromotionStage) -> Dict[str, bool]:
        """Run all validations for a release."""
        results = {}
        
        for name, handler in self._validation_handlers.items():
            try:
                if asyncio.iscoroutinefunction(handler):
                    result = await handler(release)
                else:
                    result = handler(release)
                results[name] = result
                logger.debug(f"Validation {name}: {'PASS' if result else 'FAIL'}")
            except Exception as e:
                logger.error(f"Validation {name} failed: {e}")
                results[name] = False
        
        return results
    
    async def _execute_promotion(self, release: Release, target_stage: PromotionStage) -> None:
        """Execute the promotion action."""
        # Update Docker image tags
        if release.image_tag:
            old_tag = f"{release.image_tag.split(':')[0]}:{release.version}-{release.stage.value}"
            new_tag = f"{release.image_tag.split(':')[0]}:{release.version}-{target_stage.value}"
            
            try:
                await asyncio.create_subprocess_exec(
                    'docker', 'tag', release.image_tag, new_tag,
                    stdout=subprocess.PIPE,
                    stderr=subprocess.PIPE
                )
                logger.info(f"Tagged image: {new_tag}")
            except Exception as e:
                logger.warning(f"Failed to tag image: {e}")
        
        # Update stage marker file
        marker_file = self.hermes_home / 'promotion' / f'{target_stage.value}_version'
        marker_file.write_text(json.dumps({
            'version': release.version,
            'release_id': release.release_id,
            'promoted_at': release.promoted_at,
        }, indent=2))
    
    async def _create_rollback_point(self, stage: PromotionStage, release: Release) -> RollbackPoint:
        """Create rollback point for current stage."""
        rollback_id = f"rollback_{uuid.uuid4().hex[:8]}"
        
        rollback = RollbackPoint(
            rollback_id=rollback_id,
            stage=stage,
            release_version=release.version,
            release_id=release.release_id,
            image_tag=release.image_tag,
        )
        
        # Backup current config
        config_path = self.hermes_home / 'config.yaml'
        if config_path.exists():
            backup_path = self.rollback_dir / f"{rollback_id}_config.yaml"
            shutil.copy(config_path, backup_path)
            rollback.config_backup = str(backup_path)
        
        self.rollback_points[rollback_id] = rollback
        
        # Cleanup old rollback points
        await self._cleanup_old_rollbacks()
        
        logger.info(f"Created rollback point {rollback_id} for {stage.value}")
        return rollback
    
    async def rollback(
        self,
        stage: PromotionStage,
        target_version: Optional[str] = None,
    ) -> bool:
        """
        Rollback a stage to a previous version.
        
        Args:
            stage: Stage to rollback
            target_version: Specific version to rollback to (None = last known good)
            
        Returns:
            True if rollback successful
        """
        # Find rollback point
        rollback_point = None
        for rp in sorted(
            self.rollback_points.values(),
            key=lambda x: x.created_at,
            reverse=True
        ):
            if rp.stage == stage:
                if target_version is None or rp.release_version == target_version:
                    rollback_point = rp
                    break
        
        if not rollback_point:
            logger.error(f"No rollback point found for {stage.value}")
            return False
        
        logger.info(f"Rolling back {stage.value} to {rollback_point.release_version}")
        
        try:
            # Restore config backup
            if rollback_point.config_backup:
                config_path = self.hermes_home / 'config.yaml'
                shutil.copy(rollback_point.config_backup, config_path)
                logger.info(f"Restored config from {rollback_point.config_backup}")
            
            # Update Docker image tags
            if rollback_point.image_tag:
                new_tag = f"{rollback_point.image_tag.split(':')[0]}:{rollback_point.release_version}-{stage.value}"
                await asyncio.create_subprocess_exec(
                    'docker', 'tag', rollback_point.image_tag, new_tag,
                    stdout=subprocess.PIPE,
                    stderr=subprocess.PIPE
                )
            
            # Update stage marker
            marker_file = self.hermes_home / 'promotion' / f'{stage.value}_version'
            marker_file.write_text(json.dumps({
                'version': rollback_point.release_version,
                'release_id': rollback_point.release_id,
                'rolled_back_at': datetime.utcnow().isoformat(),
            }, indent=2))
            
            # Update release status
            for release in self.releases.values():
                if release.release_id == rollback_point.release_id:
                    release.status = PromotionStatus.ROLLED_BACK
            
            logger.info(f"Successfully rolled back {stage.value} to {rollback_point.release_version}")
            await self._log_audit('rollback_completed', {
                'stage': stage.value,
                'target_version': rollback_point.release_version,
                'rollback_id': rollback_point.rollback_id,
            })
            
            return True
            
        except Exception as e:
            logger.error(f"Rollback failed: {e}")
            return False
    
    async def _cleanup_old_rollbacks(self) -> None:
        """Cleanup old rollback points."""
        if len(self.rollback_points) <= self.max_rollback_points:
            return
        
        # Remove oldest rollback points
        sorted_points = sorted(
            self.rollback_points.values(),
            key=lambda x: x.created_at
        )
        
        for rp in sorted_points[:len(sorted_points) - self.max_rollback_points]:
            # Cleanup backup files
            if rp.config_backup:
                try:
                    Path(rp.config_backup).unlink()
                except Exception:
                    pass
            
            del self.rollback_points[rp.rollback_id]
        
        logger.info(f"Cleaned up old rollback points")
    
    # -------------------------------------------------------------------------
    # Persistence
    # -------------------------------------------------------------------------
    
    async def _save_manifest(self) -> None:
        """Save pipeline manifest to disk."""
        self._ensure_directories()
        try:
            data = {
                'timestamp': datetime.utcnow().isoformat(),
                'releases': {rid: r.to_dict() for rid, r in self.releases.items()},
                'rollback_points': {rpid: rp.to_dict() for rpid, rp in self.rollback_points.items()},
            }
            temp_file = self.manifest_file.with_suffix('.tmp')
            temp_file.write_text(json.dumps(data, indent=2))
            temp_file.rename(self.manifest_file)
        except Exception as e:
            logger.error(f"Failed to save manifest: {e}")
    
    async def _load_manifest(self) -> None:
        """Load pipeline manifest from disk."""
        if not self.manifest_file.exists():
            return
        
        try:
            content = self.manifest_file.read_text()
            data = json.loads(content)
            
            for release_id, release_data in data.get('releases', {}).items():
                self.releases[release_id] = Release.from_dict(release_data)
            
            for rollback_id, rollback_data in data.get('rollback_points', {}).items():
                self.rollback_points[rollback_id] = RollbackPoint.from_dict(rollback_data)
            
            logger.info(f"Loaded {len(self.releases)} releases, {len(self.rollback_points)} rollback points")
        except Exception as e:
            logger.error(f"Failed to load manifest: {e}")
    
    async def _log_audit(self, event_type: str, data: Dict[str, Any]) -> None:
        """Log audit entry."""
        try:
            audit_entry = {
                'timestamp': datetime.utcnow().isoformat(),
                'event_type': event_type,
                'data': data,
            }
            with open(self.audit_file, 'a') as f:
                f.write(json.dumps(audit_entry) + '\n')
        except Exception as e:
            logger.error(f"Failed to write audit log: {e}")
    
    # -------------------------------------------------------------------------
    # Queries
    # -------------------------------------------------------------------------
    
    def get_release(self, release_id: str) -> Optional[Release]:
        """Get release by ID."""
        return self.releases.get(release_id)
    
    def list_releases(
        self,
        stage: Optional[PromotionStage] = None,
        status: Optional[PromotionStatus] = None,
    ) -> List[Release]:
        """List releases with optional filters."""
        releases = list(self.releases.values())
        
        if stage:
            releases = [r for r in releases if r.stage == stage]
        if status:
            releases = [r for r in releases if r.status == status]
        
        return sorted(releases, key=lambda r: r.created_at, reverse=True)
    
    def get_current_version(self, stage: PromotionStage) -> Optional[str]:
        """Get current version at a stage."""
        marker_file = self.hermes_home / 'promotion' / f'{stage.value}_version'
        if not marker_file.exists():
            return None
        
        try:
            data = json.loads(marker_file.read_text())
            return data.get('version')
        except Exception:
            return None
    
    def get_stats(self) -> Dict[str, Any]:
        """Get pipeline statistics."""
        by_stage = {}
        by_status = {}
        
        for release in self.releases.values():
            stage = release.stage.value if isinstance(release.stage, PromotionStage) else release.stage
            by_stage[stage] = by_stage.get(stage, 0) + 1
            
            status = release.status.value if isinstance(release.status, PromotionStatus) else release.status
            by_status[status] = by_status.get(status, 0) + 1
        
        return {
            'total_releases': len(self.releases),
            'by_stage': by_stage,
            'by_status': by_status,
            'rollback_points': len(self.rollback_points),
            'dev_version': self.get_current_version(PromotionStage.DEV),
            'staging_version': self.get_current_version(PromotionStage.STAGING),
            'prod_version': self.get_current_version(PromotionStage.PROD),
        }


# Global pipeline instance
_pipeline: Optional[PromotionPipeline] = None


def get_pipeline() -> PromotionPipeline:
    """Get or create the global pipeline."""
    global _pipeline
    if _pipeline is None:
        _pipeline = PromotionPipeline()
    return _pipeline


async def initialize_pipeline() -> PromotionPipeline:
    """Initialize the promotion pipeline."""
    pipeline = get_pipeline()
    await pipeline._load_manifest()
    return pipeline
