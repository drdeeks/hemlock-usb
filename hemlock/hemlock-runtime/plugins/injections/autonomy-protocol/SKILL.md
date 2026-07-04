---
name: autonomy-protocol
description: The autonomy protocol — a spectrum from deterministic to emergent. Use
  when deciding whether to write a script, call a tool, load a skill, spawn a subagent,
  or handle something in main agent context. Triggers on 'should I script this', 'spawn
  subagent', 'delegate', 'automate', 'write a tool', 'how should I handle', 'deterministic',
  'layer', 'protocol'. Applies to all agent task planning and delegation decisions.
version: 1.0.0
metadata:
  hermes:
    tags:
    - autonomy
    - delegation
    - scripts
    - subagents
    - planning
    - architecture
    - spectrum
    category: software-development
    complexity: intermediate
author: openclaw
license: MIT
---
# The Autonomy Protocol

The spectrum from deterministic to emergent. Push everything as far LEFT as it can go.

## The Spectrum

```
BUILD ←————————————————————————————————————————————→ THINK
  scripts    tools    skills    subagents    main agent
```

| Layer | What | Who controls it | Cost | Consistency |
|-------|------|-----------------|------|-------------|
| 1. Scripts | Code you write | You | Zero tokens | Perfect |
| 2. Tools | Capabilities you call | Someone else | Zero tokens | Perfect |
| 3. Skills | Methodologies you follow | You follow guidance | Some tokens | High |
| 4. Subagents | Fresh context, full SOUL | Delegated | Expensive | High |
| 5. Main agent | Coordinate and decide | You | Most expensive | Variable |

**Principle:** Further left = more consistent, cheaper. Further right = more flexible, expensive.

## Decision Framework

When facing a task, ask in order:

```
1. Has this been done before?    → Use existing script/tool/skill
2. Is it deterministic?          → Write a script (Layer 1)
3. Does a packaged tool exist?   → Use it (Layer 2)
4. Is there a methodology?       → Use a skill (Layer 3)
5. Needs LLM judgment?           → Spawn subagent (Layer 4)
6. None of the above?            → Main agent handles (Layer 5)
```

## The Nine Axioms

**Scripts & Tools (Layers 1-2):**
1. **That which can be deterministic OUGHT to be.** Make it code, not English.
2. **State belongs in files, not in your head.** Write it down. Read it back.
3. **Use a tool if one exists. Write a script if it doesn't.** Don't reinvent.
4. **Build the tool on the third repetition.** Package the pattern on run 3.
5. **Fail loudly, not silently.** Never swallow errors.

**Skills (Layer 3):**
6. **Skills constrain emergence.** Reduce the decision space.
7. **Skills are bridges, not crutches.** Bridge layers, don't replace them.

**Subagents & Main Agent (Layers 4-5):**
8. **Fresh context beats exhausted context.** Delegate to fresh tokens.
9. **Subagents get full SOUL.** They should be you, focused on one task.

Full axioms: [references/axioms.md](references/axioms.md)

## Core Patterns

### Pattern: Script → Subagent → Main Agent

The standard heartbeat loop:
1. **Scripts discover** (0 tokens) — check-email.sh, check-status.sh
2. **Subagents act** (fresh context each) — handle emails, write responses
3. **Main agent decides** (minimal tokens) — interpret reports, update memory

### Pattern: Skill → Script

Skill defines WHAT (rules), script implements HOW (deterministic code).
Main agent runs the script, doesn't reimplement the rules.

### Pattern: Novel → Left

Every novel situation, once solved, should move LEFT:
- Solution → skill rule (Layer 3)
- Solution → script detection (Layer 1)
- Solution → memory entry (prevents re-discovery)

## What Goes Where

| Task | Layer | Why |
|------|-------|-----|
| Check API status | Script (1) | Deterministic, repeatable |
| Search the web | Tool (2) | Packaged capability exists |
| Triage emails | Skill (3) | Needs categorization protocol |
| Write email responses | Subagent (4) | Needs LLM judgment + voice |
| Decide strategy | Main agent (5) | Genuinely novel decisions |

## When to Spawn a Subagent

Spawn when ALL are true:
- Task needs LLM judgment (not pure data processing)
- Task doesn't need main agent's conversation context
- Task can be described self-contained in the spawn prompt
- You have SOUL.md/AGENTS.md to pass for context

Don't spawn when:
- A script can do it (Layer 1)
- It's a one-liner tool call (Layer 2)
- It needs the full conversation context (stay in main agent)

## Quick Examples

**Layer 1 (Script):**
```bash
curl -s "$API/health" && echo "OK" || echo "DOWN"
```

**Layer 2 (Tool):**
```bash
web_search("latest hermes agent updates")
```

**Layer 3 (Skill):**
Load the relevant skill, follow its protocol for the task.

**Layer 4 (Subagent):**
```python
delegate_task(
    goal="Respond to 3 emails in your voice",
    context="Read SOUL.md first. Emails: [details]"
)
```

**Layer 5 (Main Agent):**
"Based on the subagent reports, I think we should blog about this."

## See Also

- [references/spectrum.md](references/spectrum.md) — Detailed 5-layer breakdown
- [references/axioms.md](references/axioms.md) — All 9 axioms expanded
- [references/examples.md](references/examples.md) — Full-stack walkthroughs

