#!/usr/bin/env python3
"""
Promotion Pipeline Test Suite

Tests release creation, promotion, and rollback functionality.
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

from promotion import initialize_pipeline, get_pipeline, PromotionStage, PromotionStatus

logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s [%(levelname)s] %(name)s: %(message)s'
)
logger = logging.getLogger(__name__)


class PromotionPipelineTest:
    """Test suite for promotion pipeline."""
    
    def __init__(self, hermes_home: Path):
        self.hermes_home = hermes_home
        self.pipeline = None
        self.results: Dict[str, Any] = {}
    
    async def setup(self) -> None:
        """Initialize pipeline."""
        logger.info("Setting up promotion pipeline test...")
        self.pipeline = await initialize_pipeline()
        logger.info("Setup complete")
    
    async def teardown(self) -> None:
        """Cleanup."""
        logger.info("Test complete")
    
    async def test_release_creation(self) -> Dict[str, Any]:
        """Test release creation."""
        logger.info("Testing release creation...")
        start_time = time.time()
        
        # Create test releases
        releases = []
        for i, version in enumerate(['1.0.0', '1.1.0', '1.2.0']):
            release = await self.pipeline.create_release(
                version=version,
                image_tag=f"openclaw/framework:{version}",
                source_commit=f"abc123{i}",
                changelog=[f"Feature {i}", f"Bug fix {i}"],
                metadata={'test': True},
            )
            releases.append(release)
        
        duration = time.time() - start_time
        
        results = {
            'releases_created': len(releases),
            'duration_sec': round(duration, 3),
            'versions': [r.version for r in releases],
        }
        
        logger.info(f"Release creation test complete: {results}")
        return results
    
    async def test_promotion_workflow(self, release_id: str) -> Dict[str, Any]:
        """Test promotion through stages."""
        logger.info(f"Testing promotion workflow for {release_id}...")
        start_time = time.time()
        
        # Promote to staging
        staging_success = await self.pipeline.promote_release(
            release_id=release_id,
            target_stage=PromotionStage.STAGING,
        )
        
        # Promote to prod (with approval)
        prod_success = await self.pipeline.promote_release(
            release_id=release_id,
            target_stage=PromotionStage.PROD,
            approved_by="test_user",
        )
        
        duration = time.time() - start_time
        
        release = self.pipeline.get_release(release_id)
        
        results = {
            'release_id': release_id,
            'staging_promotion': staging_success,
            'prod_promotion': prod_success,
            'final_stage': release.stage.value if release else None,
            'final_status': release.status.value if release else None,
            'duration_sec': round(duration, 3),
        }
        
        logger.info(f"Promotion workflow test complete: {results}")
        return results
    
    async def test_rollback(self, release_id: str) -> Dict[str, Any]:
        """Test rollback functionality."""
        logger.info(f"Testing rollback for {release_id}...")
        start_time = time.time()
        
        # Get the release object
        release = self.pipeline.get_release(release_id)
        if not release:
            return {'error': f'Release not found: {release_id}'}
        
        # First promote to prod
        await self.pipeline.promote_release(
            release_id=release_id,
            target_stage=PromotionStage.PROD,
            approved_by="test_user",
        )
        
        # Create a new release to simulate update
        new_release = await self.pipeline.create_release(
            version="1.3.0-bad",
            image_tag="openclaw/framework:1.3.0-bad",
            changelog=["Bad release for testing"],
        )
        
        await self.pipeline.promote_release(
            release_id=new_release.release_id,
            target_stage=PromotionStage.STAGING,
        )
        
        await self.pipeline.promote_release(
            release_id=new_release.release_id,
            target_stage=PromotionStage.PROD,
            approved_by="test_user",
        )
        
        # Now rollback
        rollback_success = await self.pipeline.rollback(
            stage=PromotionStage.PROD,
            target_version=release.version,
        )
        
        duration = time.time() - start_time
        
        # Check current prod version
        current_version = self.pipeline.get_current_version(PromotionStage.PROD)
        
        results = {
            'rollback_success': rollback_success,
            'rolled_back_to': current_version,
            'expected_version': release.version,
            'match': current_version == release.version,
            'duration_sec': round(duration, 3),
        }
        
        logger.info(f"Rollback test complete: {results}")
        return results
    
    async def test_validation_pipeline(self) -> Dict[str, Any]:
        """Test validation pipeline."""
        logger.info("Testing validation pipeline...")
        start_time = time.time()
        
        # Create release
        release = await self.pipeline.create_release(
            version="1.4.0",
            image_tag="openclaw/framework:1.4.0",
        )
        
        # Run validations
        validation_results = await self.pipeline._run_validations(
            release,
            PromotionStage.STAGING
        )
        
        duration = time.time() - start_time
        
        results = {
            'release_id': release.release_id,
            'validations_run': len(validation_results),
            'validation_results': validation_results,
            'all_passed': all(validation_results.values()),
            'duration_sec': round(duration, 3),
        }
        
        logger.info(f"Validation pipeline test complete: {results}")
        return results
    
    async def run_all_tests(self) -> Dict[str, Any]:
        """Run all pipeline tests."""
        logger.info("=" * 60)
        logger.info("Starting Promotion Pipeline Test Suite")
        logger.info("=" * 60)
        
        total_start = time.time()
        
        try:
            # Test release creation
            self.results['release_creation'] = await self.test_release_creation()
            release_id = self.results['release_creation']['versions'][0]
            release = [r for r in self.pipeline.releases.values() if r.version == release_id][0]
            
            # Test promotion workflow
            self.results['promotion_workflow'] = await self.test_promotion_workflow(release.release_id)
            
            # Test rollback
            self.results['rollback'] = await self.test_rollback(release.release_id)
            
            # Test validation pipeline
            self.results['validation_pipeline'] = await self.test_validation_pipeline()
            
            # Get final stats
            self.results['final_stats'] = self.pipeline.get_stats()
            
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
        logger.info(f"Releases created: {self.results.get('final_stats', {}).get('total_releases', 0)}")
        logger.info(f"Rollback points: {self.results.get('final_stats', {}).get('rollback_points', 0)}")
        
        if 'error' in self.results:
            logger.error(f"Tests failed with error: {self.results['error']}")
        
        return self.results


async def main():
    """Main entry point."""
    hermes_home = Path(os.environ.get('HERMES_HOME', Path.home() / '.hermes'))
    
    test = PromotionPipelineTest(hermes_home=hermes_home)
    
    try:
        await test.setup()
        results = await test.run_all_tests()
        
        # Save results
        results_file = hermes_home / 'promotion' / 'pipeline_test_results.json'
        results_file.parent.mkdir(parents=True, exist_ok=True)
        results_file.write_text(json.dumps(results, indent=2))
        logger.info(f"Results saved to {results_file}")
        
        # Exit with error if tests failed
        if 'error' in results:
            sys.exit(1)
        
        logger.info("All promotion pipeline tests passed!")
        
    except Exception as e:
        logger.exception(f"Test failed: {e}")
        sys.exit(1)
    finally:
        await test.teardown()


if __name__ == "__main__":
    asyncio.run(main())
