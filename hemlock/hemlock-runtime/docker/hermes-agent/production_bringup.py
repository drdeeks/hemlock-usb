#!/usr/bin/env python3
"""
Production Runtime Bring-Up Script

Startup order:
1. Mount persistent volumes
2. Load runtime configuration
3. Load memory databases
4. Restore sessions
5. Restore agent identities
6. Load skills
7. Start MCP services
8. Start Hermes gateway
9. Connect Telegram/OpenClaw
10. Begin autonomous loops
"""

import asyncio
import json
import logging
import os
import signal
import sys
from datetime import datetime
from pathlib import Path
from typing import Dict

from paths import resolver

logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)

sys.path.insert(0, str(resolver.hermes_home))


class ProductionRuntime:
    """Production runtime bring-up manager."""
    
    def __init__(self):
        self.hermes_home = resolver.hermes_home
        self.agents_dir = resolver.agents_dir
        self.running = False
        self.components = {}
        self.startup_log = []
        
    def _log_startup(self, step: str, success: bool, details: str = ''):
        """Log startup step."""
        entry = {
            'step': step,
            'success': success,
            'details': details,
            'timestamp': datetime.now().isoformat()
        }
        self.startup_log.append(entry)
        
        status = "✓" if success else "✗"
        logger.info(f"{status} {step}: {details}")
        
    async def step_1_mount_volumes(self):
        """Step 1: Mount persistent volumes."""
        logger.info("=" * 60)
        logger.info("STEP 1: Mounting Persistent Volumes")
        logger.info("=" * 60)
        
        required_volumes = [
            self.hermes_home,
            self.hermes_home / 'sessions',
            self.hermes_home / 'memory',
            self.hermes_home / 'logs',
            self.hermes_home / 'state',
            self.hermes_home / 'checkpoints',
            self.agents_dir
        ]
        
        all_mounted = True
        for volume in required_volumes:
            if volume.exists():
                self._log_startup(
                    f"Volume: {volume}",
                    True,
                    f"{len(list(volume.glob('*')))} items"
                )
            else:
                try:
                    volume.mkdir(parents=True, exist_ok=True)
                    self._log_startup(f"Volume: {volume}", True, "created")
                except Exception as e:
                    self._log_startup(f"Volume: {volume}", False, str(e))
                    all_mounted = False
                    
        return all_mounted
        
    async def step_2_load_config(self):
        """Step 2: Load runtime configuration."""
        logger.info("=" * 60)
        logger.info("STEP 2: Loading Runtime Configuration")
        logger.info("=" * 60)
        
        try:
            config = {
                'HERMES_HOME': os.getenv('HERMES_HOME', str(self.hermes_home)),
                'ENABLE_PERSISTENT_MEMORY': os.getenv('ENABLE_PERSISTENT_MEMORY', 'true'),
                'ENABLE_AGENT_RESURRECTION': os.getenv('ENABLE_AGENT_RESURRECTION', 'true'),
                'ENABLE_CONTINUOUS_RUNTIME': os.getenv('ENABLE_CONTINUOUS_RUNTIME', 'true'),
                'ENABLE_SKILL_LEARNING': os.getenv('ENABLE_SKILL_LEARNING', 'true'),
            }
            
            self.components['config'] = config
            
            self._log_startup(
                "Configuration loaded",
                True,
                f"{len(config)} settings"
            )
            
            return True
            
        except Exception as e:
            self._log_startup("Configuration load", False, str(e))
            return False
            
    async def step_3_load_memory(self):
        """Step 3: Load memory databases."""
        logger.info("=" * 60)
        logger.info("STEP 3: Loading Memory Databases")
        logger.info("=" * 60)
        
        try:
            from cognition.memory_synthesis import MemorySynthesisEngine
            
            engine = MemorySynthesisEngine(hermes_home=self.hermes_home)
            stats = engine.get_memory_stats()
            
            self.components['memory_engine'] = engine
            
            self._log_startup(
                "Memory databases loaded",
                True,
                f"{stats['total_memories']} total memories"
            )
            
            return True
            
        except Exception as e:
            self._log_startup("Memory load", False, str(e))
            return False
            
    async def step_4_restore_sessions(self):
        """Step 4: Restore sessions."""
        logger.info("=" * 60)
        logger.info("STEP 4: Restoring Sessions")
        logger.info("=" * 60)
        
        try:
            from gateway.session_store import SessionStore
            
            store = SessionStore(hermes_home=self.hermes_home)
            sessions = store.list_sessions()
            
            self.components['session_store'] = store
            
            self._log_startup(
                "Sessions restored",
                True,
                f"{len(sessions)} sessions"
            )
            
            return True
            
        except Exception as e:
            self._log_startup("Session restore", False, str(e))
            return False
            
    async def step_5_restore_identities(self):
        """Step 5: Restore agent identities."""
        logger.info("=" * 60)
        logger.info("STEP 5: Restoring Agent Identities")
        logger.info("=" * 60)
        
        try:
            from identity.agent_identity import IdentityRestorationManager
            
            manager = IdentityRestorationManager(agents_dir=self.agents_dir)
            agents = manager.discover_agents()
            
            restored = manager.restore_all_agents()
            
            self.components['identity_manager'] = manager
            self.components['agents'] = restored
            
            self._log_startup(
                "Agent identities restored",
                True,
                f"{len(restored)} agents: {', '.join(agents)}"
            )
            
            return True
            
        except Exception as e:
            self._log_startup("Identity restore", False, str(e))
            return False
            
    async def step_6_load_skills(self):
        """Step 6: Load skills."""
        logger.info("=" * 60)
        logger.info("STEP 6: Loading Skills")
        logger.info("=" * 60)
        
        try:
            from cognition.skill_sandbox import SkillRegistry
            
            registry = SkillRegistry()
            stats = registry.get_registry_stats()
            
            self.components['skill_registry'] = registry
            
            self._log_startup(
                "Skills loaded",
                True,
                f"{stats['total_skills']} skills ({stats['active']} active)"
            )
            
            return True
            
        except Exception as e:
            self._log_startup("Skill load", False, str(e))
            return False
            
    async def step_7_start_mcp(self):
        """Step 7: Start MCP services."""
        logger.info("=" * 60)
        logger.info("STEP 7: Starting MCP Services")
        logger.info("=" * 60)
        
        try:
            from agent_brain_mcp import AgentBrainMCP
            
            mcp = AgentBrainMCP()
            
            self.components['mcp'] = mcp
            
            self._log_startup(
                "MCP services started",
                True,
                "Brain server ready"
            )
            
            return True
            
        except ImportError:
            self._log_startup("MCP services", False, "Not available (optional)")
            return True
            
        except Exception as e:
            self._log_startup("MCP start", False, str(e))
            return False
            
    async def step_8_start_gateway(self):
        """Step 8: Start Hermes gateway."""
        logger.info("=" * 60)
        logger.info("STEP 8: Starting Hermes Gateway")
        logger.info("=" * 60)
        
        try:
            from integration.openclaw_bridge import OpenClawHermesBridge
            
            bridge = OpenClawHermesBridge(
                hermes_home=self.hermes_home,
                agents_dir=self.agents_dir
            )
            
            self.components['gateway'] = bridge
            
            status = bridge.get_bridge_status()
            
            self._log_startup(
                "Hermes gateway started",
                True,
                f"Status: {status['status']}"
            )
            
            return True
            
        except Exception as e:
            self._log_startup("Gateway start", False, str(e))
            return False
            
    async def step_9_connect_transport(self):
        """Step 9: Connect Telegram/OpenClaw transport."""
        logger.info("=" * 60)
        logger.info("STEP 9: Connecting Transport Layer")
        logger.info("=" * 60)
        
        try:
            from integration.openclaw_bridge import TransportLayer
            
            bridge = self.components.get('gateway')
            if bridge:
                transport = TransportLayer(bridge)
                self.components['transport'] = transport
                
                self._log_startup(
                    "Transport layer connected",
                    True,
                    "Telegram/Discord ready"
                )
                
                return True
                
        except Exception as e:
            self._log_startup("Transport connect", False, str(e))
            return False
            
        self._log_startup("Transport connect", False, "Gateway not available")
        return False
        
    async def step_10_start_loops(self):
        """Step 10: Begin autonomous loops."""
        logger.info("=" * 60)
        logger.info("STEP 10: Starting Autonomous Loops")
        logger.info("=" * 60)
        
        try:
            coordinator = self.components.get('gateway')
            if coordinator and hasattr(coordinator, 'cognitive_coordinator'):
                cognitive = coordinator.cognitive_coordinator
                cognitive.running = True
                
                self.components['cognitive_loop'] = cognitive
                
                self._log_startup(
                    "Autonomous loops started",
                    True,
                    "Reflection, memory, skill generation active"
                )
                
                return True
                
        except Exception as e:
            self._log_startup("Loop start", False, str(e))
            return False
            
        self._log_startup("Loop start", False, "Cognitive coordinator not available")
        return False
        
    async def bring_up(self):
        """Execute full bring-up sequence."""
        logger.info("\n" + "=" * 60)
        logger.info("PRODUCTION RUNTIME BRING-UP")
        logger.info("Started: " + datetime.now().isoformat())
        logger.info("=" * 60 + "\n")
        
        self.running = True
        
        steps = [
            ("Mount Volumes", self.step_1_mount_volumes),
            ("Load Config", self.step_2_load_config),
            ("Load Memory", self.step_3_load_memory),
            ("Restore Sessions", self.step_4_restore_sessions),
            ("Restore Identities", self.step_5_restore_identities),
            ("Load Skills", self.step_6_load_skills),
            ("Start MCP", self.step_7_start_mcp),
            ("Start Gateway", self.step_8_start_gateway),
            ("Connect Transport", self.step_9_connect_transport),
            ("Start Loops", self.step_10_start_loops),
        ]
        
        results = []
        for name, step_func in steps:
            try:
                result = await step_func()
                results.append((name, result))
                
                if not result:
                    logger.warning(f"Step '{name}' failed - continuing...")
                    
            except Exception as e:
                logger.error(f"Step '{name}' crashed: {e}")
                results.append((name, False))
                
        self._print_startup_summary(results)
        
        return all(r for _, r in results)
        
    def _print_startup_summary(self, results):
        """Print startup summary."""
        logger.info("\n" + "=" * 60)
        logger.info("STARTUP SUMMARY")
        logger.info("=" * 60)
        
        passed = sum(1 for _, r in results if r)
        total = len(results)
        
        for name, result in results:
            status = "✓" if result else "✗"
            logger.info(f"  {status} {name}")
            
        logger.info(f"\nTotal: {passed}/{total} steps successful")
        
        if passed == total:
            logger.info("\n✓ PRODUCTION RUNTIME READY")
        else:
            logger.info(f"\n! PARTIAL STARTUP - {total - passed} steps failed")
            
        logger.info("=" * 60)
        
    def get_status(self) -> Dict:
        """Get runtime status."""
        return {
            'running': self.running,
            'components': list(self.components.keys()),
            'startup_log': self.startup_log,
            'timestamp': datetime.now().isoformat()
        }


async def main():
    """Main entry point."""
    runtime = ProductionRuntime()
    
    loop = asyncio.get_event_loop()
    
    def signal_handler():
        logger.info("\nShutting down...")
        runtime.running = False
        
    for sig in (signal.SIGTERM, signal.SIGINT):
        loop.add_signal_handler(sig, signal_handler)
    
    success = await runtime.bring_up()
    
    if success:
        logger.info("\nRuntime bring-up complete. Press Ctrl+C to stop.")
        
        while runtime.running:
            await asyncio.sleep(1)
    else:
        logger.warning("\nRuntime bring-up incomplete. Exiting.")
        sys.exit(1)


if __name__ == '__main__':
    asyncio.run(main())
