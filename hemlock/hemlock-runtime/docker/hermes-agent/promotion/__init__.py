"""
Hermes Promotion Pipeline

Multi-stage promotion workflow for framework releases.

Components:
- PromotionPipeline: Stage management and validation
- Rollback mechanisms
- Release versioning
- Deployment audit logging

Usage:
    from promotion import initialize_pipeline, get_pipeline
    
    # Initialize
    pipeline = await initialize_pipeline()
    
    # Create release
    release = await pipeline.create_release(
        version="1.2.0",
        image_tag="openclaw/framework:1.2.0",
        changelog=["Feature X", "Bug fix Y"]
    )
    
    # Promote through stages
    await pipeline.promote_release(release.release_id, PromotionStage.STAGING)
    await pipeline.promote_release(release.release_id, PromotionStage.PROD, approved_by="admin")
    
    # Rollback if needed
    await pipeline.rollback(PromotionStage.PROD)
"""

from .pipeline_manager import (
    PromotionPipeline,
    Release,
    RollbackPoint,
    PromotionStage,
    PromotionStatus,
    get_pipeline,
    initialize_pipeline,
)

__all__ = [
    'PromotionPipeline',
    'Release',
    'RollbackPoint',
    'PromotionStage',
    'PromotionStatus',
    'get_pipeline',
    'initialize_pipeline',
]
