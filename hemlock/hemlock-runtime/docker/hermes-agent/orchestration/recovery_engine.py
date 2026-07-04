#!/usr/bin/env python3
"""
Hermes Recovery Engine

Handles failure detection, recovery strategies, and system healing.
Monitors agents and tasks for failures and applies appropriate recovery actions.

Features:
- Failure detection and classification
- Automatic recovery strategies
- Escalation policies
- Health monitoring
- Recovery audit logging
"""

import asyncio
import json
import logging
import os
import time
from datetime import datetime, timedelta
from enum import Enum
from pathlib import Path
from typing import Any, Callable, Dict, List, Optional, Set
from dataclasses import dataclass, field, asdict
import uuid

logger = logging.getLogger(__name__)


class FailureSeverity(Enum):
    """Failure severity levels."""
    LOW = "low"           # Minor issue, self-healing
    MEDIUM = "medium"     # Requires intervention
    HIGH = "high"         # Critical, immediate action needed
    CRITICAL = "critical" # System-threatening


class FailureType(Enum):
    """Types of failures."""
    AGENT_CRASH = "agent_crash"
    AGENT_HUNG = "agent_hung"
    TASK_FAILED = "task_failed"
    TASK_TIMEOUT = "task_timeout"
    RESOURCE_EXHAUSTED = "resource_exhausted"
    CONNECTION_LOST = "connection_lost"
    DISK_FULL = "disk_full"
    MEMORY_PRESSURE = "memory_pressure"
    HEALTH_CHECK_FAILED = "health_check_failed"
    UNKNOWN = "unknown"


@dataclass
class FailureEvent:
    """Represents a detected failure."""
    failure_id: str
    failure_type: FailureType
    severity: FailureSeverity
    source: str  # Agent ID, task ID, or component name
    message: str
    detected_at: str = field(default_factory=lambda: datetime.utcnow().isoformat())
    resolved_at: Optional[str] = None
    recovery_attempts: int = 0
    recovery_actions: List[str] = field(default_factory=list)
    metadata: Dict[str, Any] = field(default_factory=dict)
    resolved: bool = False
    resolution: Optional[str] = None
    
    def to_dict(self) -> Dict[str, Any]:
        """Convert to dictionary for JSON serialization."""
        return {
            **asdict(self),
            'failure_type': self.failure_type.value if isinstance(self.failure_type, FailureType) else self.failure_type,
            'severity': self.severity.value if isinstance(self.severity, FailureSeverity) else self.severity,
        }
    
    @classmethod
    def from_dict(cls, data: Dict[str, Any]) -> 'FailureEvent':
        """Create from dictionary."""
        if 'failure_type' in data and isinstance(data['failure_type'], str):
            data['failure_type'] = FailureType(data['failure_type'])
        if 'severity' in data and isinstance(data['severity'], str):
            data['severity'] = FailureSeverity(data['severity'])
        return cls(**data)


@dataclass
class RecoveryStrategy:
    """Defines a recovery strategy for specific failure types."""
    strategy_id: str
    name: str
    failure_types: List[FailureType]
    actions: List[str]  # Action names to execute
    max_attempts: int = 3
    delay_between_attempts: int = 10  # seconds
    escalation_strategy: Optional[str] = None  # Strategy to use if this fails
    enabled: bool = True


