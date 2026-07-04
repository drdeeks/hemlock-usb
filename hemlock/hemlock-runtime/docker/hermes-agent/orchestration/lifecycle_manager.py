#!/usr/bin/env python3
"""
Hermes Agent Lifecycle Manager

Manages the complete lifecycle of agents: spawn, monitor, pause, resume, terminate.
Tracks agent state and ensures proper cleanup on shutdown.

States:
  - pending: Agent requested but not yet started
  - starting: Agent initialization in progress
  - running: Agent actively processing tasks
  - idle: Agent running but no active tasks
  - paused: Agent temporarily suspended
  - stopping: Graceful shutdown in progress
  - stopped: Agent fully terminated
  - failed: Agent encountered unrecoverable error
"""

import asyncio
import json
import logging
import os
import signal
import time
import uuid
from datetime import datetime
from enum import Enum
from pathlib import Path
from typing import Any, Dict, List, Optional, Callable
from dataclasses import dataclass, field, asdict

logger = logging.getLogger(__name__)


class AgentState(Enum):
    """Agent lifecycle states."""
    PENDING = "pending"
    STARTING = "starting"
    RUNNING = "running"
    IDLE = "idle"
    PAUSED = "paused"
    STOPPING = "stopping"
    STOPPED = "stopped"
    FAILED = "failed"


@dataclass
class AgentMetadata:
    """Metadata for a managed agent."""
    agent_id: str
    name: str
    state: AgentState = AgentState.PENDING
    created_at: str = field(default_factory=lambda: datetime.utcnow().isoformat())
    started_at: Optional[str] = None
    stopped_at: Optional[str] = None
    last_activity: Optional[str] = None
    pid: Optional[int] = None
    session_id: Optional[str] = None
    workspace: Optional[str] = None
    model: Optional[str] = None
    platform: Optional[str] = None
    error_message: Optional[str] = None
    restart_count: int = 0
    max_restarts: int = 3
    metadata: Dict[str, Any] = field(default_factory=dict)
    
    def to_dict(self) -> Dict[str, Any]:
        """Convert to dictionary for JSON serialization."""
        return {
            **asdict(self),
            'state': self.state.value if isinstance(self.state, AgentState) else self.state,
        }
    
    @classmethod
    def from_dict(cls, data: Dict[str, Any]) -> 'AgentMetadata':
        """Create from dictionary."""
        if 'state' in data and isinstance(data['state'], str):
            data['state'] = AgentState(data['state'])
        return cls(**data)


