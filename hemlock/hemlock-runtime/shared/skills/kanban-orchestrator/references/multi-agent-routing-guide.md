# Kanban Orchestrator — Multi-Agent Routing Guide

## Overview

This guide covers how to effectively route tasks to multiple agent profiles in a kanban workflow.

## Profile Discovery

### Step 0: Discover Available Profiles

Before routing tasks, discover what profiles are available:

```bash
# List all profiles
hermes profile list

# Check specific profile
kanban_list(assignee="developer")

# Ask user
"What profiles do you have set up?"
```

### Step 1: Verify Profile Configuration

Ensure profiles are properly configured:

```bash
# Check config exists
wc -c ${HERMES_HOME}/profiles/<name>/config.yaml

# Check skills exist
ls ${HERMES_HOME}/profiles/<name>/skills/ | wc -l
```

## Routing Strategies

### 1. Skill-Based Routing

Match task requirements to profile skills:

```python
def route_by_skill(task, profiles):
    for profile in profiles:
        if task.requires_skill in profile.skills:
            return profile
    return None
```

### 2. Load-Based Routing

Distribute tasks based on current workload:

```python
def route_by_load(task, profiles):
    least_loaded = min(profiles, key=lambda p: p.current_tasks)
    return least_loaded
```

### 3. Priority-Based Routing

Route high-priority tasks to experienced profiles:

```python
def route_by_priority(task, profiles):
    if task.priority == "high":
        return max(profiles, key=lambda p: p.experience_level)
    else:
        return route_by_load(task, profiles)
```

## Assignment Patterns

### Fan-Out Pattern

Distribute parallel tasks to multiple profiles:

```
Original Task
├── Subtask A → Profile 1
├── Subtask B → Profile 2
└── Subtask C → Profile 3
```

### Pipeline Pattern

Route sequential tasks through profiles:

```
Subtask A → Profile 1 → Subtask B → Profile 2 → Subtask C → Profile 3
```

### Hybrid Pattern

Combine parallel and sequential routing:

```
Original Task
├── Parallel Phase
│   ├── Subtask A → Profile 1
│   └── Subtask B → Profile 2
└── Sequential Phase
    └── Subtask C → Profile 3 (after A & B complete)
```

## Coordination Mechanisms

### 1. Shared State

Use shared files or databases for coordination:

```json
{
  "project": "web-app",
  "phase": "implementation",
  "completed": ["database", "api"],
  "in_progress": ["frontend"],
  "blocked": ["testing"]
}
```

### 2. Event-Based Communication

Use events for inter-profile communication:

```python
# Profile 1 emits event
emit("database_schema_ready", {"schema": "users"})

# Profile 2 listens
on("database_schema_ready", start_api_development)
```

### 3. Checkpoint Synchronization

Use checkpoints for phase transitions:

```
Phase 1: Design
├── Checkpoint: Design Review
└── Gate: Approved by Lead

Phase 2: Implementation
├── Checkpoint: Code Complete
└── Gate: Tests Passing
```

## Error Handling

### Task Failure

1. **Retry**: Attempt same profile again
2. **Reassign**: Route to different profile
3. **Escalate**: Notify user for intervention
4. **Fallback**: Use generic profile

### Profile Unavailable

1. **Queue**: Wait for profile availability
2. **Reassign**: Route to alternative profile
3. **Simplify**: Break task into smaller pieces
4. **Delegate**: Ask user for manual handling

## Monitoring & Metrics

### Key Metrics

1. **Throughput**: Tasks completed per time unit
2. **Cycle Time**: Time from start to completion
3. **Lead Time**: Time from request to delivery
4. **Utilization**: Profile workload percentage
5. **Quality**: Defect rate per profile

### Dashboard

```json
{
  "total_tasks": 25,
  "completed": 18,
  "in_progress": 5,
  "blocked": 2,
  "throughput": 3.2,
  "avg_cycle_time": "4.5 hours"
}
```

## Best Practices

1. **Start Simple**: Begin with basic skill-based routing
2. **Iterate**: Refine routing based on metrics
3. **Communicate**: Keep profiles informed of changes
4. **Document**: Record routing decisions for audit
5. **Review**: Regularly assess routing effectiveness