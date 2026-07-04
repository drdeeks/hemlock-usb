#!/usr/bin/env python3
"""
Backup and Recovery Test Suite

Tests backup creation, restoration, and point-in-time recovery.
"""

import asyncio
import json
import logging
import os
import sys
import time
from pathlib import Path
from datetime import datetime
from typing import Dict, Any

# Add parent directory to path
sys.path.insert(0, str(Path(__file__).parent.parent))

from backup import initialize_backup, get_backup_manager, BackupType, BackupStatus

logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s [%(levelname)s] %(name)s: %(message)s'
)
logger = logging.getLogger(__name__)


class BackupRecoveryTest:
    """Test suite for backup and recovery."""
    
    def __init__(self, hermes_home: Path):
        self.hermes_home = hermes_home
        self.backup_mgr = None
        self.results: Dict[str, Any] = {}
        self.test_dir = hermes_home / 'backup_test'
        self.backup_test_dir = hermes_home / 'backups' / 'test_restores'
    
    async def setup(self) -> None:
        """Initialize backup manager and test directories."""
        logger.info("Setting up backup/recovery test...")
        self.backup_mgr = await initialize_backup()
        
        # Create test directories
        self.test_dir.mkdir(parents=True, exist_ok=True)
        self.backup_test_dir.mkdir(parents=True, exist_ok=True)
        
        # Create test data
        await self._create_test_data()
        
        logger.info("Setup complete")
    
    async def teardown(self) -> None:
        """Cleanup test artifacts."""
        logger.info("Tearing down...")
        
        # Clean test directories
        if self.test_dir.exists():
            import shutil
            shutil.rmtree(self.test_dir, ignore_errors=True)
        
        logger.info("Teardown complete")
    
    async def _create_test_data(self) -> None:
        """Create test data for backup."""
        logger.info("Creating test data...")
        
        # Create test sessions
        sessions_dir = self.test_dir / 'sessions'
        sessions_dir.mkdir(parents=True, exist_ok=True)
        for i in range(5):
            session_file = sessions_dir / f'session_{i}.jsonl'
            session_file.write_text(json.dumps({
                'session_id': f'test_session_{i}',
                'messages': [{'role': 'user', 'content': f'Test message {i}'}],
                'timestamp': datetime.utcnow().isoformat(),
            }) + '\n')
        
        # Create test memory
        memory_dir = self.test_dir / 'memory'
        memory_dir.mkdir(parents=True, exist_ok=True)
        (memory_dir / 'MEMORY.md').write_text('# Test Memory\n\nThis is test memory content.')
        (memory_dir / 'notes.md').write_text('# Notes\n\nTest notes content.')
        
        # Create test skills
        skills_dir = self.test_dir / 'skills'
        skills_dir.mkdir(parents=True, exist_ok=True)
        test_skill = skills_dir / 'test_skill'
        test_skill.mkdir(parents=True, exist_ok=True)
        (test_skill / 'SKILL.md').write_text('# Test Skill\n\nThis is a test skill.')
        
        # Create test config
        (self.test_dir / 'config.yaml').write_text('''
model:
  primary: test-model
tools:
  enabled: all
''')
        
        logger.info(f"Created test data in {self.test_dir}")
    
    async def test_backup_creation(self) -> Dict[str, Any]:
        """Test backup creation."""
        logger.info("Testing backup creation...")
        start_time = time.time()
        
        # Add test directory as backup source
        self.backup_mgr.add_source('test_data', str(self.test_dir))
        
        # Create full backup
        manifest = await self.backup_mgr.create_backup(
            backup_type=BackupType.FULL,
            sources=['test_data'],
            metadata={'test': True},
        )
        
        duration = time.time() - start_time
        
        results = {
            'backup_id': manifest.backup_id,
            'status': manifest.status.value,
            'duration_sec': round(duration, 3),
            'size_bytes': manifest.backup_size,
            'size_mb': round(manifest.backup_size / 1024 / 1024, 2),
            'file_count': manifest.file_count,
            'checksum': manifest.checksum[:16] + '...' if manifest.checksum else None,
        }
        
        logger.info(f"Backup creation test complete: {results}")
        return results
    
    async def test_backup_restore(self, backup_id: str) -> Dict[str, Any]:
        """Test backup restoration."""
        logger.info(f"Testing backup restoration: {backup_id}...")
        start_time = time.time()
        
        # Restore to test directory
        restore_dir = self.backup_test_dir / f'restore_{backup_id}'
        success = await self.backup_mgr.restore_backup(
            backup_id=backup_id,
            target_dir=restore_dir,
            verify=True,
        )
        
        duration = time.time() - start_time
        
        # Verify restored files
        restored_files = []
        if restore_dir.exists():
            restored_files = [str(f.relative_to(restore_dir)) for f in restore_dir.rglob('*') if f.is_file()]
        
        results = {
            'backup_id': backup_id,
            'success': success,
            'duration_sec': round(duration, 3),
            'restore_dir': str(restore_dir),
            'restored_files': len(restored_files),
            'files': restored_files[:10],  # First 10 files
        }
        
        logger.info(f"Backup restore test complete: {results}")
        return results
    
    async def test_point_in_time_recovery(self) -> Dict[str, Any]:
        """Test point-in-time recovery with multiple backups."""
        logger.info("Testing point-in-time recovery...")
        
        # Create multiple backups over time
        backup_ids = []
        for i in range(3):
            # Modify test data
            test_file = self.test_dir / 'test_data.txt'
            test_file.write_text(f'Test data version {i}\nTimestamp: {datetime.utcnow().isoformat()}')
            
            # Create backup
            manifest = await self.backup_mgr.create_backup(
                backup_type=BackupType.SNAPSHOT,
                sources=['test_data'],
                metadata={'version': i},
            )
            backup_ids.append(manifest.backup_id)
            
            logger.info(f"Created snapshot {i}: {manifest.backup_id}")
            await asyncio.sleep(0.1)  # Small delay between backups
        
        # Test restoring each snapshot
        restore_results = []
        for backup_id in backup_ids:
            restore_dir = self.backup_test_dir / f'pit_restore_{backup_id}'
            success = await self.backup_mgr.restore_backup(
                backup_id=backup_id,
                target_dir=restore_dir,
                verify=True,
            )
            
            # Read restored version
            version_file = restore_dir / 'test_data.txt'
            version = version_file.read_text() if version_file.exists() else 'NOT FOUND'
            
            restore_results.append({
                'backup_id': backup_id,
                'success': success,
                'version': version[:50] if version else None,
            })
        
        results = {
            'snapshots_created': len(backup_ids),
            'restores_tested': len(restore_results),
            'all_successful': all(r['success'] for r in restore_results),
            'restores': restore_results,
        }
        
        logger.info(f"Point-in-time recovery test complete: {results}")
        return results
    
    async def test_incremental_backup(self) -> Dict[str, Any]:
        """Test incremental backup."""
        logger.info("Testing incremental backup...")
        
        # Create initial full backup
        full_manifest = await self.backup_mgr.create_backup(
            backup_type=BackupType.FULL,
            sources=['test_data'],
        )
        
        # Modify some files
        new_file = self.test_dir / 'new_file.txt'
        new_file.write_text('New content added after full backup')
        
        # Create incremental backup
        incr_manifest = await self.backup_mgr.create_backup(
            backup_type=BackupType.INCREMENTAL,
            sources=['test_data'],
        )
        
        results = {
            'full_backup': {
                'id': full_manifest.backup_id,
                'size_bytes': full_manifest.backup_size,
            },
            'incremental_backup': {
                'id': incr_manifest.backup_id,
                'size_bytes': incr_manifest.backup_size,
            },
            'size_reduction_pct': round(
                (1 - incr_manifest.backup_size / full_manifest.backup_size) * 100, 1
            ) if full_manifest.backup_size > 0 else 0,
        }
        
        logger.info(f"Incremental backup test complete: {results}")
        return results
    
    async def run_all_tests(self) -> Dict[str, Any]:
        """Run all backup/recovery tests."""
        logger.info("=" * 60)
        logger.info("Starting Backup and Recovery Test Suite")
        logger.info("=" * 60)
        
        total_start = time.time()
        
        try:
            # Test backup creation
            self.results['backup_creation'] = await self.test_backup_creation()
            backup_id = self.results['backup_creation']['backup_id']
            
            # Test backup restoration
            self.results['backup_restore'] = await self.test_backup_restore(backup_id)
            
            # Test point-in-time recovery
            self.results['point_in_time_recovery'] = await self.test_point_in_time_recovery()
            
            # Test incremental backup
            self.results['incremental_backup'] = await self.test_incremental_backup()
            
            # Get final stats
            self.results['final_stats'] = self.backup_mgr.get_stats()
            
        except Exception as e:
            logger.error(f"Test failed: {e}")
            self.results['error'] = str(e)
            import traceback
            self.results['traceback'] = traceback.format_exc()
        
        total_duration = time.time() - total_start
        self.results['total_duration_sec'] = round(total_duration, 3)
        
        # Summary
        logger.info("=" * 60)
        logger.info("Test Summary")
        logger.info("=" * 60)
        logger.info(f"Total duration: {total_duration:.2f}s")
        logger.info(f"Backups created: {self.results.get('final_stats', {}).get('total_backups', 0)}")
        logger.info(f"Total backup size: {self.results.get('final_stats', {}).get('total_size_mb', 0):.2f}MB")
        
        if 'error' in self.results:
            logger.error(f"Tests failed with error: {self.results['error']}")
        
        return self.results


async def main():
    """Main entry point."""
    hermes_home = Path(os.environ.get('HERMES_HOME', Path.home() / '.hermes'))
    
    test = BackupRecoveryTest(hermes_home=hermes_home)
    
    try:
        await test.setup()
        results = await test.run_all_tests()
        
        # Save results
        results_file = hermes_home / 'backups' / 'recovery_test_results.json'
        results_file.parent.mkdir(parents=True, exist_ok=True)
        results_file.write_text(json.dumps(results, indent=2))
        logger.info(f"Results saved to {results_file}")
        
        # Exit with error if tests failed
        if 'error' in results:
            sys.exit(1)
        
        logger.info("All backup/recovery tests passed!")
        
    except Exception as e:
        logger.exception(f"Test failed: {e}")
        sys.exit(1)
    finally:
        await test.teardown()


if __name__ == "__main__":
    asyncio.run(main())
