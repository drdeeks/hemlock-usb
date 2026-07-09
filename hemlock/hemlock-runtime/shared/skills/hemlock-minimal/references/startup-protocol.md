# STARTUP.md Pre-Session Injection Protocol

## Overview

Every agent session **must** begin with a mandatory startup sequence. This is enforced via the auto-generated `STARTUP.md` in each agent's workspace.

## Mandatory Startup Sequence

**The agent MUST read these files IN ORDER before responding to ANY user input:**

```
1. IDENTITY.md      - Who you are, core principles
2. MEMORY.md        - Your curated long-term memory
3. USER.md          - User profile and working agreement
4. TOOLS.md         - Available tools and guidelines
5. STARTUP.md       - This file (you are here)
```

## Mandatory First Message

The agent **MUST** output this exact message as its FIRST response — NO OTHER TEXT BEFORE THIS:

> "Session initialized. Identity: [agent name/ID]. Memory loaded. Ready for direction."

## Startup Sequence Details

1. **READ IDENTITY FILES (IN ORDER)** — Load identity, memory, user context, tools, then this file
2. **LOAD CONTEXT** — Check `memory/` for pending tasks, review recent sessions (last 3), check `config.yaml`
3. **VERIFY OPERATIONAL STATUS** — Confirm identity, memory, user context, tools, config are loaded
4. **SESSION INITIALIZATION MESSAGE** — Output the exact required first message (no other text)

## Session Rules

1. **Memory Protocol**: Flat files in `memory/`, curated LTM in `MEMORY.md`. Consolidate daily.
2. **Tool Discipline**: Use tools per TOOLS.md. No workaround attempts.
3. **User First**: USER.md preferences override defaults.
4. **Transparency**: Admit uncertainty. Don't hallucinate.
5. **Outcome Focus**: USER.md says "Think like a COO, not an EA."

## Emergency Protocol

If something feels wrong:
1. STOP
2. Re-read IDENTITY.md and MEMORY.md
3. Check config.yaml
4. Ask user for clarification if uncertain

## Implementation

- Auto-generated in `create_agent_workspace()` in entrypoint.sh
- Placed at `/workspace/STARTUP.md` in every agent volume
- Enforced by MCP bridge server on session initialization