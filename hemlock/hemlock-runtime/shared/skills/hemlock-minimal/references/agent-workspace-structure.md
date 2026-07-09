# Agent Workspace Structure (Corrected)

## Overview

Each agent gets a complete, self-contained workspace in its Docker volume (`hemlock-agent-<id>`). This workspace includes all identity, memory, tools, and skills needed for the agent to operate independently and portably.

## Complete Workspace Layout

```
/workspace/ (inside agent volume)
├── agent.json          # Identity + model config {id, name, model, provider, status, created}
├── SOUL.md             # Agent personality/purpose
├── IDENTITY.md         # Core identity + principles (COO not EA, genuine, memory persists)
├── USER.md             # User profile + working agreement
├── TOOLS.md            # Available tools + guidelines + restrictions
├── MEMORY.md           # Curated long-term memory (LTM) - SINGLE FILE
├── STARTUP.md          # Pre-session injection protocol (MANDATORY)
├── HEARTBEAT.md        # Agent heartbeat configuration
├── config.yaml         # Runtime config (model, tools, memory, consolidation)
├── .env                # API keys (600 perms)
├── avatars/            # Agent avatars (included in Minimal export)
├── tools/              # Custom tools (included in Minimal export)
├── skills/             # COPIED from /skills (NOT symlinked)
├── memory/             # FLAT - NO subdirectories
│   ├── 20260613-meeting-notes.md
│   ├── 20260613-api-discovery.md
│   ├── session-20260613T143022.md
│   └── ... (all flat files)
├── sessions/           # Session markers
│   └── session-20260613T143022.md
├── .secrets/           # Encrypted secrets (default perms, NO 700)
├── logs/
├── media/
├── projects/
├── config/
├── cron/
└── # NO symlinks for skills - agents COPY what they need
```

## Critical Corrections (from conversation)

| Aspect | Old (Wrong) | New (Correct) |
|---|---|---|
| Memory structure | `memory/{short-term,long-term,pending,archived}/` | `memory/` FLAT only |
| MEMORY.md | Curated LTM | **Only** curated LTM file |
| Skills | Symlinked from `/shared-skills` | **COPIED** from `/skills` to `skills/` |
| Export Minimal | Included config/env | **NO config, NO .env** — only core identity |
| Export Standard | All recent memory | **Latest 5 sessions/ + Latest 5 memory/** |
| Skills volume | `/shared-skills` symlink | `/skills` read-only volume, agents COPY |

## Memory Hierarchy

```
MEMORY.md                 ← Curated LTM (permanent, manual consolidation)
memory/                   ← Flat STM files (auto-expire)
  ├── 20260613-notes.md
  ├── session-20260613T143022.md
  └── ...

NO subdirectories: short-term/, long-term/, pending/, archived/
```

## Skills Management

- `/skills` = Read-only volume at container root with 100+ DrDeeks skills
- Agents **COPY** skills: `copy-skills <agent_id> [skill1 skill2...]`
- On export: agent's `skills/` directory included (Standard/Full)
- No symlinks — complete self-contained package on export

## Export Mode Inclusions

| Mode | Includes `skills/`? | Includes `memory/`? | Includes `sessions/`? |
|---|---|---|---|
| Minimal | No | No | No |
| Standard | Yes (copied) | Latest 5 only | Latest 5 only |
| Full | Yes | All | All |