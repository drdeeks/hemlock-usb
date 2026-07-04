"""
Runtime Daemon Manager - Continuous agent cognition and gateway lifecycle.

This module provides:
- Continuous gateway runtime with automatic restart
- Session resurrection on startup
- Memory preload during boot
- Agent identity restoration
- Health monitoring and recovery
"""

import asyncio
import json
import logging
import os
import signal
import sys
import time
from datetime import datetime
from pathlib import Path
from typing import Dict, Optional, Any, List

from hermes_constants import get_hermes_home

logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)


class RuntimeDaemon:
    """Manages continuous Hermes runtime with persistent cognition."""
    
    def __init__(self, hermes_home: Optional[Path] = None):
        self.hermes_home = hermes_home or get_hermes_home()
        self.sessions_dir = self.hermes_home / 'sessions'
        self.memory_dir = self.hermes_home / 'memory'
        self.agents_dir = Path('/agents')
        self.state_dir = self.hermes_home / 'state'
        self.checkpoints_dir = self.hermes_home / 'checkpoints'
        self.logs_dir = self.hermes_home / 'logs'
        
        self.running = False
        self.gateway_task = None
        self.agents = {}
        self.last_checkpoint = None
        
        self._ensure_directories()
        
    def _ensure_directories(self):
        """Create required runtime directories."""
        for directory in [
            self.sessions_dir,
            self.memory_dir,
            self.state_dir,
            self.checkpoints_dir,
            self.logs_dir,
            self.agents_dir
        ]:
            directory.mkdir(parents=True, exist_ok=True)
            
    def _load_runtime_config(self) -> Dict[str, Any]:
        """Load runtime configuration from environment and config files."""
        config = {
            'enable_persistent_memory': os.getenv('ENABLE_PERSISTENT_MEMORY', 'true').lower() == 'true',
            'enable_agent_resurrection': os.getenv('ENABLE_AGENT_RESURRECTION', 'true').lower() == 'true',
            'enable_continuous_runtime': os.getenv('ENABLE_CONTINUOUS_RUNTIME', 'true').lower() == 'true',
            'enable_skill_learning': os.getenv('ENABLE_SKILL_LEARNING', 'true').lower() == 'true',
            'enable_memory_feedback': os.getenv('ENABLE_MEMORY_FEEDBACK', 'true').lower() == 'true',
            'enable_session_recovery': os.getenv('ENABLE_SESSION_RECOVERY', 'true').lower() == 'true',
        }
        
        config_path = self.hermes_home / 'config.yaml'
        if config_path.exists():
            try:
                import yaml
                with open(config_path) as f:
                    yaml_config = yaml.safe_load(f) or {}
                config.update(yaml_config.get('runtime', {}))
            except Exception as e:
                logger.warning(f"Failed to load config.yaml: {e}")
                
        return config
    
    def _restore_sessions(self) -> Dict[str, Any]:
        """Restore existing sessions from persistent storage."""
        sessions = {}
        
        if not self.sessions_dir.exists():
            logger.info("No sessions directory found - starting fresh")
            return sessions
            
        for session_file in self.sessions_dir.glob('*.json'):
            try:
                with open(session_file) as f:
                    session_data = json.load(f)
                session_id = session_file.stem
                sessions[session_id] = session_data
                logger.info(f"Restored session: {session_id}")
            except Exception as e:
                logger.error(f"Failed to restore session {session_file}: {e}")
                
        logger.info(f"Restored {len(sessions)} sessions")
        return sessions
    
    def _preload_memory(self) -> Dict[str, Any]:
        """Preload memory databases during boot."""
        memory = {
            'short_term': [],
            'long_term': [],
            'summaries': [],
            'reflections': []
        }
        
        memory_runtime_dir = self.memory_dir / 'runtime'
        if memory_runtime_dir.exists():
            for memory_file in memory_runtime_dir.glob('*.json'):
                try:
                    with open(memory_file) as f:
                        memory_data = json.load(f)
                    memory_type = memory_file.stem
                    if memory_type in memory:
                        memory[memory_type] = memory_data
                    logger.info(f"Preloaded memory: {memory_type}")
                except Exception as e:
                    logger.error(f"Failed to preload memory {memory_file}: {e}")
                    
        logger.info("Memory preload complete")
        return memory
    
    def _restore_agent_identities(self) -> Dict[str, Dict]:
        """Restore individualized agent identities."""
        agents = {}
        
        if not self.agents_dir.exists():
            logger.info("No agents directory found")
            return agents
            
        for agent_dir in self.agents_dir.iterdir():
            if not agent_dir.is_dir():
                continue
                
            agent_id = agent_dir.name
            identity_file = agent_dir / 'identity.md'
            state_file = agent_dir / 'state' / 'current_state.json'
            
            agent_data = {
                'id': agent_id,
                'directory': agent_dir,
                'identity': None,
                'state': None,
                'skills': [],
                'memory': {}
            }
            
            if identity_file.exists():
                with open(identity_file) as f:
                    agent_data['identity'] = f.read()
                logger.info(f"Restored agent identity: {agent_id}")
                
            if state_file.exists():
                try:
                    with open(state_file) as f:
                        agent_data['state'] = json.load(f)
                except Exception as e:
                    logger.error(f"Failed to load state for {agent_id}: {e}")
                    
            skills_dir = agent_dir / 'skills'
            if skills_dir.exists():
                agent_data['skills'] = [s.stem for s in skills_dir.glob('*.py')]
                
            agents[agent_id] = agent_data
            
        logger.info(f"Restored {len(agents)} agent identities")
        return agents
    
    def _save_checkpoint(self, state: Dict[str, Any]):
        """Save runtime checkpoint for recovery."""
        timestamp = datetime.now().strftime('%Y%m%d_%H%M%S')
        checkpoint_file = self.checkpoints_dir / f'checkpoint_{timestamp}.json'
        
        try:
            with open(checkpoint_file, 'w') as f:
                json.dump({
                    'timestamp': timestamp,
                    'state': state
                }, f, indent=2)
                
            self.last_checkpoint = checkpoint_file
            logger.info(f"Saved checkpoint: {checkpoint_file}")
        except Exception as e:
            logger.error(f"Failed to save checkpoint: {e}")
            
    def _cleanup_old_checkpoints(self, keep_count: int = 10):
        """Keep only recent checkpoints to save space."""
        checkpoints = sorted(self.checkpoints_dir.glob('checkpoint_*.json'))
        
        if len(checkpoints) > keep_count:
            for old_checkpoint in checkpoints[:-keep_count]:
                try:
                    old_checkpoint.unlink()
                    logger.debug(f"Removed old checkpoint: {old_checkpoint}")
                except Exception as e:
                    logger.warning(f"Failed to remove checkpoint {old_checkpoint}: {e}")
                    
    async def _run_gateway(self):
        """Run the Hermes gateway continuously."""
        from gateway.run import start_gateway
        
        while self.running:
            try:
                logger.info("Starting Hermes gateway...")
                await start_gateway()
            except Exception as e:
                logger.error(f"Gateway error: {e}")
                if self.running:
                    logger.info("Restarting gateway in 5 seconds...")
                    await asyncio.sleep(5)
                    
    async def _periodic_checkpoint(self, interval: int = 300):
        """Save periodic checkpoints."""
        while self.running:
            await asyncio.sleep(interval)
            
            state = {
                'agents': list(self.agents.keys()),
                'sessions_count': len(list(self.sessions_dir.glob('*.json'))),
                'timestamp': datetime.now().isoformat()
            }
            
            self._save_checkpoint(state)
            self._cleanup_old_checkpoints()
            
    async def _health_monitor(self, interval: int = 60):
        """Monitor runtime health."""
        while self.running:
            await asyncio.sleep(interval)
            
            health = {
                'timestamp': datetime.now().isoformat(),
                'agents_active': len(self.agents),
                'sessions_count': len(list(self.sessions_dir.glob('*.json'))),
                'memory_size': sum(f.stat().st_size for f in self.memory_dir.rglob('*') if f.is_file()),
                'last_checkpoint': str(self.last_checkpoint) if self.last_checkpoint else None
            }
            
            health_file = self.state_dir / 'health.json'
            try:
                with open(health_file, 'w') as f:
                    json.dump(health, f, indent=2)
            except Exception as e:
                logger.error(f"Failed to write health status: {e}")
                
            logger.debug(f"Health: {health}")
            
    async def start(self):
        """Start the runtime daemon."""
        logger.info("Starting Hermes Runtime Daemon...")
        
        config = self._load_runtime_config()
        logger.info(f"Runtime config: {config}")
        
        if config['enable_session_recovery']:
            sessions = self._restore_sessions()
            
        if config['enable_persistent_memory']:
            memory = self._preload_memory()
            
        if config['enable_agent_resurrection']:
            self.agents = self._restore_agent_identities()
            
        self.running = True
        
        tasks = [
            asyncio.create_task(self._run_gateway()),
            asyncio.create_task(self._periodic_checkpoint()),
            asyncio.create_task(self._health_monitor())
        ]
        
        logger.info("Runtime daemon started - all systems operational")
        
        try:
            await asyncio.gather(*tasks)
        except asyncio.CancelledError:
            logger.info("Runtime daemon shutting down...")
        finally:
            self.running = False
            
    def stop(self):
        """Stop the runtime daemon."""
        logger.info("Stopping runtime daemon...")
        self.running = False
        
        final_state = {
            'agents': list(self.agents.keys()),
            'shutdown_time': datetime.now().isoformat(),
            'last_checkpoint': str(self.last_checkpoint) if self.last_checkpoint else None
        }
        
        self._save_checkpoint(final_state)
        logger.info("Runtime daemon stopped")


async def main():
    """Entry point for runtime daemon."""
    daemon = RuntimeDaemon()
    
    loop = asyncio.get_event_loop()
    
    for sig in (signal.SIGTERM, signal.SIGINT):
        loop.add_signal_handler(
            sig,
            lambda: asyncio.create_task(daemon.stop())
        )
    
    try:
        await daemon.start()
    except KeyboardInterrupt:
        await daemon.stop()


if __name__ == '__main__':
    asyncio.run(main())
