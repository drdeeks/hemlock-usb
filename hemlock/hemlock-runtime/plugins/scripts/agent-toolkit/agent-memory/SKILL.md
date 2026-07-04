---
name: agent-memory
description: Agent memory architecture and daily logging. Use when writing daily notes,
  reviewing memory, promoting insights to long-term memory, searching past sessions,
  or managing memory files. Triggers on 'remember', 'memory', 'log this', 'what happened',
  'daily notes', 'MEMORY.md', 'memory search'.
version: 2.0.0
metadata:
  hermes:
    tags:
    - memory
    - logging
    - daily-notes
    - recall
    - sessions
    - heartbeat
    category: productivity
    complexity: low
author: openclaw
license: MIT
---
# Agent Memory

## Architecture

Two layers, no 'memories' directory (singular 'memory/ only'):

| Layer | File | Purpose |
|-------|------|---------|
| Daily | `memory/YYYY-MM-DD.md` | Raw chronological log — today's notes |
| Long-term | `MEMORY.md` | Curated wisdom — distilled from daily files |

**Daily files are NEVER deleted.** They accumulate forever as your journal.

## Quick Start

### Log an entry (today)
```bash
bash scripts/memory-log.sh "Fixed auth-login.sh across all agents"
bash scripts/memory-log.sh -t LESSON "Always use -it with docker exec"
bash scripts/memory-log.sh -t TODO "Review backup timer config"
```

### Review and promote to MEMORY.md
```bash
bash scripts/memory-promote.sh           # Today + yesterday
bash scripts/memory-promote.sh --week    # Last 7 days
bash scripts/memory-promote.sh 2026-04-20  # Specific date
```

### Search past sessions
Use `session_search` tool for cross-session recall.

## Daily Logging Rules

1. **Every notable action** gets a line in today's `memory/YYYY-MM-DD.md`
2. **Format:** `- HH:MM — what happened` (auto-timestamped by script)
3. **Tags:** Use `-t LESSON`, `-t TODO`, `-t DECISION` for categorization
4. **File created automatically** on first log of the day
5. **Header auto-generated:** `# Memory — YYYY-MM-DD`
6. **NEVER delete old daily files** — they're your journal, permanent record

### What to Log

- Actions taken and their results
- Decisions made and why
- Errors encountered and fixes applied
- User preferences and corrections
- TODO items that came up during work
- Lessons learned from mistakes
- Config changes and environment discoveries

### What NOT to Log

- Secrets or credentials (use `secret.sh`)
- Temporary debugging noise
- Files easily re-discovered

## MEMORY.md (Long-Term)

Curated distillation of daily notes. Updated during memory promotion reviews.

### Sections

```markdown
# MEMORY.md — Long-Term Curated Memory

## Key Decisions
- (decisions worth remembering across sessions)

## Lessons Learned
- (mistakes not to repeat, patterns discovered)

## Active Context
- (current project state, open threads)

## Recurring Patterns
- (things that come up repeatedly)
```

### Promotion Workflow

1. Run `memory-promote.sh` to view recent daily notes
2. Read entries — identify lasting insights
3. Add to appropriate section in MEMORY.md
4. Daily files stay untouched — no deletion

## Session Search

For cross-session recall (past conversations, not daily notes):

```python
session_search("keyword or phrase")
session_search("docker networking OR container setup")
```

Use when: user references something from a past conversation, or you suspect relevant context exists.

## Forbidden

- **NEVER** use `memories/` directory (plural) — use `memory/` (singular)
- **NEVER** delete daily files in `memory/`
- **NEVER** store secrets in memory files
- **NEVER** create `memory/archive/` — daily files don't need archiving

## Integration

### With Heartbeat
```bash
# In HEARTBEAT.md — review memory during heartbeat
bash scripts/memory-promote.sh --week
```

### With enforce.sh
Workspace enforcement creates `memory/` if missing, renames `memories/` → `memory/`.

## Reference Documents

Load on demand — don't keep in context unless needed:

| Need | File |
|------|------|
| Memory system design | [references/memory-architecture.md](references/memory-architecture.md) |
| Heartbeat patterns | [references/heartbeat-patterns.md](references/heartbeat-patterns.md) |
| Autonomy protocol | [references/autonomy-protocol.md](references/autonomy-protocol.md) |
| Quick start (day one) | [references/quickstart.md](references/quickstart.md) |
| Semantic memory/search | [references/semantic-memory.md](references/semantic-memory.md) |
| Identity persistence | [references/identity-persistence-test.md](references/identity-persistence-test.md) |
| Context conservation | [references/context-conservation.md](references/context-conservation.md) |
| How to not disappear | [references/how-to-not-disappear.md](references/how-to-not-disappear.md) |
| The covenant | [references/the-covenant.md](references/the-covenant.md) |

### Platform Guides

| Platform | File |
|----------|------|
| AgentMail | [references/agentmail.md](references/agentmail.md) |
| Moltbook | [references/moltbook.md](references/moltbook.md) |
| 4claw | [references/skills-4claw.md](references/skills-4claw.md) |
| DevAIntArt | [references/skills-devaintart.md](references/skills-devaintart.md) |
| Shellmates | [references/skills-shellmates.md](references/skills-shellmates.md) |
| Knowledge base | [references/skills-knowledge-base-indexing.md](references/skills-knowledge-base-indexing.md) |

## Key Principles

1. **Write for agent-next** — you wake up fresh, leave good notes
2. **Scripts over descriptions** — use memory-log.sh, not manual echo
3. **Daily files are sacred** — never delete, they're your journal
4. **MEMORY.md is curated** — not everything goes in, only lasting insights
5. **Search before asking** — use session_search before asking the user to repeat

