# Kanban-Driven Sequential Project Execution

## Owner Preference: One Project at a Time

When running multiple hackathon projects, execute ONE project at a time via kanban:
- Queue all projects as kanban tasks with priority ordering
- Complete one project fully before starting the next
- Each project task body includes: track, requirements, model mapping, queue position
- Use `status='ready'` for the current project, keep others as separate tasks
- After completing a project, mark it `done` and promote the next

Kanban task template:
```
id: t_<project>_001
title: <project>: Full hackathon build — Qwen-powered <Name> (<Track>)
assignee: <project>-orchestrator
status: ready (current) | pending (queued)
body: TRACK, DEADLINE, QUEUE POSITION, REQUIREMENTS, MODEL MAPPING, WHAT TO BUILD
workspace_kind: scratch  ← MUST be 'scratch', NOT 'project' (dispatcher rejects 'project')
workspace_path: $HEMLOCK_HOME/kanban/workspaces/t_<project>_001
```

