#!/usr/bin/env python3
"""
Hermes Task Scheduler

Schedules and executes timed and event-based tasks for agents.
Supports cron-like schedules, one-time tasks, and event-triggered tasks.

Features:
- Cron-style scheduling (minute, hour, day, month, weekday)
- One-time scheduled tasks
- Event-triggered tasks
- Task priorities and dependencies
- Task execution tracking and retry logic
- Persistent task queue
"""

import asyncio
import json
import logging
import os
import re
from datetime import datetime, timedelta
from enum import Enum
from pathlib import Path
from typing import Any, Callable, Dict, List, Optional, Set
from dataclasses import dataclass, field, asdict
import uuid

logger = logging.getLogger(__name__)


class TaskState(Enum):
    """Task execution states."""
    PENDING = "pending"
    SCHEDULED = "scheduled"
    RUNNING = "running"
    COMPLETED = "completed"
    FAILED = "failed"
    CANCELLED = "cancelled"
    RETRYING = "retrying"


class TaskPriority(Enum):
    """Task priority levels."""
    LOW = 0
    NORMAL = 1
    HIGH = 2
    CRITICAL = 3


@dataclass
class ScheduledTask:
    """Represents a scheduled task."""
    task_id: str
    name: str
    handler: str  # Handler function/coroutine name
    schedule: Optional[str] = None  # Cron expression or None for one-time
    run_at: Optional[str] = None  # ISO format datetime for one-time tasks
    event_trigger: Optional[str] = None  # Event name that triggers this task
    args: List[Any] = field(default_factory=list)
    kwargs: Dict[str, Any] = field(default_factory=dict)
    priority: TaskPriority = TaskPriority.NORMAL
    max_retries: int = 3
    retry_delay: int = 60  # seconds
    timeout: int = 300  # seconds
    enabled: bool = True
    state: TaskState = TaskState.PENDING
    created_at: str = field(default_factory=lambda: datetime.utcnow().isoformat())
    last_run: Optional[str] = None
    next_run: Optional[str] = None
    run_count: int = 0
    error_message: Optional[str] = None
    metadata: Dict[str, Any] = field(default_factory=dict)
    
    def to_dict(self) -> Dict[str, Any]:
        """Convert to dictionary for JSON serialization."""
        return {
            **asdict(self),
            'schedule': self.schedule,
            'priority': self.priority.value if isinstance(self.priority, TaskPriority) else self.priority,
            'state': self.state.value if isinstance(self.state, TaskState) else self.state,
        }
    
    @classmethod
    def from_dict(cls, data: Dict[str, Any]) -> 'ScheduledTask':
        """Create from dictionary."""
        if 'priority' in data and isinstance(data['priority'], int):
            data['priority'] = TaskPriority(data['priority'])
        if 'state' in data and isinstance(data['state'], str):
            data['state'] = TaskState(data['state'])
        return cls(**data)


class CronParser:
    """Parse and evaluate cron expressions."""
    
    # Cron field ranges: minute, hour, day, month, weekday
    FIELD_RANGES = [
        (0, 59),   # minute
        (0, 23),   # hour
        (1, 31),   # day of month
        (1, 12),   # month
        (0, 6),    # day of week (0 = Sunday)
    ]
    
    FIELD_NAMES = ['minute', 'hour', 'day', 'month', 'weekday']
    
    @classmethod
    def parse(cls, expression: str) -> List[Set[int]]:
        """
        Parse cron expression into sets of valid values for each field.
        
        Supports:
        - * (any value)
        - n (specific value)
        - n,m (multiple values)
        - n-m (range)
        - n/m (step)
        - */m (step from start)
        """
        parts = expression.strip().split()
        if len(parts) != 5:
            raise ValueError(f"Invalid cron expression: expected 5 fields, got {len(parts)}")
        
        result = []
        for i, part in enumerate(parts):
            min_val, max_val = cls.FIELD_RANGES[i]
            values = cls._parse_field(part, min_val, max_val)
            result.append(values)
        
        return result
    
    @classmethod
    def _parse_field(cls, field: str, min_val: int, max_val: int) -> Set[int]:
        """Parse a single cron field."""
        values = set()
        
        for part in field.split(','):
            if part == '*':
                values.update(range(min_val, max_val + 1))
            elif '/' in part:
                # Step value
                base, step = part.split('/', 1)
                step = int(step)
                if base == '*':
                    start = min_val
                else:
                    start = int(base)
                values.update(range(start, max_val + 1, step))
            elif '-' in part:
                # Range
                start, end = part.split('-', 1)
                values.update(range(int(start), int(end) + 1))
            else:
                # Single value
                values.add(int(part))
        
        # Validate range
        if not all(min_val <= v <= max_val for v in values):
            raise ValueError(f"Value out of range for field: {field}")
        
        return values
    
    @classmethod
    def matches(cls, expression: str, dt: datetime) -> bool:
        """Check if datetime matches cron expression."""
        try:
            fields = cls.parse(expression)
        except ValueError:
            return False
        
        return (
            dt.minute in fields[0] and
            dt.hour in fields[1] and
            dt.day in fields[2] and
            dt.month in fields[3] and
            dt.weekday() in fields[4]  # Python weekday: 0=Monday
        )
    
    @classmethod
    def next_run(cls, expression: str, after: Optional[datetime] = None) -> datetime:
        """Calculate next run time after given datetime."""
        after = after or datetime.utcnow()
        dt = after.replace(second=0, microsecond=0) + timedelta(minutes=1)
        
        # Search up to 1 year ahead
        max_iterations = 366 * 24 * 60
        for _ in range(max_iterations):
            if cls.matches(expression, dt):
                return dt
            dt += timedelta(minutes=1)
        
        raise ValueError(f"Could not find next run time for: {expression}")


