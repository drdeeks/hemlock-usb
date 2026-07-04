#!/usr/bin/env python3
"""
OpenClaw Supervisor - Enterprise Runtime Controller

Responsibilities:
- Runtime spawning
- Hermes activation
- Telegram routing
- MCP routing
- Health monitoring
- Memory injection
- Soul injection
- Telemetry
- Export/import
- Backup/recovery
- Queue management
- Crew synchronization

Architecture:
OpenClaw (orchestration) -> This Supervisor -> Hermes (runtime) -> MCP (tools)
"""

import os
import sys
import json
import time
import logging
import subprocess
import threading
from pathlib import Path
from typing import Dict, List, Optional, Any
from dataclasses import dataclass, field
from enum import Enum
import queue
import uuid
import signal

# =============================================================================
# Configuration
# =============================================================================

class Config:
    # Paths (configurable via environment variables)
    FRAMEWORK_ROOT = Path(os.getenv("OPENCLAW_ROOT", "/srv/framework"))
    HERMES_ROOT = Path(os.getenv("HERMES_HOME", "/opt/hermes"))
    AGENTS_DIR = Path(os.getenv("HERMES_AGENTS", str(FRAMEWORK_ROOT / "agents")))
    SHARED_SKILLS = Path(os.getenv("HERMES_SKILLS", str(FRAMEWORK_ROOT / "shared" / "skills")))
    VOLUMES_DIR = FRAMEWORK_ROOT / "volumes"
    
    # Runtime
    MAX_AGENTS = 10
    AGENT_TIMEOUT = 3600  # 1 hour
    HEALTH_CHECK_INTERVAL = 30  # seconds
    
    # Logging
    LOG_LEVEL = logging.INFO
    LOG_FORMAT = "%(asctime)s - %(name)s - %(levelname)s - %(message)s"


# Initialize logging
logging.basicConfig(
    level=Config.LOG_LEVEL,
    format=Config.LOG_FORMAT,
    handlers=[
        logging.StreamHandler(sys.stdout),
        logging.FileHandler(Config.FRAMEWORK_ROOT / "logs" / "supervisor.log")
    ]
)
logger = logging.getLogger("openclaw.supervisor")


# =============================================================================
# Data Models
# =============================================================================

class AgentStatus(Enum):
    PENDING = "pending"
    STARTING = "starting"
    RUNNING = "running"
    STOPPING = "stopping"
    FAILED = "failed"
    COMPLETED = "completed"


@dataclass
class AgentConfig:
    id: str
    name: str
    soul_path: Optional[Path] = None
    memory_path: Optional[Path] = None
    skills: List[str] = field(default_factory=list)
    env: Dict[str, str] = field(default_factory=dict)
    timeout: int = Config.AGENT_TIMEOUT
    
    @classmethod
    def from_json(cls, data: Dict[str, Any]) -> "AgentConfig":
        return cls(
            id=data.get("id", str(uuid.uuid4())),
            name=data["name"],
            soul_path=Path(data["soul_path"]) if data.get("soul_path") else None,
            memory_path=Path(data["memory_path"]) if data.get("memory_path") else None,
            skills=data.get("skills", []),
            env=data.get("env", {}),
            timeout=data.get("timeout", Config.AGENT_TIMEOUT)
        )


@dataclass
class AgentInstance:
    config: AgentConfig
    status: AgentStatus = AgentStatus.PENDING
    process: Optional[subprocess.Popen] = None
    start_time: Optional[float] = None
    last_heartbeat: Optional[float] = None
    port: Optional[int] = None
    errors: List[str] = field(default_factory=list)
    
    def is_alive(self) -> bool:
        if self.process is None:
            return False
        return self.process.poll() is None
    
    def runtime_elapsed(self) -> float:
        if self.start_time is None:
            return 0.0
        return time.time() - self.start_time


@dataclass
class TelegramMessage:
    chat_id: str
    text: str
    message_id: Optional[int] = None
    user: Optional[Dict[str, Any]] = None
    timestamp: float = field(default_factory=time.time)


@dataclass
class MCPTask:
    task_id: str
    agent_id: str
    tool_name: str
    arguments: Dict[str, Any]
    timeout: int = 300
    
    @classmethod
    def from_json(cls, data: Dict[str, Any]) -> "MCPTask":
        return cls(
            task_id=data.get("task_id", str(uuid.uuid4())),
            agent_id=data["agent_id"],
            tool_name=data["tool_name"],
            arguments=data.get("arguments", {}),
            timeout=data.get("timeout", 300)
        )


