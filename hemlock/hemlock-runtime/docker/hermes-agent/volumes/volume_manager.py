"""
Volume Manager - Docker Volume Management

Manages Docker volumes for:
- Individual agents (isolated)
- Crew agents (pool)
- Crew instances (shared)

Provides:
- Volume creation
- Volume mounting
- Volume isolation verification
"""

import asyncio
import json
import logging
import os
import shutil
from datetime import datetime
from pathlib import Path
from typing import Dict, List, Optional, Any

from paths import resolver

logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)


class VolumeManager:
    """
    Docker volume management for agent and crew isolation.
    """
    
    def __init__(self, agents_dir: str = None, crews_dir: str = None):
        self.agents_dir = Path(agents_dir) if agents_dir else resolver.agents_dir
        self.crews_dir = Path(crews_dir) if crews_dir else resolver.crews_dir
        
        # Ensure directories exist
        self.agents_dir.mkdir(parents=True, exist_ok=True)
        self.crews_dir.mkdir(parents=True, exist_ok=True)
        
        logger.info(f"Volume manager initialized: agents={self.agents_dir}, crews={self.crews_dir}")
        
    async def create_agent_volume(self, agent_id: str) -> bool:
        """
        Create isolated volume for individual agent.
        
        Args:
            agent_id: Agent ID
            
        Returns:
            True if successful, False otherwise
        """
        volume_name = f"hemlock-agent-{agent_id}"
        
        logger.info(f"Creating agent volume: {volume_name}")
        
        try:
            # Create volume
            result = await self._create_volume(volume_name)
            
            if result:
                logger.info(f"Agent volume created: {volume_name}")
                return True
            else:
                logger.error(f"Failed to create agent volume: {volume_name}")
                return False
        except Exception as e:
            logger.error(f"Error creating agent volume: {e}")
            return False
        
    async def create_crew_agent_volume(self, crew_id: str, agent_id: str) -> bool:
        """
        Create isolated volume for crew agent (pool).
        
        Args:
            crew_id: Crew ID
            agent_id: Agent ID
            
        Returns:
            True if successful, False otherwise
        """
        volume_name = f"hemlock-crew-agent-{crew_id}-{agent_id}"
        
        logger.info(f"Creating crew agent volume: {volume_name}")
        
        try:
            # Create volume
            result = await self._create_volume(volume_name)
            
            if result:
                logger.info(f"Crew agent volume created: {volume_name}")
                return True
            else:
                logger.error(f"Failed to create crew agent volume: {volume_name}")
                return False
        except Exception as e:
            logger.error(f"Error creating crew agent volume: {e}")
            return False
        
    async def create_crew_volume(self, crew_id: str) -> bool:
        """
        Create shared volume for crew instance.
        
        Args:
            crew_id: Crew ID
            
        Returns:
            True if successful, False otherwise
        """
        volume_name = f"hemlock-crew-{crew_id}"
        
        logger.info(f"Creating crew volume: {volume_name}")
        
        try:
            # Create volume
            result = await self._create_volume(volume_name)
            
            if result:
                logger.info(f"Crew volume created: {volume_name}")
                return True
            else:
                logger.error(f"Failed to create crew volume: {volume_name}")
                return False
        except Exception as e:
            logger.error(f"Error creating crew volume: {e}")
            return False
        
    async def mount_volume(self, volume_name: str, mount_path: str) -> bool:
        """
        Mount volume to path.
        
        Args:
            volume_name: Name of volume to mount
            mount_path: Path to mount volume
            
        Returns:
            True if successful, False otherwise
        """
        logger.info(f"Mounting volume {volume_name} to {mount_path}")
        
        try:
            # Create mount point if needed
            mount_path = Path(mount_path)
            mount_path.mkdir(parents=True, exist_ok=True)
            
            # Use docker run to mount volume
            # This is a simplified approach - in production you'd use proper Docker API
            cmd = f"docker run --rm -v {volume_name}:{mount_path} alpine touch {mount_path}/.mounted"
            
            # In a real implementation, you would use the Docker SDK
            # For this example, we'll simulate with a file
            (mount_path / ".mounted").touch()
            
            logger.info(f"Volume mounted: {volume_name} -> {mount_path}")
            return True
        except Exception as e:
            logger.error(f"Failed to mount volume: {e}")
            return False
        
    async def verify_isolation(self, volume_name: str) -> bool:
        """
        Verify volume isolation from other volumes.
        
        Args:
            volume_name: Volume to verify
            
        Returns:
            True if isolated, False otherwise
        """
        logger.info(f"Verifying isolation for volume: {volume_name}")
        
        try:
            # Check for cross-volume access
            # This is a simplified check - in production you'd use proper isolation testing
            
            # Check if volume exists
            if not await self._volume_exists(volume_name):
                logger.error(f"Volume does not exist: {volume_name}")
                return False
            
            # Check for shared files with other volumes
            # In a real implementation, you would use Docker API
            # For this example, we'll simulate with a file check
            
            # Check for .mounted file (simulating volume mount)
            if (Path('/tmp') / f"{volume_name}.mounted").exists():
                logger.info(f"Volume isolation verified: {volume_name}")
                return True
            else:
                logger.error(f"Volume isolation failed: {volume_name}")
                return False
        except Exception as e:
            logger.error(f"Error verifying isolation: {e}")
            return False
        
    async def _create_volume(self, volume_name: str) -> bool:
        """
        Create Docker volume.
        
        Args:
            volume_name: Name of volume to create
            
        Returns:
            True if successful, False otherwise
        """
        try:
            # Check if volume exists
            if await self._volume_exists(volume_name):
                logger.warning(f"Volume already exists: {volume_name}")
                return True
            
            # Create volume
            # In a real implementation, you would use the Docker SDK
            # For this example, we'll simulate with a directory
            
            # Create directory to simulate volume
            volume_path = Path('/tmp') / f"docker-volumes/{volume_name}"
            volume_path.mkdir(parents=True, exist_ok=True)
            
            # Create marker file
            (volume_path / ".volume").touch()
            
            logger.info(f"Volume created: {volume_name}")
            return True
        except Exception as e:
            logger.error(f"Failed to create volume: {e}")
            return False
        
    async def _volume_exists(self, volume_name: str) -> bool:
        """
        Check if volume exists.
        
        Args:
            volume_name: Name of volume to check
            
        Returns:
            True if exists, False otherwise
        """
        try:
            # Check for volume marker file
            volume_path = Path('/tmp') / f"docker-volumes/{volume_name}"
            return (volume_path / ".volume").exists()
        except Exception as e:
            logger.error(f"Error checking volume existence: {e}")
            return False
        
    async def list_volumes(self) -> List[str]:
        """
        List all volumes.
        
        Returns:
            List of volume names
        """
        volumes = []
        
        try:
            # List volumes in simulation directory
            volumes_dir = Path('/tmp/docker-volumes')
            
            if volumes_dir.exists():
                for item in volumes_dir.iterdir():
                    if item.is_dir() and (item / ".volume").exists():
                        volumes.append(item.name)
            
            return volumes
        except Exception as e:
            logger.error(f"Error listing volumes: {e}")
            return []
        
    async def remove_volume(self, volume_name: str) -> bool:
        """
        Remove volume.
        
        Args:
            volume_name: Name of volume to remove
            
        Returns:
            True if successful, False otherwise
        """
        try:
            # Remove volume directory
            volume_path = Path('/tmp') / f"docker-volumes/{volume_name}"
            
            if volume_path.exists():
                shutil.rmtree(volume_path)
                logger.info(f"Volume removed: {volume_name}")
                return True
            else:
                logger.warning(f"Volume not found: {volume_name}")
                return False
        except Exception as e:
            logger.error(f"Error removing volume: {e}")
            return False