class RecoveryEngine:
    """
    Engine for detecting and recovering from failures.
    
    Features:
    - Failure detection via monitoring
    - Configurable recovery strategies
    - Escalation policies
    - Health monitoring
    - Audit logging
    """
    
    def __init__(self, hermes_home: Optional[Path] = None):
        self.hermes_home = hermes_home or self._get_hermes_home()
        self.failures: Dict[str, FailureEvent] = {}
        self.strategies: Dict[str, RecoveryStrategy] = {}
        self._recovery_handlers: Dict[str, Callable] = {}
        self._running = False
        self._monitor_task: Optional[asyncio.Task] = None
        self._lock = asyncio.Lock()
        
        # Configuration
        self.health_check_interval = int(os.environ.get('RECOVERY_HEALTH_INTERVAL', '30'))
        self.failure_retention_hours = int(os.environ.get('RECOVERY_RETENTION_HOURS', '72'))
        
        # Persistence
        self.state_file = self.hermes_home / 'orchestration' / 'recovery_state.json'
        self.audit_file = self.hermes_home / 'logs' / 'recovery_audit.jsonl'
        
        # Register default strategies
        self._register_default_strategies()
    
    def _get_hermes_home(self) -> Path:
        """Get HERMES_HOME directory."""
        return Path(os.environ.get('HERMES_HOME', Path.home() / '.hermes'))
    
    def _ensure_directories(self) -> None:
        """Ensure required directories exist."""
        (self.hermes_home / 'orchestration').mkdir(parents=True, exist_ok=True)
        (self.hermes_home / 'logs').mkdir(parents=True, exist_ok=True)
    
    # -------------------------------------------------------------------------
    # Strategy Registration
    # -------------------------------------------------------------------------
    
    def _register_default_strategies(self) -> None:
        """Register default recovery strategies."""
        # Agent crash recovery
        self.register_strategy(RecoveryStrategy(
            strategy_id="agent_restart",
            name="Agent Restart",
            failure_types=[FailureType.AGENT_CRASH, FailureType.AGENT_HUNG],
            actions=["restart_agent", "verify_health"],
            max_attempts=3,
            delay_between_attempts=30,
        ))
        
        # Task failure recovery
        self.register_strategy(RecoveryStrategy(
            strategy_id="task_retry",
            name="Task Retry",
            failure_types=[FailureType.TASK_FAILED, FailureType.TASK_TIMEOUT],
            actions=["retry_task", "notify_if_failed"],
            max_attempts=3,
            delay_between_attempts=60,
        ))
        
        # Resource exhaustion recovery
        self.register_strategy(RecoveryStrategy(
            strategy_id="resource_cleanup",
            name="Resource Cleanup",
            failure_types=[FailureType.RESOURCE_EXHAUSTED, FailureType.DISK_FULL, FailureType.MEMORY_PRESSURE],
            actions=["cleanup_resources", "verify_health", "escalate_if_needed"],
            max_attempts=2,
            delay_between_attempts=60,
        ))
        
        # Connection recovery
        self.register_strategy(RecoveryStrategy(
            strategy_id="connection_recover",
            name="Connection Recovery",
            failure_types=[FailureType.CONNECTION_LOST],
            actions=["reconnect", "verify_connection", "escalate_if_needed"],
            max_attempts=5,
            delay_between_attempts=10,
        ))
    
    def register_strategy(self, strategy: RecoveryStrategy) -> None:
        """Register a recovery strategy."""
        self.strategies[strategy.strategy_id] = strategy
        logger.info(f"Registered recovery strategy: {strategy.name}")
    
    def register_recovery_handler(self, action_name: str, handler: Callable) -> None:
        """Register a handler for a recovery action."""
        self._recovery_handlers[action_name] = handler
        logger.debug(f"Registered recovery handler: {action_name}")
    
    # -------------------------------------------------------------------------
    # Failure Detection
    # -------------------------------------------------------------------------
    
    async def detect_failure(
        self,
        failure_type: FailureType,
        source: str,
        message: str,
        severity: Optional[FailureSeverity] = None,
        metadata: Optional[Dict[str, Any]] = None,
    ) -> str:
        """
        Detect and record a failure.
        
        Args:
            failure_type: Type of failure
            source: Agent ID, task ID, or component name
            message: Failure description
            severity: Failure severity (auto-detected if not provided)
            metadata: Additional failure metadata
            
        Returns:
            Failure ID
        """
        if severity is None:
            severity = self._classify_severity(failure_type)
        
        failure_id = f"failure_{uuid.uuid4().hex[:8]}"
        failure = FailureEvent(
            failure_id=failure_id,
            failure_type=failure_type,
            severity=severity,
            source=source,
            message=message,
            metadata=metadata or {},
        )
        
        async with self._lock:
            self.failures[failure_id] = failure
            await self._save_state()
        
        logger.warning(f"Detected failure {failure_id}: {failure_type.value} in {source}")
        await self._log_audit(failure, "detected")
        
        # Trigger recovery
        asyncio.create_task(self._initiate_recovery(failure_id))
        
        return failure_id
    
    def _classify_severity(self, failure_type: FailureType) -> FailureSeverity:
        """Classify failure severity based on type."""
        severity_map = {
            FailureType.AGENT_CRASH: FailureSeverity.HIGH,
            FailureType.AGENT_HUNG: FailureSeverity.HIGH,
            FailureType.TASK_FAILED: FailureSeverity.MEDIUM,
            FailureType.TASK_TIMEOUT: FailureSeverity.MEDIUM,
            FailureType.RESOURCE_EXHAUSTED: FailureSeverity.HIGH,
            FailureType.CONNECTION_LOST: FailureSeverity.MEDIUM,
            FailureType.DISK_FULL: FailureSeverity.CRITICAL,
            FailureType.MEMORY_PRESSURE: FailureSeverity.HIGH,
            FailureType.HEALTH_CHECK_FAILED: FailureSeverity.HIGH,
            FailureType.UNKNOWN: FailureSeverity.MEDIUM,
        }
        return severity_map.get(failure_type, FailureSeverity.MEDIUM)
    
    # -------------------------------------------------------------------------
    # Recovery Execution
    # -------------------------------------------------------------------------
    
    async def _initiate_recovery(self, failure_id: str) -> None:
        """Initiate recovery for a failure."""
        failure = self.failures.get(failure_id)
        if not failure or failure.resolved:
            return
        
        # Find applicable strategy
        strategy = self._find_strategy(failure.failure_type)
        if not strategy:
            logger.warning(f"No recovery strategy for failure {failure_id}: {failure.failure_type.value}")
            return
        
        logger.info(f"Initiating recovery for {failure_id} using strategy: {strategy.name}")
        
        # Execute recovery actions
        success = await self._execute_strategy(failure_id, strategy)
        
        if success:
            failure.resolved = True
            failure.resolved_at = datetime.utcnow().isoformat()
            failure.resolution = "Recovery successful"
            logger.info(f"Recovery successful for {failure_id}")
        else:
            logger.error(f"Recovery failed for {failure_id}")
            failure.resolution = "Recovery failed - manual intervention required"
        
        await self._save_state()
        await self._log_audit(failure, "recovery_completed")
    
    def _find_strategy(self, failure_type: FailureType) -> Optional[RecoveryStrategy]:
        """Find a recovery strategy for the failure type."""
        for strategy in self.strategies.values():
            if strategy.enabled and failure_type in strategy.failure_types:
                return strategy
        return None
    
    async def _execute_strategy(self, failure_id: str, strategy: RecoveryStrategy) -> bool:
        """Execute a recovery strategy."""
        failure = self.failures.get(failure_id)
        if not failure:
            return False
        
        for attempt in range(strategy.max_attempts):
            failure.recovery_attempts = attempt + 1
            logger.info(f"Recovery attempt {attempt + 1}/{strategy.max_attempts} for {failure_id}")
            
            all_success = True
            for action_name in strategy.actions:
                success = await self._execute_action(failure_id, action_name)
                if not success:
                    all_success = False
                    failure.recovery_actions.append(f"FAILED: {action_name}")
                    break
                failure.recovery_actions.append(f"OK: {action_name}")
            
            if all_success:
                return True
            
            if attempt < strategy.max_attempts - 1:
                logger.info(f"Waiting {strategy.delay_between_attempts}s before next attempt")
                await asyncio.sleep(strategy.delay_between_attempts)
        
        # Escalate if strategy has escalation
        if strategy.escalation_strategy:
            escalation = self.strategies.get(strategy.escalation_strategy)
            if escalation:
                logger.info(f"Escalating to strategy: {escalation.name}")
                return await self._execute_strategy(failure_id, escalation)
        
        return False
    
    async def _execute_action(self, failure_id: str, action_name: str) -> bool:
        """Execute a single recovery action."""
        handler = self._recovery_handlers.get(action_name)
        if not handler:
            logger.error(f"Recovery handler not found: {action_name}")
            return False
        
        failure = self.failures.get(failure_id)
        try:
            if asyncio.iscoroutinefunction(handler):
                await handler(failure)
            else:
                handler(failure)
            return True
        except Exception as e:
            logger.error(f"Recovery action {action_name} failed: {e}")
            return False
    
    # -------------------------------------------------------------------------
    # Health Monitoring
    # -------------------------------------------------------------------------
    
    async def start_monitoring(self) -> None:
        """Start health monitoring."""
        if self._running:
            return
        
        self._running = True
        self._monitor_task = asyncio.create_task(self._monitoring_loop())
        logger.info("Recovery engine monitoring started")
    
    async def stop_monitoring(self) -> None:
        """Stop health monitoring."""
        self._running = False
        if self._monitor_task:
            self._monitor_task.cancel()
            try:
                await self._monitor_task
            except asyncio.CancelledError:
                pass
            self._monitor_task = None
        logger.info("Recovery engine monitoring stopped")
    
    async def _monitoring_loop(self) -> None:
        """Background monitoring loop."""
        while self._running:
            try:
                await asyncio.sleep(self.health_check_interval)
                await self._check_system_health()
                await self._cleanup_old_failures()
            except asyncio.CancelledError:
                break
            except Exception as e:
                logger.error(f"Recovery monitoring error: {e}")
    
    async def _check_system_health(self) -> None:
        """Check overall system health."""
        # Check for unresolved high-severity failures
        critical_failures = [
            f for f in self.failures.values()
            if not f.resolved and f.severity in (FailureSeverity.HIGH, FailureSeverity.CRITICAL)
        ]
        
        if critical_failures:
            logger.warning(f"{len(critical_failures)} critical failures require attention")
            for failure in critical_failures[:5]:  # Log first 5
                logger.warning(f"  - {failure.failure_id}: {failure.failure_type.value} ({failure.source})")
    
    async def _cleanup_old_failures(self) -> None:
        """Clean up old resolved failures."""
        cutoff = datetime.utcnow() - timedelta(hours=self.failure_retention_hours)
        to_remove = []
        
        for failure_id, failure in self.failures.items():
            if failure.resolved and failure.resolved_at:
                try:
                    resolved_at = datetime.fromisoformat(failure.resolved_at)
                    if resolved_at < cutoff:
                        to_remove.append(failure_id)
                except ValueError:
                    pass
        
        if to_remove:
            async with self._lock:
                for failure_id in to_remove:
                    del self.failures[failure_id]
            logger.info(f"Cleaned up {len(to_remove)} old failures")
    
    # -------------------------------------------------------------------------
    # Persistence
    # -------------------------------------------------------------------------
    
    async def _save_state(self) -> None:
        """Persist recovery state to disk."""
        self._ensure_directories()
        try:
            state = {
                'timestamp': datetime.utcnow().isoformat(),
                'failures': {fid: f.to_dict() for fid, f in self.failures.items()},
                'strategies': {sid: asdict(s) for sid, s in self.strategies.items()},
            }
            temp_file = self.state_file.with_suffix('.tmp')
            temp_file.write_text(json.dumps(state, indent=2))
            temp_file.rename(self.state_file)
        except Exception as e:
            logger.error(f"Failed to save recovery state: {e}")
    
    async def _load_state(self) -> None:
        """Load recovery state from disk."""
        if not self.state_file.exists():
            return
        
        try:
            content = self.state_file.read_text()
            state = json.loads(content)
            
            for failure_id, failure_data in state.get('failures', {}).items():
                self.failures[failure_id] = FailureEvent.from_dict(failure_data)
            
            logger.info(f"Loaded recovery state: {len(self.failures)} failures")
        except Exception as e:
            logger.error(f"Failed to load recovery state: {e}")
    
    async def _log_audit(self, failure: FailureEvent, event_type: str) -> None:
        """Log recovery audit entry."""
        try:
            audit_entry = {
                'timestamp': datetime.utcnow().isoformat(),
                'event_type': event_type,
                'failure': failure.to_dict(),
            }
            with open(self.audit_file, 'a') as f:
                f.write(json.dumps(audit_entry) + '\n')
        except Exception as e:
            logger.error(f"Failed to write audit log: {e}")
    
    # -------------------------------------------------------------------------
    # Queries
    # -------------------------------------------------------------------------
    
    def get_failure(self, failure_id: str) -> Optional[FailureEvent]:
        """Get failure by ID."""
        return self.failures.get(failure_id)
    
    def list_failures(
        self,
        severity: Optional[FailureSeverity] = None,
        resolved: Optional[bool] = None,
        source: Optional[str] = None,
    ) -> List[FailureEvent]:
        """List failures with optional filters."""
        failures = list(self.failures.values())
        
        if severity is not None:
            failures = [f for f in failures if f.severity == severity]
        if resolved is not None:
            failures = [f for f in failures if f.resolved == resolved]
        if source is not None:
            failures = [f for f in failures if f.source == source]
        
        return failures
    
    def get_active_failures(self) -> List[FailureEvent]:
        """Get all unresolved failures."""
        return [f for f in self.failures.values() if not f.resolved]
    
    def get_stats(self) -> Dict[str, Any]:
        """Get recovery engine statistics."""
        active = self.get_active_failures()
        by_severity = {}
        by_type = {}
        
        for failure in self.failures.values():
            sev = failure.severity.value if isinstance(failure.severity, FailureSeverity) else failure.severity
            by_severity[sev] = by_severity.get(sev, 0) + 1
            
            ftype = failure.failure_type.value if isinstance(failure.failure_type, FailureType) else failure.failure_type
            by_type[ftype] = by_type.get(ftype, 0) + 1
        
        return {
            'total_failures': len(self.failures),
            'active_failures': len(active),
            'by_severity': by_severity,
            'by_type': by_type,
            'strategies_registered': len(self.strategies),
            'monitoring_active': self._running,
        }


# Global recovery engine instance
_recovery_engine: Optional[RecoveryEngine] = None


def get_recovery_engine() -> RecoveryEngine:
    """Get or create the global recovery engine."""
    global _recovery_engine
    if _recovery_engine is None:
        _recovery_engine = RecoveryEngine()
    return _recovery_engine


async def initialize_recovery() -> RecoveryEngine:
    """Initialize the recovery engine."""
    engine = get_recovery_engine()
    await engine._load_state()
    await engine.start_monitoring()
    return engine