# =============================================================================
# Queues
# =============================================================================

class MessageQueue:
    """Thread-safe queue for inter-process communication"""
    
    def __init__(self):
        self._queue: queue.Queue = queue.Queue()
        self._lock = threading.Lock()
    
    def put(self, item: Any) -> None:
        with self._lock:
            self._queue.put(item)
    
    def get(self, block: bool = True, timeout: Optional[float] = None) -> Any:
        with self._lock:
            try:
                return self._queue.get(block=block, timeout=timeout)
            except queue.Empty:
                return None
    
    def empty(self) -> bool:
        with self._lock:
            return self._queue.empty()
    
    def size(self) -> int:
        with self._lock:
            return self._queue.qsize()


# Global queues
telegram_queue = MessageQueue()
mcp_queue = MessageQueue()
task_queue = MessageQueue()
response_queue = MessageQueue()


# =============================================================================
# Agent Manager
# =============================================================================

class AgentManager:
    """Manages isolated agent containers and Hermes runtime instances"""
    
    def __init__(self):
        self.agents: Dict[str, AgentInstance] = {}
        self._lock = threading.Lock()
        self._next_port = 8000
    
    def spawn_agent(self, config: AgentConfig) -> AgentInstance:
        """Spawn a new agent instance with Hermes runtime"""
        with self._lock:
            if config.id in self.agents:
                logger.warning(f"Agent {config.id} already exists, restarting")
                self.stop_agent(config.id)
            
            instance = AgentInstance(config=config)
            self.agents[config.id] = instance
        
        # Start agent in background thread
        threading.Thread(
            target=self._start_agent_process,
            args=(config.id,),
            daemon=True
        ).start()
        
        return instance
    
    def _start_agent_process(self, agent_id: str) -> None:
        """Start Hermes runtime for an agent"""
        instance = self.agents[agent_id]
        instance.status = AgentStatus.STARTING
        instance.start_time = time.time()
        
        try:
            # Build environment
            env = os.environ.copy()
            env.update(instance.config.env)
            env["PYTHONPATH"] = f"/opt/hermes:{env.get('PYTHONPATH', '')}"
            
            # Agent-specific paths
            if instance.config.soul_path:
                env["HERMES_SOUL"] = str(instance.config.soul_path)
            if instance.config.memory_path:
                env["HERMES_MEMORY"] = str(instance.config.memory_path)
            
            # Port assignment
            with self._lock:
                self._next_port += 1
                instance.port = self._next_port
            
            env["HERMES_PORT"] = str(instance.port)
            env["HERMES_AGENT_ID"] = agent_id
            env["HERMES_AGENT_NAME"] = instance.config.name
            
            # Build command
            cmd = [
                sys.executable, "-m", "hermes_agent.runtime.run_agent",
                "--agent-id", agent_id,
                "--port", str(instance.port)
            ]
            
            if instance.config.soul_path:
                cmd.extend(["--soul", str(instance.config.soul_path)])
            if instance.config.memory_path:
                cmd.extend(["--memory", str(instance.config.memory_path)])
            
            logger.info(f"Starting agent {agent_id}: {' '.join(cmd)}")
            
            # Start process
            instance.process = subprocess.Popen(
                cmd,
                cwd=Config.HERMES_ROOT,
                env=env,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
                bufsize=1
            )
            
            # Wait briefly for startup
            time.sleep(2)
            
            if instance.is_alive():
                instance.status = AgentStatus.RUNNING
                logger.info(f"Agent {agent_id} started successfully on port {instance.port}")
            else:
                instance.status = AgentStatus.FAILED
                stdout, stderr = instance.process.communicate(timeout=5)
                instance.errors.append(f"Failed to start: {stderr}")
                logger.error(f"Agent {agent_id} failed to start: {stderr}")
                
        except Exception as e:
            instance.status = AgentStatus.FAILED
            instance.errors.append(str(e))
            logger.error(f"Error starting agent {agent_id}: {e}", exc_info=True)
    
    def stop_agent(self, agent_id: str) -> bool:
        """Stop an agent instance"""
        with self._lock:
            instance = self.agents.get(agent_id)
            if instance is None:
                return False
        
        instance.status = AgentStatus.STOPPING
        
        try:
            if instance.process and instance.is_alive():
                # Try graceful shutdown first
                instance.process.terminate()
                try:
                    instance.process.wait(timeout=10)
                except subprocess.TimeoutExpired:
                    instance.process.kill()
                    instance.process.wait()
            
            instance.status = AgentStatus.COMPLETED
            logger.info(f"Agent {agent_id} stopped")
            return True
            
        except Exception as e:
            instance.status = AgentStatus.FAILED
            instance.errors.append(f"Stop error: {str(e)}")
            logger.error(f"Error stopping agent {agent_id}: {e}")
            return False
    
    def stop_all(self) -> None:
        """Stop all agent instances"""
        logger.info("Stopping all agents...")
        with self._lock:
            agent_ids = list(self.agents.keys())
        
        for agent_id in agent_ids:
            self.stop_agent(agent_id)
    
    def get_agent(self, agent_id: str) -> Optional[AgentInstance]:
        return self.agents.get(agent_id)
    
    def list_agents(self) -> List[AgentInstance]:
        with self._lock:
            return list(self.agents.values())
    
    def health_check(self) -> Dict[str, bool]:
        """Check health of all agents"""
        results = {}
        for agent_id, instance in self.agents.items():
            if instance.status == AgentStatus.RUNNING:
                # Check if process is still alive
                is_healthy = instance.is_alive()
                if not is_healthy:
                    instance.status = AgentStatus.FAILED
                    logger.warning(f"Agent {agent_id} health check failed")
                results[agent_id] = is_healthy
            else:
                results[agent_id] = False
        return results
    
    def inject_soul(self, agent_id: str, soul_path: Path) -> bool:
        """Inject soul file into running agent"""
        instance = self.agents.get(agent_id)
        if instance is None or not instance.is_alive():
            return False
        
        # TODO: Implement soul injection via agent API
        instance.config.soul_path = soul_path
        logger.info(f"Soul injected for agent {agent_id}: {soul_path}")
        return True
    
    def inject_memory(self, agent_id: str, memory_path: Path) -> bool:
        """Inject memory into running agent"""
        instance = self.agents.get(agent_id)
        if instance is None or not instance.is_alive():
            return False
        
        # TODO: Implement memory injection via agent API
        instance.config.memory_path = memory_path
        logger.info(f"Memory injected for agent {agent_id}: {memory_path}")
        return True


