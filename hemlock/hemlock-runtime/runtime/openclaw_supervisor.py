#!/usr/bin/env python3
"""
OpenClaw Supervisor - Enterprise Multi-Agent Runtime Controller

Responsibilities:
- Runtime spawning and lifecycle management
- Hermes activation and configuration
- Telegram routing via OpenClaw Gateway
- MCP routing and tool execution fabric
- Health monitoring and recovery
- Memory/soul injection
- Telemetry collection
- Export/import management
- Backup/recovery
- Queue management
- Crew synchronization

Architecture:
    OpenClaw (Control Plane) -> This Supervisor -> Hermes (Cognition Layer) -> MCP (Tool Fabric)
"""

import asyncio
import json
import logging
import os
import signal
import subprocess
import sys
import time
from pathlib import Path
from typing import Any, Dict, List, Optional

try:
    from paths import resolver
    _HAS_RESOLVER = True
except ImportError:
    _HAS_RESOLVER = False

# Configure logging
_log_dir = Path(os.getenv("OPENCLAW_LOGS", "/var/log/openclaw"))
_log_dir.mkdir(parents=True, exist_ok=True)
logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s - %(name)s - %(levelname)s - %(message)s",
    handlers=[
        logging.StreamHandler(sys.stdout),
        logging.FileHandler(str(_log_dir / "supervisor.log")),
    ],
)
logger = logging.getLogger("openclaw.supervisor")


