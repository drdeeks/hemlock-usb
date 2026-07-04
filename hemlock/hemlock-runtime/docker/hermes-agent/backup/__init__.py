"""
Hermes Backup and Recovery System

Automated backup and recovery for Hermes framework data.

Components:
- BackupManager: Automated backups with scheduling
- Recovery testing and validation
- Point-in-time recovery
- Disaster recovery procedures

Usage:
    from backup import initialize_backup, get_backup_manager
    
    # Initialize
    backup_mgr = await initialize_backup()
    
    # Create backup
    manifest = await backup_mgr.create_backup()
    
    # Restore backup
    success = await backup_mgr.restore_backup(manifest.backup_id)
"""

from .backup_manager import (
    BackupManager,
    BackupManifest,
    BackupType,
    BackupStatus,
    get_backup_manager,
    initialize_backup,
)

__all__ = [
    'BackupManager',
    'BackupManifest',
    'BackupType',
    'BackupStatus',
    'get_backup_manager',
    'initialize_backup',
]