# =============================================================================
# Telegram Router
# =============================================================================

class TelegramRouter:
    """Routes Telegram messages to appropriate agents"""
    
    def __init__(self, agent_manager: AgentManager):
        self.agent_manager = agent_manager
        self._running = False
        self._thread: Optional[threading.Thread] = None
    
    def start(self) -> None:
        """Start the Telegram routing thread"""
        if self._running:
            return
        
        self._running = True
        self._thread = threading.Thread(
            target=self._process_queue,
            daemon=True
        )
        self._thread.start()
        logger.info("Telegram router started")
    
    def stop(self) -> None:
        """Stop the Telegram router"""
        self._running = False
        if self._thread:
            self._thread.join(timeout=5)
        logger.info("Telegram router stopped")
    
    def _process_queue(self) -> None:
        """Process incoming Telegram messages"""
        while self._running:
            try:
                msg = telegram_queue.get(timeout=1)
                if msg is None:
                    continue
                
                self._route_message(msg)
                
            except Exception as e:
                logger.error(f"Error processing Telegram message: {e}")
    
    def _route_message(self, msg: TelegramMessage) -> None:
        """Route a Telegram message to the appropriate agent"""
        # Parse command to determine target agent
        text = msg.text.strip()
        
        # Check for direct agent addressing
        if text.startswith("/"):
            parts = text.split()
            if len(parts) >= 2:
                agent_id = parts[1]
                command = parts[2] if len(parts) > 2 else ""
                
                # Forward to specific agent
                self._forward_to_agent(agent_id, msg, command)
                return
        
        # Default: round-robin or first available agent
        for instance in self.agent_manager.list_agents():
            if instance.status == AgentStatus.RUNNING:
                self._forward_to_agent(instance.config.id, msg, text)
                return
        
        logger.warning(f"No available agents for message: {msg.text}")
    
    def _forward_to_agent(self, agent_id: str, msg: TelegramMessage, text: str) -> None:
        """Forward message to a specific agent"""
        instance = self.agent_manager.get_agent(agent_id)
        if instance is None or instance.status != AgentStatus.RUNNING:
            logger.warning(f"Agent {agent_id} not available")
            return
        
        # TODO: Implement actual message forwarding via agent API
        logger.info(f"Forwarding to agent {agent_id}: {text[:100]}...")
        
        # Simulate async processing
        threading.Thread(
            target=self._send_to_agent_api,
            args=(instance, msg, text),
            daemon=True
        ).start()
    
    def _send_to_agent_api(self, instance: AgentInstance, msg: TelegramMessage, text: str) -> None:
        """Send message to agent via HTTP API"""
        # TODO: Implement actual HTTP call to Hermes agent endpoint
        # This is a placeholder for the real implementation
        import requests
        try:
            if instance.port:
                url = f"http://localhost:{instance.port}/api/message"
                payload = {
                    "chat_id": msg.chat_id,
                    "text": text,
                    "message_id": msg.message_id
                }
                # response = requests.post(url, json=payload, timeout=30)
                logger.debug(f"Would send to {url}: {payload}")
        except Exception as e:
            logger.error(f"Error sending to agent {instance.config.id}: {e}")