class LifecycleManager:
    """
    Manages agent lifecycle with state tracking and automatic recovery.
    
    Features:
    - Agent spawn with configurable parameters
    - State tracking and persistence
    - Automatic restart on failure (with limits)
    - Graceful shutdown with timeout
    - Activity monitoring and idle detection
    - Event callbacks for state changes
    """
    
    def __init__(self, hermes_home: Optional[Path] = None):
        self.hermes_home = hermes_home or self._get_hermes_home()
        self.agents: Dict[str, AgentMetadata] = {}
        self._processes: Dict[str, asyncio.subprocess.Process] = {}
        self._state_callbacks: List[Callable] = []
        self._monitor_task: Optional[asyncio.Task] = None
        self._running = False
        self._lock = asyncio.Lock()
        
        # Configuration
        self.idle_timeout = int(os.environ.get('AGENT_IDLE_TIMEOUT', '3600'))  # 1 hour
        self.health_check_interval = int(os.environ.get('AGENT_HEALTH_INTERVAL', '30'))  # 30 seconds
        self.shutdown_timeout = int(os.environ.get('AGENT_SHUTDOWN_TIMEOUT', '30'))  # 30 seconds
        
        # Persistence
        self.state_file = self.hermes_home / 'orchestration' / 'agent_state.json'
        
    def _get_hermes_home(self) -> Path:
        """Get HERMES_HOME directory."""
        return Path(os.environ.get('HERMES_HOME', Path.home() / '.hermes'))
    
    def _ensure_directories(self) -> None:
        """Ensure required directories exist."""
        self.hermes_home.mkdir(parents=True, exist_ok=True)
        (self.hermes_home / 'orchestration').mkdir(parents=True, exist_ok=True)
        (self.hermes_home / 'agents').mkdir(parents=True, exist_ok=True)
    
    # -------------------------------------------------------------------------
    # State Management
    # -------------------------------------------------------------------------
    
    async def _save_state(self) -> None:
        """Persist agent state to disk."""
        self._ensure_directories()
        try:
            state = {
                'timestamp': datetime.utcnow().isoformat(),
                'agents': {aid: agent.to_dict() for aid, agent in self.agents.items()},
            }
            temp_file = self.state_file.with_suffix('.tmp')
            temp_file.write_text(json.dumps(state, indent=2))
            temp_file.rename(self.state_file)
            logger.debug(f"Saved agent state for {len(self.agents)} agents")
        except Exception as e:
            logger.error(f"Failed to save agent state: {e}")
    
    async def _load_state(self) -> None:
        """Load agent state from disk."""
        if not self.state_file.exists():
            logger.debug("No existing agent state found")
            return
        
        try:
            content = self.state_file.read_text()
            state = json.loads(content)
            for agent_id, agent_data in state.get('agents', {}).items():
                self.agents[agent_id] = AgentMetadata.from_dict(agent_data)
            logger.info(f"Loaded agent state for {len(self.agents)} agents")
        except Exception as e:
            logger.error(f"Failed to load agent state: {e}")
    
    def register_state_callback(self, callback: Callable) -> None:
        """Register callback for state changes."""
        self._state_callbacks.append(callback)
    
    async def _notify_state_change(self, agent_id: str, old_state: AgentState, new_state: AgentState) -> None:
        """Notify callbacks of state change."""
        for callback in self._state_callbacks:
            try:
                if asyncio.iscoroutinefunction(callback):
                    await callback(agent_id, old_state, new_state)
                else:
                    callback(agent_id, old_state, new_state)
            except Exception as e:
                logger.error(f"State callback failed: {e}")
    
    # -------------------------------------------------------------------------
    # Agent Lifecycle
    # -------------------------------------------------------------------------
    
    async def spawn_agent(
        self,
        name: str,
        model: Optional[str] = None,
        platform: Optional[str] = None,
        workspace: Optional[str] = None,
        session_id: Optional[str] = None,
        **kwargs
    ) -> str:
        """
        Spawn a new agent.
        
        Args:
            name: Human-readable agent name
            model: Model to use (e.g., "claude-sonnet-4-20250514")
            platform: Platform type (cli, telegram, discord, etc.)
            workspace: Workspace directory path
            session_id: Existing session ID to resume
            **kwargs: Additional agent configuration
            
        Returns:
            Agent ID for the spawned agent
        """
        agent_id = f"agent_{uuid.uuid4().hex[:8]}"
        
        metadata = AgentMetadata(
            agent_id=agent_id,
            name=name,
            state=AgentState.PENDING,
            model=model,
            platform=platform,
            workspace=workspace,
            session_id=session_id,
            metadata=kwargs,
        )
        
        async with self._lock:
            self.agents[agent_id] = metadata
            await self._save_state()
        
        logger.info(f"Spawning agent {agent_id} ({name})")
        await self._transition_state(agent_id, AgentState.STARTING)
        
        # Start agent in background
        asyncio.create_task(self._run_agent(agent_id))
        
        return agent_id
    
    async def _run_agent(self, agent_id: str) -> None:
        """Run agent lifecycle."""
        metadata = self.agents.get(agent_id)
        if not metadata:
            logger.error(f"Agent {agent_id} not found")
            return
        
        try:
            # TODO: Implement actual agent process spawning
            # For now, simulate agent startup
            await asyncio.sleep(0.1)  # Simulate startup delay
            
            metadata.started_at = datetime.utcnow().isoformat()
            metadata.last_activity = metadata.started_at
            metadata.pid = os.getpid()  # Placeholder - real PID when spawned
            
            await self._transition_state(agent_id, AgentState.RUNNING)
            logger.info(f"Agent {agent_id} started successfully")
            
            # Monitor agent until stopped
            while metadata.state in (AgentState.RUNNING, AgentState.IDLE):
                await asyncio.sleep(self.health_check_interval)
                await self._check_agent_health(agent_id)
                
        except asyncio.CancelledError:
            logger.info(f"Agent {agent_id} task cancelled")
            await self._transition_state(agent_id, AgentState.STOPPING)
        except Exception as e:
            logger.error(f"Agent {agent_id} failed: {e}")
            metadata.error_message = str(e)
            await self._handle_agent_failure(agent_id)
    
    async def _check_agent_health(self, agent_id: str) -> None:
        """Check agent health and update state."""
        metadata = self.agents.get(agent_id)
        if not metadata:
            return
        
        # Check if agent is still alive (placeholder)
        if metadata.pid:
            try:
                os.kill(metadata.pid, 0)  # Check if process exists
            except OSError:
                logger.warning(f"Agent {agent_id} (PID {metadata.pid}) no longer exists")
                await self._handle_agent_failure(agent_id)
                return
        
        # Check for idle timeout
        if metadata.last_activity:
            last_activity = datetime.fromisoformat(metadata.last_activity)
            idle_time = (datetime.utcnow() - last_activity).total_seconds()
            if idle_time > self.idle_timeout:
                logger.info(f"Agent {agent_id} idle for {idle_time}s, marking as idle")
                await self._transition_state(agent_id, AgentState.IDLE)
    
    async def _handle_agent_failure(self, agent_id: str) -> None:
        """Handle agent failure with automatic restart."""
        metadata = self.agents.get(agent_id)
        if not metadata:
            return
        
        if metadata.restart_count < metadata.max_restarts:
            metadata.restart_count += 1
            logger.info(f"Restarting agent {agent_id} (attempt {metadata.restart_count}/{metadata.max_restarts})")
            await self._transition_state(agent_id, AgentState.PENDING)
            asyncio.create_task(self._run_agent(agent_id))
        else:
            logger.error(f"Agent {agent_id} exceeded max restarts, marking as failed")
            await self._transition_state(agent_id, AgentState.FAILED)
            metadata.stopped_at = datetime.utcnow().isoformat()
            await self._save_state()
    
    async def stop_agent(self, agent_id: str, force: bool = False) -> bool:
        """
        Stop an agent.
        
        Args:
            agent_id: Agent ID to stop
            force: If True, kill immediately; otherwise graceful shutdown
            
        Returns:
            True if agent was stopped successfully
        """
        metadata = self.agents.get(agent_id)
        if not metadata:
            logger.warning(f"Agent {agent_id} not found")
            return False
        
        if metadata.state in (AgentState.STOPPED, AgentState.STOPPING):
            logger.debug(f"Agent {agent_id} already stopping/stopped")
            return True
        
        logger.info(f"Stopping agent {agent_id} (force={force})")
        await self._transition_state(agent_id, AgentState.STOPPING)
        
        try:
            # TODO: Implement actual process termination
            # For now, simulate shutdown
            if not force:
                await asyncio.sleep(0.1)  # Simulate graceful shutdown
            
            metadata.stopped_at = datetime.utcnow().isoformat()
            await self._transition_state(agent_id, AgentState.STOPPED)
            logger.info(f"Agent {agent_id} stopped successfully")
            await self._save_state()
            return True
            
        except Exception as e:
            logger.error(f"Failed to stop agent {agent_id}: {e}")
            if force:
                metadata.state = AgentState.STOPPED
                metadata.stopped_at = datetime.utcnow().isoformat()
                await self._save_state()
                return True
            return False
    
    async def pause_agent(self, agent_id: str) -> bool:
        """Pause a running agent."""
        metadata = self.agents.get(agent_id)
        if not metadata or metadata.state != AgentState.RUNNING:
            return False
        
        logger.info(f"Pausing agent {agent_id}")
        await self._transition_state(agent_id, AgentState.PAUSED)
        return True
    
    async def resume_agent(self, agent_id: str) -> bool:
        """Resume a paused agent."""
        metadata = self.agents.get(agent_id)
        if not metadata or metadata.state != AgentState.PAUSED:
            return False
        
        logger.info(f"Resuming agent {agent_id}")
        await self._transition_state(agent_id, AgentState.RUNNING)
        metadata.last_activity = datetime.utcnow().isoformat()
        return True
    
    async def _transition_state(self, agent_id: str, new_state: AgentState) -> None:
        """Transition agent to new state."""
        metadata = self.agents.get(agent_id)
        if not metadata:
            return
        
        old_state = metadata.state
        if old_state == new_state:
            return
        
        metadata.state = new_state
        logger.debug(f"Agent {agent_id}: {old_state.value} -> {new_state.value}")
        await self._notify_state_change(agent_id, old_state, new_state)
        await self._save_state()
    
    # -------------------------------------------------------------------------
    # Monitoring
    # -------------------------------------------------------------------------
    
    async def start_monitoring(self) -> None:
        """Start background monitoring task."""
        if self._monitor_task:
            return
        
        self._running = True
        self._monitor_task = asyncio.create_task(self._monitor_loop())
        logger.info("Lifecycle monitoring started")
    
    async def stop_monitoring(self) -> None:
        """Stop background monitoring task."""
        self._running = False
        if self._monitor_task:
            self._monitor_task.cancel()
            try:
                await self._monitor_task
            except asyncio.CancelledError:
                pass
            self._monitor_task = None
        logger.info("Lifecycle monitoring stopped")
    
    async def _monitor_loop(self) -> None:
        """Background monitoring loop."""
        while self._running:
            try:
                await asyncio.sleep(self.health_check_interval)
                await self._save_state()  # Periodic state persistence
            except asyncio.CancelledError:
                break
            except Exception as e:
                logger.error(f"Monitor loop error: {e}")
    
    # -------------------------------------------------------------------------
    # Queries
    # -------------------------------------------------------------------------
    
    def get_agent(self, agent_id: str) -> Optional[AgentMetadata]:
        """Get agent metadata."""
        return self.agents.get(agent_id)
    
    def list_agents(self, state: Optional[AgentState] = None) -> List[AgentMetadata]:
        """List agents, optionally filtered by state."""
        if state:
            return [a for a in self.agents.values() if a.state == state]
        return list(self.agents.values())
    
    def get_running_agents(self) -> List[AgentMetadata]:
        """Get all running agents."""
        return self.list_agents(AgentState.RUNNING)
    
    def get_failed_agents(self) -> List[AgentMetadata]:
        """Get all failed agents."""
        return self.list_agents(AgentState.FAILED)
    
    def get_stats(self) -> Dict[str, Any]:
        """Get lifecycle manager statistics."""
        states = {}
        for agent in self.agents.values():
            state_name = agent.state.value if isinstance(agent.state, AgentState) else agent.state
            states[state_name] = states.get(state_name, 0) + 1
        
        return {
            'total_agents': len(self.agents),
            'states': states,
            'running': len(self.get_running_agents()),
            'failed': len(self.get_failed_agents()),
            'monitoring_active': self._running,
        }
    
    # -------------------------------------------------------------------------
    # Cleanup
    # -------------------------------------------------------------------------
    
    async def shutdown(self, timeout: Optional[int] = None) -> None:
        """
        Shutdown all agents and the lifecycle manager.
        
        Args:
            timeout: Maximum seconds to wait for graceful shutdown
        """
        timeout = timeout or self.shutdown_timeout
        logger.info(f"Shutting down lifecycle manager (timeout={timeout}s)")
        
        await self.stop_monitoring()
        
        # Stop all agents
        stop_tasks = []
        for agent_id in list(self.agents.keys()):
            metadata = self.agents.get(agent_id)
            if metadata and metadata.state not in (AgentState.STOPPED, AgentState.STOPPING):
                stop_tasks.append(self.stop_agent(agent_id))
        
        if stop_tasks:
            try:
                await asyncio.wait_for(
                    asyncio.gather(*stop_tasks, return_exceptions=True),
                    timeout=timeout
                )
            except asyncio.TimeoutError:
                logger.warning(f"Timeout stopping agents, forcing shutdown")
                # Force stop remaining agents
                for agent_id in list(self.agents.keys()):
                    metadata = self.agents.get(agent_id)
                    if metadata and metadata.state not in (AgentState.STOPPED,):
                        metadata.state = AgentState.STOPPED
                        metadata.stopped_at = datetime.utcnow().isoformat()
        
        await self._save_state()
        logger.info("Lifecycle manager shutdown complete")


# Global lifecycle manager instance
_lifecycle_manager: Optional[LifecycleManager] = None


def get_lifecycle_manager() -> LifecycleManager:
    """Get or create the global lifecycle manager."""
    global _lifecycle_manager
    if _lifecycle_manager is None:
        _lifecycle_manager = LifecycleManager()
    return _lifecycle_manager


async def initialize_lifecycle() -> LifecycleManager:
    """Initialize the lifecycle manager."""
    manager = get_lifecycle_manager()
    await manager._load_state()
    await manager.start_monitoring()
    return manager
