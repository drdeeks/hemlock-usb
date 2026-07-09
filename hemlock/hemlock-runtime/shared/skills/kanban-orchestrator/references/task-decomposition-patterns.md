# Kanban Orchestrator — Task Decomposition Patterns

## Overview

This document describes common patterns for decomposing complex tasks into manageable subtasks for multi-agent routing.

## Decomposition Strategies

### 1. Functional Decomposition

Break task by functional areas:

```
Task: "Build a web application"
├── Frontend (UI/UX)
├── Backend (API/Logic)
├── Database (Storage)
├── Testing (Quality)
└── Deployment (Infrastructure)
```

### 2. Phase-Based Decomposition

Break task by implementation phases:

```
Task: "Implement authentication system"
├── Phase 1: Requirements Analysis
├── Phase 2: Design & Architecture
├── Phase 3: Implementation
├── Phase 4: Testing
└── Phase 5: Deployment
```

### 3. Component-Based Decomposition

Break task by system components:

```
Task: "Integrate payment processing"
├── Payment Gateway Integration
├── Transaction Management
├── Security & Compliance
├── Error Handling
└── Monitoring & Logging
```

## Routing Rules

### Profile Matching

1. **Skill-based routing**: Match task requirements to profile skills
2. **Load balancing**: Distribute tasks across available profiles
3. **Dependency awareness**: Route dependent tasks to same profile when possible
4. **Priority routing**: High-priority tasks to most experienced profiles

### Fallback Strategies

1. **Generic profile**: Use a general-purpose profile for unmatched tasks
2. **User intervention**: Escalate to user when no suitable profile exists
3. **Task simplification**: Break down further until matchable

## Anti-Patterns

### 1. Over-Decomposition

Creating too many subtasks increases coordination overhead.

**Rule**: Maximum 5-7 subtasks per decomposition.

### 2. Under-Decomposition

Leaving tasks too large makes them hard to route and track.

**Rule**: Each subtask should be completable in 1-4 hours.

### 3. Ignoring Dependencies

Not considering task dependencies leads to blocked workflows.

**Rule**: Map dependencies before routing.

## Examples

### Example 1: Feature Development

**Original Task**: "Implement user profile management"

**Decomposition**:
1. Database schema design → Database specialist
2. API endpoint implementation → Backend developer
3. Frontend UI components → Frontend developer
4. Integration testing → QA engineer
5. Documentation → Technical writer

### Example 2: Bug Fix

**Original Task**: "Fix login timeout issue"

**Decomposition**:
1. Root cause analysis → Senior developer
2. Implement fix → Backend developer
3. Add monitoring → DevOps engineer
4. Verify fix → QA engineer
5. Update documentation → Technical writer

## Best Practices

1. **Clear boundaries**: Each subtask should have clear start/end criteria
2. **Minimal overlap**: Subtasks should not duplicate work
3. **Traceability**: Link subtasks back to original requirements
4. **Progress tracking**: Enable independent progress monitoring
5. **Quality gates**: Define verification criteria for each subtask