# =============================================================================
# MCP Router
# =============================================================================

class MCPRouter:
    """Routes MCP tool requests to appropriate endpoints"""
    
    def __init__(self, agent_manager: AgentManager):
        self.agent_manager = agent_manager
        self._running = False
        self._thread: Optional[threading.Thread] = None
        self._mcp_servers: Dict[str, Any] = {}
    
    def start(self) -> None:
        """Start the MCP routing thread"""
        if self._running:
            return
        
        self._running = True
        self._thread = threading.Thread(
            target=self._process_queue,
            daemon=True
        )
        self._thread.start()
        logger.info("MCP router started")
    
    def stop(self) -> None:
        """Stop the MCP router"""
        self._running = False
        if self._thread:
            self._thread.join(timeout=5)
        logger.info("MCP router stopped")
    
    def register_server(self, server_id: str, config: Dict[str, Any]) -> bool:
        """Register an MCP server"""
        self._mcp_servers[server_id] = config
        logger.info(f"MCP server registered: {server_id}")
        return True
    
    def _process_queue(self) -> None:
        """Process incoming MCP tasks"""
        while self._running:
            try:
                task = mcp_queue.get(timeout=1)
                if task is None:
                    continue
                
                self._route_task(task)
                
            except Exception as e:
                logger.error(f"Error processing MCP task: {e}")
    
    def _route_task(self, task: MCPTask) -> None:
        """Route an MCP task to the appropriate server or agent"""
        # Check if this is an agent-specific tool
        instance = self.agent_manager.get_agent(task.agent_id)
        if instance is None or instance.status != AgentStatus.RUNNING:
            logger.warning(f"Agent {task.agent_id} not available for MCP task")
            return
        
        # TODO: Forward to agent's MCP endpoint
        logger.info(f"Routing MCP task {task.task_id} to agent {task.agent_id}")
        
        threading.Thread(
            target=self._execute_mcp_task,
            args=(task,),
            daemon=True
        ).start()
    
    def _execute_mcp_task(self, task: MCPTask) -> None:
        """Execute an MCP task"""
        # TODO: Implement actual MCP tool execution
        logger.debug(f"Executing MCP task {task.task_id}: {task.tool_name}")


# =============================================================================
# Export/Import Manager
# =============================================================================

class ExportImportManager:
    """Handles agent state export/import and backup/recovery"""
    
    def __init__(self, agent_manager: AgentManager):
        self.agent_manager = agent_manager
        self.export_dir = Config.VOLUMES_DIR / "exports"
        self.backup_dir = Config.VOLUMES_DIR / "backups"
        
        # Ensure directories exist
        self.export_dir.mkdir(parents=True, exist_ok=True)
        self.backup_dir.mkdir(parents=True, exist_ok=True)
    
    def export_agent(self, agent_id: str, export_path: Optional[Path] = None) -> bool:
        """Export agent state (memory, soul, trajectory)"""
        instance = self.agent_manager.get_agent(agent_id)
        if instance is None:
            return False
        
        try:
            export_path = export_path or (self.export_dir / f"{agent_id}_{int(time.time())}.tar.gz")
            
            # TODO: Implement actual export
            logger.info(f"Exporting agent {agent_id} to {export_path}")
            
            # Placeholder: create a manifest
            manifest = {
                "agent_id": agent_id,
                "agent_name": instance.config.name,
                "export_time": time.time(),
                "status": instance.status.value
            }
            
            with open(export_path.with_suffix(".json"), "w") as f:
                json.dump(manifest, f, indent=2)
            
            return True
            
        except Exception as e:
            logger.error(f"Error exporting agent {agent_id}: {e}")
            return False
    
    def import_agent(self, export_path: Path) -> bool:
        """Import agent state from export"""
        try:
            # TODO: Implement actual import
            logger.info(f"Importing from {export_path}")
            return True
        except Exception as e:
            logger.error(f"Error importing from {export_path}: {e}")
            return False
    
    def backup_all(self) -> bool:
        """Backup all agents"""
        logger.info("Backing up all agents...")
        success = True
        for instance in self.agent_manager.list_agents():
            if not self.export_agent(instance.config.id):
                success = False
        return success
    
    def recover_agent(self, agent_id: str, backup_path: Path) -> bool:
        """Recover agent from backup"""
        return self.import_agent(backup_path)