class TaskScheduler:
    """
    Scheduler for timed and event-based tasks.
    
    Features:
    - Cron-style scheduling
    - One-time scheduled tasks
    - Event-triggered tasks
    - Task priorities
    - Retry logic
    - Persistence
    """
    
    def __init__(self, hermes_home: Optional[Path] = None):
        self.hermes_home = hermes_home or self._get_hermes_home()
        self.tasks: Dict[str, ScheduledTask] = {}
        self._handlers: Dict[str, Callable] = {}
        self._event_subscribers: Dict[str, List[str]] = {}  # event -> task_ids
        self._running = False
        self._scheduler_task: Optional[asyncio.Task] = None
        self._lock = asyncio.Lock()
        
        # Configuration
        self.check_interval = int(os.environ.get('SCHEDULER_CHECK_INTERVAL', '10'))  # seconds
        
        # Persistence
        self.state_file = self.hermes_home / 'orchestration' / 'scheduler_state.json'
    
    def _get_hermes_home(self) -> Path:
        """Get HERMES_HOME directory."""
        return Path(os.environ.get('HERMES_HOME', Path.home() / '.hermes'))
    
    def _ensure_directories(self) -> None:
        """Ensure required directories exist."""
        (self.hermes_home / 'orchestration').mkdir(parents=True, exist_ok=True)
    
    # -------------------------------------------------------------------------
    # Task Registration
    # -------------------------------------------------------------------------
    
    def register_handler(self, name: str, handler: Callable) -> None:
        """Register a task handler function."""
        self._handlers[name] = handler
        logger.debug(f"Registered task handler: {name}")
    
    def schedule_task(
        self,
        name: str,
        handler: str,
        schedule: Optional[str] = None,
        run_at: Optional[str] = None,
        event_trigger: Optional[str] = None,
        args: Optional[List[Any]] = None,
        kwargs: Optional[Dict[str, Any]] = None,
        priority: TaskPriority = TaskPriority.NORMAL,
        **options
    ) -> str:
        """
        Schedule a new task.
        
        Args:
            name: Human-readable task name
            handler: Handler function name (must be registered)
            schedule: Cron expression (e.g., "*/5 * * * *" for every 5 minutes)
            run_at: ISO format datetime for one-time tasks
            event_trigger: Event name that triggers this task
            args: Positional arguments for handler
            kwargs: Keyword arguments for handler
            priority: Task priority level
            **options: Additional options (max_retries, retry_delay, timeout)
            
        Returns:
            Task ID
        """
        task_id = f"task_{uuid.uuid4().hex[:8]}"
        
        task = ScheduledTask(
            task_id=task_id,
            name=name,
            handler=handler,
            schedule=schedule,
            run_at=run_at,
            event_trigger=event_trigger,
            args=args or [],
            kwargs=kwargs or {},
            priority=priority,
            **options
        )
        
        # Calculate next run time
        if schedule:
            try:
                task.next_run = CronParser.next_run(schedule).isoformat()
                task.state = TaskState.SCHEDULED
            except ValueError as e:
                logger.error(f"Invalid schedule for task {task_id}: {e}")
                task.state = TaskState.FAILED
                task.error_message = str(e)
        elif run_at:
            task.next_run = run_at
            task.state = TaskState.SCHEDULED
        elif event_trigger:
            task.state = TaskState.PENDING
            # Subscribe to event
            if event_trigger not in self._event_subscribers:
                self._event_subscribers[event_trigger] = []
            self._event_subscribers[event_trigger].append(task_id)
        else:
            task.state = TaskState.PENDING
            logger.warning(f"Task {task_id} has no schedule, run_at, or event_trigger")
        
        self.tasks[task_id] = task
        logger.info(f"Scheduled task {task_id}: {name}")
        return task_id
    
    def cancel_task(self, task_id: str) -> bool:
        """Cancel a scheduled task."""
        task = self.tasks.get(task_id)
        if not task:
            return False
        
        if task.state in (TaskState.COMPLETED, TaskState.CANCELLED):
            return False
        
        task.state = TaskState.CANCELLED
        logger.info(f"Cancelled task {task_id}: {task.name}")
        return True
    
    def enable_task(self, task_id: str) -> bool:
        """Enable a task."""
        task = self.tasks.get(task_id)
        if not task:
            return False
        task.enabled = True
        return True
    
    def disable_task(self, task_id: str) -> bool:
        """Disable a task."""
        task = self.tasks.get(task_id)
        if not task:
            return False
        task.enabled = False
        return True
    
    # -------------------------------------------------------------------------
    # Event Handling
    # -------------------------------------------------------------------------
    
    async def trigger_event(self, event_name: str, data: Optional[Dict[str, Any]] = None) -> None:
        """Trigger an event, executing all subscribed tasks."""
        task_ids = self._event_subscribers.get(event_name, [])
        if not task_ids:
            logger.debug(f"No tasks subscribed to event: {event_name}")
            return
        
        logger.info(f"Triggering event: {event_name} ({len(task_ids)} tasks)")
        
        for task_id in task_ids:
            task = self.tasks.get(task_id)
            if task and task.enabled and task.state == TaskState.PENDING:
                asyncio.create_task(self._execute_task(task_id, event_data=data))
    
    # -------------------------------------------------------------------------
    # Task Execution
    # -------------------------------------------------------------------------
    
    async def _execute_task(self, task_id: str, event_data: Optional[Dict[str, Any]] = None) -> None:
        """Execute a task."""
        task = self.tasks.get(task_id)
        if not task or not task.enabled:
            return
        
        handler = self._handlers.get(task.handler)
        if not handler:
            logger.error(f"Task {task_id} handler not found: {task.handler}")
            task.state = TaskState.FAILED
            task.error_message = f"Handler not found: {task.handler}"
            return
        
        try:
            task.state = TaskState.RUNNING
            task.last_run = datetime.utcnow().isoformat()
            task.run_count += 1
            
            logger.info(f"Executing task {task_id}: {task.name}")
            
            # Merge event data into kwargs
            kwargs = {**task.kwargs, **(event_data or {})}
            
            # Execute handler with timeout
            if asyncio.iscoroutinefunction(handler):
                await asyncio.wait_for(
                    handler(*task.args, **kwargs),
                    timeout=task.timeout
                )
            else:
                await asyncio.get_event_loop().run_in_executor(
                    None,
                    lambda: handler(*task.args, **kwargs)
                )
            
            task.state = TaskState.COMPLETED
            logger.info(f"Task {task_id} completed successfully")
            
        except asyncio.TimeoutError:
            logger.error(f"Task {task_id} timed out after {task.timeout}s")
            task.error_message = f"Timeout after {task.timeout}s"
            await self._handle_task_failure(task_id)
            
        except Exception as e:
            logger.error(f"Task {task_id} failed: {e}")
            task.error_message = str(e)
            await self._handle_task_failure(task_id)
        
        finally:
            # Schedule next run if recurring
            if task.state == TaskState.COMPLETED and task.schedule:
                try:
                    task.next_run = CronParser.next_run(task.schedule).isoformat()
                    task.state = TaskState.SCHEDULED
                except ValueError:
                    task.state = TaskState.FAILED
    
    async def _handle_task_failure(self, task_id: str) -> None:
        """Handle task failure with retry logic."""
        task = self.tasks.get(task_id)
        if not task:
            return
        
        if task.run_count <= task.max_retries:
            task.state = TaskState.RETRYING
            logger.info(f"Task {task_id} will retry in {task.retry_delay}s")
            await asyncio.sleep(task.retry_delay)
            asyncio.create_task(self._execute_task(task_id))
        else:
            task.state = TaskState.FAILED
            logger.error(f"Task {task_id} failed after {task.max_retries} retries")
    
    # -------------------------------------------------------------------------
    # Scheduler Loop
    # -------------------------------------------------------------------------
    
    async def start(self) -> None:
        """Start the scheduler."""
        if self._running:
            return
        
        self._running = True
        await self._load_state()
        self._scheduler_task = asyncio.create_task(self._scheduler_loop())
        logger.info("Task scheduler started")
    
    async def stop(self) -> None:
        """Stop the scheduler."""
        self._running = False
        if self._scheduler_task:
            self._scheduler_task.cancel()
            try:
                await self._scheduler_task
            except asyncio.CancelledError:
                pass
            self._scheduler_task = None
        await self._save_state()
        logger.info("Task scheduler stopped")
    
    async def _scheduler_loop(self) -> None:
        """Main scheduler loop."""
        while self._running:
            try:
                await asyncio.sleep(self.check_interval)
                await self._check_scheduled_tasks()
            except asyncio.CancelledError:
                break
            except Exception as e:
                logger.error(f"Scheduler loop error: {e}")
    
    async def _check_scheduled_tasks(self) -> None:
        """Check and execute due scheduled tasks."""
        now = datetime.utcnow()
        
        async with self._lock:
            for task in self.tasks.values():
                if not task.enabled or task.state not in (TaskState.SCHEDULED, TaskState.PENDING):
                    continue
                
                # Check time-based tasks
                if task.next_run:
                    try:
                        next_run = datetime.fromisoformat(task.next_run)
                        if now >= next_run:
                            asyncio.create_task(self._execute_task(task.task_id))
                    except ValueError:
                        logger.warning(f"Invalid next_run for task {task.task_id}")
    
    # -------------------------------------------------------------------------
    # Persistence
    # -------------------------------------------------------------------------
    
    async def _save_state(self) -> None:
        """Persist scheduler state to disk."""
        self._ensure_directories()
        try:
            state = {
                'timestamp': datetime.utcnow().isoformat(),
                'tasks': {tid: task.to_dict() for tid, task in self.tasks.items()},
                'event_subscribers': self._event_subscribers,
            }
            temp_file = self.state_file.with_suffix('.tmp')
            temp_file.write_text(json.dumps(state, indent=2))
            temp_file.rename(self.state_file)
            logger.debug(f"Saved scheduler state for {len(self.tasks)} tasks")
        except Exception as e:
            logger.error(f"Failed to save scheduler state: {e}")
    
    async def _load_state(self) -> None:
        """Load scheduler state from disk."""
        if not self.state_file.exists():
            return
        
        try:
            content = self.state_file.read_text()
            state = json.loads(content)
            
            for task_id, task_data in state.get('tasks', {}).items():
                self.tasks[task_id] = ScheduledTask.from_dict(task_data)
            
            self._event_subscribers = state.get('event_subscribers', {})
            
            logger.info(f"Loaded scheduler state for {len(self.tasks)} tasks")
        except Exception as e:
            logger.error(f"Failed to load scheduler state: {e}")
    
    # -------------------------------------------------------------------------
    # Queries
    # -------------------------------------------------------------------------
    
    def get_task(self, task_id: str) -> Optional[ScheduledTask]:
        """Get task by ID."""
        return self.tasks.get(task_id)
    
    def list_tasks(self, state: Optional[TaskState] = None) -> List[ScheduledTask]:
        """List tasks, optionally filtered by state."""
        if state:
            return [t for t in self.tasks.values() if t.state == state]
        return list(self.tasks.values())
    
    def get_pending_tasks(self) -> List[ScheduledTask]:
        """Get all pending tasks."""
        return self.list_tasks(TaskState.PENDING)
    
    def get_scheduled_tasks(self) -> List[ScheduledTask]:
        """Get all scheduled tasks."""
        return self.list_tasks(TaskState.SCHEDULED)
    
    def get_stats(self) -> Dict[str, Any]:
        """Get scheduler statistics."""
        states = {}
        for task in self.tasks.values():
            state_name = task.state.value if isinstance(task.state, TaskState) else task.state
            states[state_name] = states.get(state_name, 0) + 1
        
        return {
            'total_tasks': len(self.tasks),
            'states': states,
            'handlers_registered': len(self._handlers),
            'events_subscribed': len(self._event_subscribers),
            'scheduler_running': self._running,
        }


# Global scheduler instance
_scheduler: Optional[TaskScheduler] = None


def get_scheduler() -> TaskScheduler:
    """Get or create the global scheduler."""
    global _scheduler
    if _scheduler is None:
        _scheduler = TaskScheduler()
    return _scheduler


async def initialize_scheduler() -> TaskScheduler:
    """Initialize the scheduler."""
    scheduler = get_scheduler()
    await scheduler.start()
    return scheduler