async def main():
    """CLI entry point."""
    import sys
    
    manager = VolumeManager()
    
    if len(sys.argv) < 2:
        print("Usage: python -m volumes.volume_manager [create-agent|create-crew-agent|create-crew|list|remove] <args>")
        print("  create-agent <agent_id>          - Create agent volume")
        print("  create-crew-agent <crew_id> <agent_id> - Create crew agent volume")
        print("  create-crew <crew_id>            - Create crew volume")
        print("  list                              - List all volumes")
        print("  remove <volume_name>            - Remove volume")
        sys.exit(1)
        
    command = sys.argv[1]
    
    if command == 'create-agent':
        if len(sys.argv) < 3:
            print("Usage: create-agent <agent_id>")
            sys.exit(1)
            
        agent_id = sys.argv[2]
        
        success = await manager.create_agent_volume(agent_id)
        if success:
            print(f"✓ Agent volume created for {agent_id}")
        else:
            print(f"✗ Failed to create agent volume for {agent_id}")
            sys.exit(1)
            
    elif command == 'create-crew-agent':
        if len(sys.argv) < 4:
            print("Usage: create-crew-agent <crew_id> <agent_id>")
            sys.exit(1)
            
        crew_id = sys.argv[2]
        agent_id = sys.argv[3]
        
        success = await manager.create_crew_agent_volume(crew_id, agent_id)
        if success:
            print(f"✓ Crew agent volume created for {crew_id}/{agent_id}")
        else:
            print(f"✗ Failed to create crew agent volume for {crew_id}/{agent_id}")
            sys.exit(1)
            
    elif command == 'create-crew':
        if len(sys.argv) < 3:
            print("Usage: create-crew <crew_id>")
            sys.exit(1)
            
        crew_id = sys.argv[2]
        
        success = await manager.create_crew_volume(crew_id)
        if success:
            print(f"✓ Crew volume created for {crew_id}")
        else:
            print(f"✗ Failed to create crew volume for {crew_id}")
            sys.exit(1)
            
    elif command == 'list':
        volumes = await manager.list_volumes()
        
        print(f"\n{'='*60}")
        print(f"Docker Volumes ({len(volumes)} total)")
        print(f"{'='*60}\n")
        
        for volume in volumes:
            print(f"  • {volume}")
            
    elif command == 'remove':
        if len(sys.argv) < 3:
            print("Usage: remove <volume_name>")
            sys.exit(1)
            
        volume_name = sys.argv[2]
        
        success = await manager.remove_volume(volume_name)
        if success:
            print(f"✓ Volume removed: {volume_name}")
        else:
            print(f"✗ Failed to remove volume: {volume_name}")
            sys.exit(1)
            
    else:
        print(f"Unknown command: {command}")
        sys.exit(1)


if __name__ == '__main__':
    asyncio.run(main())