# =============================================================================
# Telemetry Collector
# =============================================================================

class TelemetryCollector:
    """Collects and reports runtime telemetry"""
    
    def __init__(self, agent_manager: AgentManager):
        self.agent_manager = agent_manager
        self._running = False
        self._thread: Optional[threading.Thread] = None
        self.metrics: Dict[str, Any] = {}
    
    def start(self) -> None:
        """Start telemetry collection"""
        if self._running:
            return
        
        self._running = True
        self._thread = threading.Thread(
            target=self._collect,
            daemon=True
        )
        self._thread.start()
        logger.info("Telemetry collector started")
    
    def stop(self) -> None:
        """Stop telemetry collection"""
        self._running = False
        if self._thread:
            self._thread.join(timeout=5)
        logger.info("Telemetry collector stopped")
    
    def _collect(self) -> None:
        """Collect metrics periodically"""
        while self._running:
            try:
                self._collect_metrics()
                time.sleep(Config.HEALTH_CHECK_INTERVAL)
            except Exception as e:
                logger.error(f"Error collecting metrics: {e}")
    
    def _collect_metrics(self) -> None:
        """Collect current metrics"""
        agents = self.agent_manager.list_agents()
        
        self.metrics = {
            "timestamp": time.time(),
            "agents": {
                "total": len(agents),
                "running": sum(1 for a in agents if a.status == AgentStatus.RUNNING),
                "failed": sum(1 for a in agents if a.status == AgentStatus.FAILED),
                "pending": sum(1 for a in agents if a.status == AgentStatus.PENDING),
            },
            "queues": {
                "telegram": telegram_queue.size(),
                "mcp": mcp_queue.size(),
                "tasks": task_queue.size(),
            },
            "agents_detail": {}
        }
        
        for instance in agents:
            self.metrics["agents_detail"][instance.config.id] = {
                "status": instance.status.value,
                "uptime": instance.runtime_elapsed(),
                "errors": len(instance.errors),
                "port": instance.port
            }
        
        # Log summary
        logger.debug(f"Telemetry: {json.dumps(self.metrics, default=str)}")
    
    def get_metrics(self) -> Dict[str, Any]:
        return self.metrics


# =============================================================================
# Crew Synchronizer
# =============================================================================

class CrewSynchronizer:
    """Manages crew-level coordination between agents"""
    
    def __init__(self, agent_manager: AgentManager):
        self.agent_manager = agent_manager
        self.crews: Dict[str, List[str]] = {}
    
    def create_crew(self, crew_id: str, agent_ids: List[str]) -> bool:
        """Create a new crew of agents"""
        self.crews[crew_id] = agent_ids
        logger.info(f"Crew created: {crew_id} with {len(agent_ids)} agents")
        return True
    
    def disband_crew(self, crew_id: str) -> bool:
        """Disband a crew"""
        if crew_id in self.crews:
            del self.crews[crew_id]
            logger.info(f"Crew disbanded: {crew_id}")
            return True
        return False
    
    def sync_crew(self, crew_id: str) -> bool:
        """Synchronize crew state"""
        if crew_id not in self.crews:
            return False
        
        # TODO: Implement crew synchronization logic
        agent_ids = self.crews[crew_id]
        logger.info(f"Syncing crew {crew_id}: {agent_ids}")
        
        # Verify all agents are running
        all_healthy = True
        for agent_id in agent_ids:
            instance = self.agent_manager.get_agent(agent_id)
            if instance is None or instance.status != AgentStatus.RUNNING:
                all_healthy = False
                break
        
        return all_healthy


# =============================================================================
# Main Supervisor
# =============================================================================