class OpenClawSupervisor:
    """Main supervisor class for OpenClaw enterprise runtime."""

    def __init__(self):
        self.running = False
        self.hermes_process: Optional[subprocess.Popen] = None
        self.agent_processes: Dict[str, subprocess.Popen] = {}
        self.shutdown_event = asyncio.Event()
        self.config = self._load_config()
        self._setup_paths()

    def _load_config(self) -> Dict[str, Any]:
        """Load supervisor configuration."""
        config_path = Path(os.getenv("OPENCLAW_CONFIG", "/etc/openclaw/supervisor.json"))
        if _HAS_RESOLVER:
            default_runtime = str(resolver.hermes_home)
            default_agents = str(resolver.agents_dir)
            default_registry = str(resolver.skills_root)
            default_memory = str(resolver.memory_dir / "volumes" / "memory")
            default_souls = str(resolver.memory_dir / "volumes" / "souls")
            default_trajectories = str(resolver.memory_dir / "volumes" / "trajectories")
            default_exports = str(resolver.memory_dir / "volumes" / "exports")
            default_runtime_routing = str(resolver.root / "runtime" / "routing")
            default_runtime_orchestration = str(resolver.root / "runtime" / "orchestration")
            default_runtime_queues = str(resolver.root / "runtime" / "queues")
        else:
            default_runtime = "/opt/hermes"
            default_agents = "/agents"
            default_registry = "/srv/framework/shared/skills"
            default_memory = "/srv/framework/volumes/memory"
            default_souls = "/srv/framework/volumes/souls"
            default_trajectories = "/srv/framework/volumes/trajectories"
            default_exports = "/srv/framework/volumes/exports"
            default_runtime_routing = "/srv/framework/runtime/routing"
            default_runtime_orchestration = "/srv/framework/runtime/orchestration"
            default_runtime_queues = "/srv/framework/runtime/queues"

        default_config = {
            "hermes": {
                "enabled": True,
                "gateway_port": 8080,
                "runtime_path": default_runtime,
                "cli_entry": "hermes",
            },
            "openclaw": {
                "gateway_host": "0.0.0.0",
                "gateway_port": 8000,
                "router_enabled": True,
            },
            "agents": {
                "max_concurrent": 10,
                "timeout": 3600,
                "default_identity": "default",
            },
            "mcp": {
                "enabled": True,
                "registry_path": default_registry,
                "timeout": 30,
            },
            "volumes": {
                "memory": default_memory,
                "souls": default_souls,
                "trajectories": default_trajectories,
                "exports": default_exports,
            },
            "telemetry": {
                "enabled": True,
                "metrics_port": 9090,
            },
        }
        
        if config_path.exists():
            try:
                with open(config_path) as f:
                    return {**default_config, **json.load(f)}
            except Exception as e:
                logger.error(f"Failed to load config: {e}")
        
        return default_config

    def _setup_paths(self):
        """Setup required filesystem paths."""
        if _HAS_RESOLVER:
            paths = [
                str(resolver.logs_dir),
                str(resolver.config_dir),
                self.config["volumes"]["memory"],
                self.config["volumes"]["souls"],
                self.config["volumes"]["trajectories"],
                self.config["volumes"]["exports"],
                self.config["mcp"]["registry_path"],
            ]
        else:
            paths = [
                "/var/log/openclaw",
                "/etc/openclaw",
                self.config["volumes"]["memory"],
                self.config["volumes"]["souls"],
                self.config["volumes"]["trajectories"],
                self.config["volumes"]["exports"],
                self.config["mcp"]["registry_path"],
                "/srv/framework/runtime/routing",
                "/srv/framework/runtime/orchestration",
                "/srv/framework/runtime/queues",
            ]
        for path in paths:
            Path(path).mkdir(parents=True, exist_ok=True)

    def _start_hermes_gateway(self) -> bool:
        """Start Hermes gateway runtime."""
        try:
            hermes_path = Path(self.config["hermes"]["runtime_path"])
            gateway_script = hermes_path / "gateway" / "run.py"
            
            if not gateway_script.exists():
                # Try alternative path
                gateway_script = hermes_path / "hermes_cli" / "hermes_cli" / "gateway.py"
            
            if gateway_script.exists():
                cmd = [
                    sys.executable,
                    str(gateway_script),
                    "--port", str(self.config["hermes"]["gateway_port"]),
                    "--host", str(self.config["openclaw"]["gateway_host"]),
                ]
                self.hermes_process = subprocess.Popen(
                    cmd,
                    stdout=subprocess.PIPE,
                    stderr=subprocess.PIPE,
                    cwd=hermes_path,
                    env={**os.environ, "PYTHONPATH": str(hermes_path), "HERMES_HOME": str(hermes_path)},
                )
                logger.info(f"Hermes Gateway started (PID: {self.hermes_process.pid})")
                return True
            else:
                logger.warning(f"Hermes gateway script not found: {gateway_script}")
                # Try running via hermes CLI
                cmd = [
                    "hermes",
                    "gateway",
                    "--port", str(self.config["hermes"]["gateway_port"]),
                ]
                self.hermes_process = subprocess.Popen(cmd)
                logger.info(f"Hermes Gateway started via CLI (PID: {self.hermes_process.pid})")
                return True
        except Exception as e:
            logger.error(f"Failed to start Hermes Gateway: {e}")
            return False

    def _start_agent(self, agent_id: str, identity: str = None) -> bool:
        """Start an isolated agent process."""
        try:
            hermes_path = Path(self.config["hermes"]["runtime_path"])
            run_agent_script = hermes_path / "run_agent.py"
            
            if not run_agent_script.exists():
                run_agent_script = hermes_path / "hermes_cli" / "run_agent.py"
            
            identity = identity or self.config["agents"]["default_identity"]
            soul_path = Path(self.config["volumes"]["souls"]) / f"{identity}.json"
            memory_path = Path(self.config["volumes"]["memory"]) / f"{agent_id}.json"
            trajectory_path = Path(self.config["volumes"]["trajectories"]) / f"{agent_id}.jsonl"
            
            cmd = [
                sys.executable,
                str(run_agent_script),
                "--agent-id", agent_id,
                "--identity", identity,
                "--soul-path", str(soul_path) if soul_path.exists() else "",
                "--memory-path", str(memory_path),
                "--trajectory-path", str(trajectory_path),
                "--skills-path", str(Path(self.config["mcp"]["registry_path"]) / identity),
                "--shared-skills-path", self.config["mcp"]["registry_path"],
            ]
            
            proc = subprocess.Popen(
                cmd,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                cwd=hermes_path,
                env={**os.environ, "PYTHONPATH": str(hermes_path), "HERMES_HOME": str(hermes_path)},
            )
            self.agent_processes[agent_id] = proc
            logger.info(f"Agent {agent_id} started (PID: {proc.pid})")
            return True
        except Exception as e:
            logger.error(f"Failed to start agent {agent_id}: {e}")
            return False

    def _start_openclaw_router(self) -> bool:
        """Start OpenClaw router for Telegram routing."""
        try:
            runtime_routing = os.getenv("OPENCLAW_RUNTIME", "/srv/framework") + "/runtime/routing/router.py"
            router_script = Path(runtime_routing)
            if router_script.exists():
                cmd = [
                    sys.executable,
                    str(router_script),
                    "--host", self.config["openclaw"]["gateway_host"],
                    "--port", str(self.config["openclaw"]["gateway_port"]),
                    "--hermes-port", str(self.config["hermes"]["gateway_port"]),
                ]
                self.router_process = subprocess.Popen(cmd)
                logger.info(f"OpenClaw Router started (PID: {self.router_process.pid})")
                return True
            else:
                logger.warning("OpenClaw Router script not found, skipping")
            return False
        except Exception as e:
            logger.error(f"Failed to start OpenClaw Router: {e}")
            return False

    def _start_mcp_registry(self) -> bool:
        """Start MCP registry server."""
        try:
            runtime_orchestration = os.getenv("OPENCLAW_RUNTIME", "/srv/framework") + "/runtime/orchestration/mcp_registry.py"
            registry_script = Path(runtime_orchestration)
            if registry_script.exists():
                cmd = [
                    sys.executable,
                    str(registry_script),
                    "--path", self.config["mcp"]["registry_path"],
                    "--port", "8081",
                ]
                self.mcp_process = subprocess.Popen(cmd)
                logger.info(f"MCP Registry started (PID: {self.mcp_process.pid})")
                return True
            return False
        except Exception as e:
            logger.error(f"Failed to start MCP Registry: {e}")
            return False

    def start(self):
        """Start all supervisor services."""
        logger.info("Starting OpenClaw Supervisor...")
        self.running = True
        self.shutdown_event.clear()

        # Initialize filesystem
        self._setup_paths()

        # Start core services
        services_started = []
        
        if self.config["mcp"]["enabled"]:
            if self._start_mcp_registry():
                services_started.append("MCP Registry")

        if self.config["hermes"]["enabled"]:
            if self._start_hermes_gateway():
                services_started.append("Hermes Gateway")

        if self.config["openclaw"]["router_enabled"]:
            if self._start_openclaw_router():
                services_started.append("OpenClaw Router")

        # Start default agents
        default_agents = ["hermes-main"]
        for agent_id in default_agents:
            self._start_agent(agent_id)
            services_started.append(f"Agent: {agent_id}")

        logger.info(f"Supervisor started with services: {', '.join(services_started)}")
        logger.info("OpenClaw Enterprise Runtime is now operational")

    def stop(self):
        """Stop all supervisor services."""
        logger.info("Stopping OpenClaw Supervisor...")
        self.running = False
        self.shutdown_event.set()

        # Stop agent processes
        for agent_id, proc in self.agent_processes.items():
            if proc and proc.poll() is None:
                proc.terminate()
                try:
                    proc.wait(timeout=5)
                except subprocess.TimeoutExpired:
                    proc.kill()
                logger.info(f"Agent {agent_id} stopped")

        # Stop Hermes process
        if self.hermes_process and self.hermes_process.poll() is None:
            self.hermes_process.terminate()
            try:
                self.hermes_process.wait(timeout=5)
            except subprocess.TimeoutExpired:
                self.hermes_process.kill()
            logger.info("Hermes Gateway stopped")

        # Stop router if exists
        if hasattr(self, 'router_process') and self.router_process:
            self.router_process.terminate()
            try:
                self.router_process.wait(timeout=5)
            except subprocess.TimeoutExpired:
                self.router_process.kill()

        # Stop MCP registry if exists
        if hasattr(self, 'mcp_process') and self.mcp_process:
            self.mcp_process.terminate()
            try:
                self.mcp_process.wait(timeout=5)
            except subprocess.TimeoutExpired:
                self.mcp_process.kill()

        logger.info("OpenClaw Supervisor stopped")

    def health_check(self) -> Dict[str, Any]:
        """Perform health check on all services."""
        health = {
            "supervisor": "healthy",
            "timestamp": time.time(),
            "services": {},
        }

        # Check Hermes
        if self.hermes_process:
            health["services"]["hermes"] = {
                "status": "healthy" if self.hermes_process.poll() is None else "unhealthy",
                "pid": self.hermes_process.pid if self.hermes_process else None,
            }
        else:
            health["services"]["hermes"] = {"status": "not_started"}

        # Check agents
        health["services"]["agents"] = {}
        for agent_id, proc in self.agent_processes.items():
            health["services"]["agents"][agent_id] = {
                "status": "healthy" if proc and proc.poll() is None else "unhealthy",
                "pid": proc.pid if proc else None,
            }

        return health

    def spawn_agent(self, agent_id: str, identity: str = None, soul: Dict = None) -> bool:
        """Spawn a new agent with optional soul injection."""
        logger.info(f"Spawning agent: {agent_id}")
        
        if soul:
            soul_path = Path(self.config["volumes"]["souls"]) / f"{identity or agent_id}.json"
            soul_path.parent.mkdir(parents=True, exist_ok=True)
            with open(soul_path, "w") as f:
                json.dump(soul, f, indent=2)
            logger.info(f"Soul injected for agent {agent_id}")

        return self._start_agent(agent_id, identity)

    def backup_agent(self, agent_id: str, export_path: str = None) -> bool:
        """Backup agent state (memory, soul, trajectory)."""
        try:
            export_path = export_path or str(Path(self.config["volumes"]["exports"]) / f"{agent_id}_{int(time.time())}.tar.gz")
            
            memory_path = Path(self.config["volumes"]["memory"]) / f"{agent_id}.json"
            trajectory_path = Path(self.config["volumes"]["trajectories"]) / f"{agent_id}.jsonl"
            
            # Simple tar.gz backup
            cmd = ["tar", "czf", export_path]
            files_to_backup = []
            if memory_path.exists():
                files_to_backup.append(str(memory_path))
            if trajectory_path.exists():
                files_to_backup.append(str(trajectory_path))
            
            if files_to_backup:
                cmd.extend(files_to_backup)
                subprocess.run(cmd, check=True)
                logger.info(f"Agent {agent_id} backed up to {export_path}")
                return True
            else:
                logger.warning(f"No state files found for agent {agent_id}")
                return False
        except Exception as e:
            logger.error(f"Failed to backup agent {agent_id}: {e}")
            return False

    async def run(self):
        """Main async runtime loop."""
        self.start()
        
        try:
            while self.running and not self.shutdown_event.is_set():
                # Health check every 30 seconds
                await asyncio.sleep(30)
                health = self.health_check()
                logger.debug(f"Health check: {json.dumps(health, indent=2)}")
                
                # Auto-recover failed agents
                for agent_id, proc in list(self.agent_processes.items()):
                    if proc and proc.poll() is not None:
                        logger.warning(f"Agent {agent_id} crashed, restarting...")
                        self._start_agent(agent_id)
                        
        except KeyboardInterrupt:
            logger.info("Received interrupt signal")
        except Exception as e:
            logger.error(f"Runtime error: {e}")
        finally:
            self.stop()


def handle_signals(supervisor: OpenClawSupervisor):
    """Handle OS signals for graceful shutdown."""
    def signal_handler(sig, frame):
        logger.info(f"Received signal {sig}, shutting down...")
        supervisor.stop()
        sys.exit(0)
    
    signal.signal(signal.SIGINT, signal_handler)
    signal.signal(signal.SIGTERM, signal_handler)


def main():
    """Main entrypoint."""
    supervisor = OpenClawSupervisor()
    handle_signals(supervisor)
    
    # Run sync for compatibility
    try:
        asyncio.run(supervisor.run())
    except KeyboardInterrupt:
        supervisor.stop()


if __name__ == "__main__":
    main()
