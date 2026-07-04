#!/usr/bin/env python3
"""
Orchestration Layer Load Test

Validates orchestration components under load:
- Spawns multiple agents simultaneously
- Schedules many concurrent tasks
- Simulates failures and verifies recovery
- Measures performance and stability
"""

import asyncio
import logging
import os
import sys
import time
from pathlib import Path
from typing import List, Dict, Any
from datetime import datetime

# Add parent directory to path
sys.path.insert(0, str(Path(__file__).parent.parent))

from orchestration import (
    initialize_orchestration,
    shutdown_orchestration,
    get_orchestration_stats,
)
from orchestration.lifecycle_manager import AgentState
from orchestration.scheduler import TaskPriority, TaskState
from orchestration.recovery_engine import FailureType, FailureSeverity

logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s [%(levelname)s] %(name)s: %(message)s'
)
logger = logging.getLogger(__name__)


class OrchestrationLoadTest:
    """Load test for orchestration layer."""
    
    def __init__(self, hermes_home: Path):
        self.hermes_home = hermes_home
        self.lifecycle = None
        self.scheduler = None
        self.recovery = None
        self.results: Dict[str, Any] = {}
    
    async def setup(self) -> None:
        """Initialize orchestration components."""
        logger.info("Setting up orchestration load test...")
        self.lifecycle, self.scheduler, self.recovery = await initialize_orchestration(
            hermes_home=self.hermes_home
        )
        logger.info("Setup complete")
    
    async def teardown(self) -> None:
        """Shutdown orchestration components."""
        logger.info("Tearing down...")
        await shutdown_orchestration(timeout=10)
        logger.info("Teardown complete")
    
    async def test_agent_lifecycle(self, num_agents: int = 10) -> Dict[str, Any]:
        """Test spawning and managing multiple agents."""
        logger.info(f"Testing agent lifecycle with {num_agents} agents...")
        start_time = time.time()
        
        # Spawn agents
        agent_ids = []
        spawn_times = []
        
        for i in range(num_agents):
            t0 = time.time()
            agent_id = await self.lifecycle.spawn_agent(
                name=f"test-agent-{i}",
                model="test-model",
                platform="test",
            )
            agent_ids.append(agent_id)
            spawn_times.append(time.time() - t0)
        
        spawn_duration = time.time() - start_time
        logger.info(f"Spawned {num_agents} agents in {spawn_duration:.2f}s")
        
        # Wait for agents to start
        await asyncio.sleep(0.5)
        
        # Check agent states
        running_count = 0
        for agent_id in agent_ids:
            agent = self.lifecycle.get_agent(agent_id)
            if agent and agent.state == AgentState.RUNNING:
                running_count += 1
        
        # Stop agents
        stop_start = time.time()
        stop_tasks = [self.lifecycle.stop_agent(aid) for aid in agent_ids]
        await asyncio.gather(*stop_tasks)
        stop_duration = time.time() - stop_start
        
        results = {
            'num_agents': num_agents,
            'spawn_duration_sec': round(spawn_duration, 3),
            'avg_spawn_time_sec': round(sum(spawn_times) / len(spawn_times), 3),
            'running_count': running_count,
            'success_rate': round(running_count / num_agents * 100, 1),
            'stop_duration_sec': round(stop_duration, 3),
        }
        
        logger.info(f"Agent lifecycle test complete: {results}")
        return results
    
    async def test_task_scheduling(self, num_tasks: int = 50) -> Dict[str, Any]:
        """Test scheduling and executing multiple tasks."""
        logger.info(f"Testing task scheduling with {num_tasks} tasks...")
        start_time = time.time()
        
        # Register test handler
        executed_tasks = []
        
        async def test_handler(task_id, **kwargs):
            executed_tasks.append(task_id)
            await asyncio.sleep(0.01)  # Simulate work
        
        self.scheduler.register_handler("test_handler", test_handler)
        
        # Schedule tasks
        task_ids = []
        for i in range(num_tasks):
            task_id = self.scheduler.schedule_task(
                name=f"test-task-{i}",
                handler="test_handler",
                run_at=datetime.utcnow().isoformat(),  # Run immediately
                priority=TaskPriority.NORMAL,
            )
            task_ids.append(task_id)
        
        schedule_duration = time.time() - start_time
        logger.info(f"Scheduled {num_tasks} tasks in {schedule_duration:.2f}s")
        
        # Wait for tasks to execute
        await asyncio.sleep(2)
        
        # Check execution
        executed_count = len(executed_tasks)
        
        results = {
            'num_tasks': num_tasks,
            'schedule_duration_sec': round(schedule_duration, 3),
            'executed_count': executed_count,
            'execution_rate': round(executed_count / num_tasks * 100, 1),
        }
        
        logger.info(f"Task scheduling test complete: {results}")
        return results
    
    async def test_failure_recovery(self, num_failures: int = 5) -> Dict[str, Any]:
        """Test failure detection and recovery."""
        logger.info(f"Testing failure recovery with {num_failures} failures...")
        start_time = time.time()
        
        # Register recovery handler
        recovery_count = [0]
        
        async def test_recovery_handler(failure):
            recovery_count[0] += 1
            logger.info(f"Recovery executed for {failure.failure_id}")
        
        self.recovery.register_recovery_handler("test_recovery", test_recovery_handler)
        
        # Register strategy
        from orchestration.recovery_engine import RecoveryStrategy
        self.recovery.register_strategy(RecoveryStrategy(
            strategy_id="test_strategy",
            name="Test Recovery",
            failure_types=[FailureType.UNKNOWN],
            actions=["test_recovery"],
            max_attempts=1,
        ))
        
        # Simulate failures
        failure_ids = []
        for i in range(num_failures):
            failure_id = await self.recovery.detect_failure(
                failure_type=FailureType.UNKNOWN,
                source=f"test-source-{i}",
                message=f"Test failure {i}",
                severity=FailureSeverity.MEDIUM,
            )
            failure_ids.append(failure_id)
        
        detect_duration = time.time() - start_time
        
        # Wait for recovery
        await asyncio.sleep(1)
        
        # Check recovery
        resolved_count = sum(
            1 for fid in failure_ids
            if self.recovery.get_failure(fid) and self.recovery.get_failure(fid).resolved
        )
        
        results = {
            'num_failures': num_failures,
            'detect_duration_sec': round(detect_duration, 3),
            'recovery_count': recovery_count[0],
            'resolved_count': resolved_count,
            'recovery_rate': round(resolved_count / num_failures * 100, 1),
        }
        
        logger.info(f"Failure recovery test complete: {results}")
        return results
    
    async def test_concurrent_operations(self, agents: int = 5, tasks: int = 20) -> Dict[str, Any]:
        """Test concurrent agent and task operations."""
        logger.info(f"Testing concurrent operations: {agents} agents, {tasks} tasks...")
        start_time = time.time()
        
        # Register handler
        async def concurrent_handler(**kwargs):
            await asyncio.sleep(0.01)
        
        self.scheduler.register_handler("concurrent_handler", concurrent_handler)
        
        # Spawn agents and schedule tasks concurrently
        async def spawn_agents():
            agent_ids = []
            for i in range(agents):
                agent_id = await self.lifecycle.spawn_agent(
                    name=f"concurrent-agent-{i}",
                    model="test",
                )
                agent_ids.append(agent_id)
            return agent_ids
        
        async def schedule_tasks():
            task_ids = []
            for i in range(tasks):
                task_id = self.scheduler.schedule_task(
                    name=f"concurrent-task-{i}",
                    handler="concurrent_handler",
                    run_at=datetime.utcnow().isoformat(),
                )
                task_ids.append(task_id)
            return task_ids
        
        # Run concurrently
        agent_ids, task_ids = await asyncio.gather(
            spawn_agents(),
            asyncio.create_task(schedule_tasks()),
        )
        
        concurrent_duration = time.time() - start_time
        
        # Wait for operations to complete
        await asyncio.sleep(2)
        
        # Check results
        running_agents = len(self.lifecycle.get_running_agents())
        scheduled_tasks = len(self.scheduler.get_scheduled_tasks())
        
        results = {
            'agents_spawned': len(agent_ids),
            'tasks_scheduled': len(task_ids),
            'concurrent_duration_sec': round(concurrent_duration, 3),
            'running_agents': running_agents,
            'scheduled_tasks': scheduled_tasks,
        }
        
        logger.info(f"Concurrent operations test complete: {results}")
        return results
    
    async def run_all_tests(self) -> Dict[str, Any]:
        """Run all load tests."""
        logger.info("=" * 60)
        logger.info("Starting Orchestration Layer Load Test")
        logger.info("=" * 60)
        
        total_start = time.time()
        
        try:
            # Run tests
            self.results['agent_lifecycle'] = await self.test_agent_lifecycle(num_agents=10)
            self.results['task_scheduling'] = await self.test_task_scheduling(num_tasks=50)
            self.results['failure_recovery'] = await self.test_failure_recovery(num_failures=5)
            self.results['concurrent_operations'] = await self.test_concurrent_operations(
                agents=5, tasks=20
            )
            
            # Get final stats
            self.results['final_stats'] = get_orchestration_stats()
            
        except Exception as e:
            logger.error(f"Test failed: {e}")
            self.results['error'] = str(e)
        
        total_duration = time.time() - total_start
        self.results['total_duration_sec'] = round(total_duration, 3)
        
        # Summary
        logger.info("=" * 60)
        logger.info("Load Test Summary")
        logger.info("=" * 60)
        logger.info(f"Total duration: {total_duration:.2f}s")
        for test_name, test_results in self.results.items():
            if isinstance(test_results, dict) and 'success_rate' in test_results:
                logger.info(f"  {test_name}: {test_results['success_rate']}% success")
            elif isinstance(test_results, dict) and 'execution_rate' in test_results:
                logger.info(f"  {test_name}: {test_results['execution_rate']}% execution")
        
        return self.results


async def main():
    """Main entry point."""
    # Use test HERMES_HOME
    hermes_home = Path(os.environ.get('HERMES_HOME', Path.home() / '.hermes'))
    
    test = OrchestrationLoadTest(hermes_home=hermes_home)
    
    try:
        await test.setup()
        results = await test.run_all_tests()
        
        # Save results
        import json
        results_file = hermes_home / 'orchestration' / 'load_test_results.json'
        results_file.parent.mkdir(parents=True, exist_ok=True)
        results_file.write_text(json.dumps(results, indent=2))
        logger.info(f"Results saved to {results_file}")
        
        # Exit with error if tests failed
        if 'error' in results:
            sys.exit(1)
        
    except Exception as e:
        logger.exception(f"Test failed: {e}")
        sys.exit(1)
    finally:
        await test.teardown()


if __name__ == "__main__":
    asyncio.run(main())