class OpenClawSupervisor:
    """Main supervisor controller"""
    
    def __init__(self):
        logger.info("Initializing OpenClaw Supervisor...")
        
        # Initialize components
        self.agent_manager = AgentManager()
        self.telegram_router = TelegramRouter(self.agent_manager)
        self.mcp_router = MCPRouter(self.agent_manager)
        self.export_manager = ExportImportManager(self.agent_manager)
        self.telemetry = TelemetryCollector(self.agent_manager)
        self.crew_sync = CrewSynchronizer(self.agent_manager)
        
        # State
        self._running = False
        self._shutdown_event = threading.Event()
        
        logger.info("OpenClaw Supervisor initialized")
    
    def start(self) -> None:
        """Start all supervisor components"""
        logger.info("Starting OpenClaw Supervisor...")
        
        # Verify Hermes installation
        self._verify_hermes()
        
        # Start all components
        self.telegram_router.start()
        self.mcp_router.start()
        self.telemetry.start()
        
        self._running = True
        logger.info("OpenClaw Supervisor started")
        
        # Start health monitor
        threading.Thread(target=self._health_monitor, daemon=True).start()
    
    def _verify_hermes(self) -> None:
        """Verify Hermes is properly installed"""
        hermes_path = Config.HERMES_ROOT
        if not hermes_path.exists():
            logger.error(f"Hermes root not found: {hermes_path}")
            raise RuntimeError(f"Hermes not found at {hermes_path}")
        
        cli_path = hermes_path / "hermes_cli"
        if not cli_path.exists():
            logger.warning(f"Hermes CLI path not found: {cli_path}")
        
        # Test import
        try:
            sys.path.insert(0, str(hermes_path))
            import hermes_agent
            logger.info(f"Hermes module imported successfully from {hermes_path}")
        except ImportError as e:
            logger.error(f"Failed to import Hermes: {e}")
            raise
    
    def _health_monitor(self) -> None:
        """Monitor health of all components"""
        while self._running:
            try:
                # Check agents
                health = self.agent_manager.health_check()
                unhealthy = [aid for aid, h in health.items() if not h]
                if unhealthy:
                    logger.warning(f"Unhealthy agents: {unhealthy}")
                
                # Collect telemetry
                self.telemetry._collect_metrics()
                
                time.sleep(Config.HEALTH_CHECK_INTERVAL)
                
            except Exception as e:
                logger.error(f"Health monitor error: {e}")
                time.sleep(5)
    
    def stop(self) -> None:
        """Stop all supervisor components gracefully"""
        logger.info("Stopping OpenClaw Supervisor...")
        self._running = False
        
        # Stop components
        self.telegram_router.stop()
        self.mcp_router.stop()
        self.telemetry.stop()
        
        # Stop all agents
        self.agent_manager.stop_all()
        
        logger.info("OpenClaw Supervisor stopped")
    
    def handle_telegram_message(self, msg: TelegramMessage) -> None:
        """Handle incoming Telegram message"""
        telegram_queue.put(msg)
    
    def handle_mcp_task(self, task: MCPTask) -> None:
        """Handle incoming MCP task"""
        mcp_queue.put(task)
    
    def spawn_agent(self, config: AgentConfig) -> AgentInstance:
        """Spawn a new agent"""
        return self.agent_manager.spawn_agent(config)
    
    def get_status(self) -> Dict[str, Any]:
        """Get overall system status"""
        return {
            "running": self._running,
            "agents": {aid: inst.status.value for aid, inst in self.agent_manager.agents.items()},
            "queues": {
                "telegram": telegram_queue.size(),
                "mcp": mcp_queue.size(),
                "tasks": task_queue.size()
            },
            "telemetry": self.telemetry.get_metrics()
        }


# =============================================================================
# Signal Handling
# =============================================================================

def signal_handler(signum, frame):
    """Handle shutdown signals"""
    logger.info(f"Received signal {signum}, shutting down...")
    supervisor._shutdown_event.set()
    supervisor.stop()
    sys.exit(0)


# =============================================================================
# Main Entry Point
# =============================================================================

if __name__ == "__main__":
    # Initialize supervisor
    supervisor = OpenClawSupervisor()
    
    # Register signal handlers
    signal.signal(signal.SIGINT, signal_handler)
    signal.signal(signal.SIGTERM, signal_handler)
    
    # Start supervisor
    supervisor.start()
    
    # Keep running until shutdown
    try:
        while supervisor._running:
            time.sleep(1)
    except KeyboardInterrupt:
        supervisor.stop()
