"""
Hermes Orchestration Layer

Coordinates agent lifecycle, task scheduling, and failure recovery.

Components:
- LifecycleManager: Agent spawn, monitor, pause, resume, terminate
- TaskScheduler: Cron-style and event-driven task scheduling
- RecoveryEngine: Failure detection and automatic recovery

Usage:
    from orchestration import initialize_orchestration
    
    # Initialize all components
    lifecycle, scheduler, recovery = await initialize_orchestration()
    
    # Spawn an agent
    agent_id = await lifecycle.spawn_agent("my-agent", model="claude-sonnet-4")
    
    # Schedule a task
    scheduler.schedule_task(
        name="hourly-cleanup",
        handler="cleanup_handler",
        schedule="0 * * * *"  # Every hour
    )
    
    # Register recovery handler
    recovery.register_recovery_handler("restart_agent", my_restart_function)
"""

import logging
from pathlib import Path
from typing import Optional, Tuple

from .lifecycle_manager import LifecycleManager, get_lifecycle_manager, initialize_lifecycle
from .scheduler import TaskScheduler, get_scheduler, initialize_scheduler
from .recovery_engine import RecoveryEngine, get_recovery_engine, initialize_recovery

logger = logging.getLogger(__name__)

__all__ = [
    # Lifecycle
    'LifecycleManager',
    'get_lifecycle_manager',
    'initialize_lifecycle',
    
    # Scheduler
    'TaskScheduler',
    'get_scheduler',
    'initialize_scheduler',
    
    # Recovery
    'RecoveryEngine',
    'get_recovery_engine',
    'initialize_recovery',
    
    # Combined initialization
    'initialize_orchestration',
    'shutdown_orchestration',
    'get_orchestration_stats',
]

# Global instances
_lifecycle: Optional[LifecycleManager] = None
_scheduler: Optional[TaskScheduler] = None
_recovery: Optional[RecoveryEngine] = None


async def initialize_orchestration(hermes_home: Optional[Path] = None) -> Tuple[LifecycleManager, TaskScheduler, RecoveryEngine]:
    """
    Initialize all orchestration components.
    
    Args:
        hermes_home: HERMES_HOME directory (uses env var if not provided)
        
    Returns:
        Tuple of (lifecycle_manager, scheduler, recovery_engine)
    """
    global _lifecycle, _scheduler, _recovery
    
    logger.info("Initializing orchestration layer...")
    
    # Initialize lifecycle manager
    _lifecycle = LifecycleManager(hermes_home=hermes_home)
    await _lifecycle._load_state()
    await _lifecycle.start_monitoring()
    logger.info("  ✓ Lifecycle manager initialized")
    
    # Initialize scheduler
    _scheduler = TaskScheduler(hermes_home=hermes_home)
    await _scheduler.start()
    logger.info("  ✓ Task scheduler initialized")
    
    # Initialize recovery engine
    _recovery = RecoveryEngine(hermes_home=hermes_home)
    await _recovery._load_state()
    await _recovery.start_monitoring()
    logger.info("  ✓ Recovery engine initialized")
    
    # Wire up integration between components
    _wire_components()
    
    logger.info("Orchestration layer initialized successfully")
    return _lifecycle, _scheduler, _recovery


async def shutdown_orchestration(timeout: int = 30) -> None:
    """
    Gracefully shutdown all orchestration components.
    
    Args:
        timeout: Maximum seconds to wait for graceful shutdown
    """
    logger.info("Shutting down orchestration layer...")
    
    global _lifecycle, _scheduler, _recovery
    
    # Stop scheduler first (no new tasks)
    if _scheduler:
        await _scheduler.stop()
        logger.info("  ✓ Scheduler stopped")
    
    # Stop recovery monitoring
    if _recovery:
        await _recovery.stop_monitoring()
        logger.info("  ✓ Recovery engine stopped")
    
    # Stop lifecycle manager (stops all agents)
    if _lifecycle:
        await _lifecycle.shutdown(timeout=timeout)
        logger.info("  ✓ Lifecycle manager stopped")
    
    logger.info("Orchestration layer shutdown complete")


def _wire_components() -> None:
    """Wire up integration between orchestration components."""
    if not (_lifecycle and _scheduler and _recovery):
        return
    
    # Register lifecycle state changes as events for scheduler
    async def on_agent_state_change(agent_id: str, old_state, new_state):
        """Trigger events on agent state changes."""
        await _scheduler.trigger_event(f"agent_{new_state.value}", {
            'agent_id': agent_id,
            'old_state': old_state.value if hasattr(old_state, 'value') else old_state,
            'new_state': new_state.value if hasattr(new_state, 'value') else new_state,
        })
        
        # Detect failures
        if new_state.name == 'FAILED':
            agent = _lifecycle.get_agent(agent_id)
            await _recovery.detect_failure(
                failure_type=_recovery.FailureType.AGENT_CRASH,
                source=agent_id,
                message=f"Agent failed: {agent.error_message if agent else 'unknown'}",
                severity=_recovery.FailureSeverity.HIGH,
            )
    
    _lifecycle.register_state_callback(on_agent_state_change)
    
    # Register default recovery handlers
    async def restart_agent_handler(failure):
        """Restart a failed agent."""
        agent_id = failure.source
        if _lifecycle:
            await _lifecycle.stop_agent(agent_id)
            agent = _lifecycle.get_agent(agent_id)
            if agent:
                await _lifecycle.spawn_agent(
                    name=agent.name,
                    model=agent.model,
                    platform=agent.platform,
                    workspace=agent.workspace,
                )
    
    _recovery.register_recovery_handler("restart_agent", restart_agent_handler)
    
    logger.debug("Orchestration components wired successfully")


def get_orchestration_stats() -> dict:
    """Get combined statistics from all orchestration components."""
    stats = {
        'lifecycle': _lifecycle.get_stats() if _lifecycle else {},
        'scheduler': _scheduler.get_stats() if _scheduler else {},
        'recovery': _recovery.get_stats() if _recovery else {},
    }
    
    # Add summary
    total_agents = stats['lifecycle'].get('total_agents', 0)
    total_tasks = stats['scheduler'].get('total_tasks', 0)
    active_failures = stats['recovery'].get('active_failures', 0)
    
    stats['summary'] = {
        'total_agents': total_agents,
        'running_agents': stats['lifecycle'].get('running', 0),
        'total_tasks': total_tasks,
        'scheduled_tasks': stats['scheduler'].get('states', {}).get('scheduled', 0),
        'active_failures': active_failures,
        'system_healthy': active_failures == 0,
    }
    
    return stats


# Convenience accessors
def get_lifecycle() -> Optional[LifecycleManager]:
    """Get the lifecycle manager instance."""
    return _lifecycle


def get_task_scheduler() -> Optional[TaskScheduler]:
    """Get the scheduler instance."""
    return _scheduler


def get_recovery() -> Optional[RecoveryEngine]:
    """Get the recovery engine instance."""
    return _recovery
