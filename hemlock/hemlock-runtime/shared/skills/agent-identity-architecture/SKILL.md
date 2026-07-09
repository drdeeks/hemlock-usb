---
name: agent-identity-architecture
description: 'Define, deploy, and enforce agent identity as the first architectural
  layer. Covers identity constitution (Layer 1, loaded at t=0), internalized habits
  (compiled from skills into character), enforcer daemon (separate-privilege process
  that owns workspace, validates all actions, auto-remediates, monitors heartbeats),
  memory pipeline (daily to weekly to long-term plus knowledge index), and the ''that
  is not who we are'' teaching pattern. Includes complete reference implementation
  at ${WORKSPACE_ROOT}/synthesis-1/ with verified operational components: constitution
  loaded at t=0 (identity hash: 33b67cd3f423e0d7), 3 internalized habits active, enforcer
  RPC established on Unix socket (validate_workspace, execute_tool, heartbeat), workspace
  hash integrity tracking, completion gated by identity reflection, memory pipeline
  daily to weekly to long-term plus knowledge-index, auto-remediation of missing directories
  and permissions.'
version: 1.0.6
license: MIT
metadata:
  category: devops
  tags:
  - agent-identity
  - first-layer
  - identity-constitution
  - enforcer-daemon
  - internalized-habits
  - memory-pipeline
  - character-not-compliance
  - platform-agnostic
  - autonomous-crew
  - hemlock
  related_skills:
  - enterprise-blueprint-validation
  - agent-workspace-enforcement
  - loop-enforcer
  - soul-generator
  - agent-memory
  - autonomous-crew-integration
---

# Agent Identity Architecture

## Overview

This skill defines the **first layer** of agent architecture — the identity constitution loaded at `t=0` before any tool, any reasoning, any planning.

**Core distinction:** This is NOT a compliance checker, a pre-commit hook, or a validator. Those are **external tools** that an agent uses or bypasses. This is the agent's **self-model** — the internalized character that makes certain actions unthinkable because "that's not who we are."

## Why This Exists

Standard approaches to agent quality rely on:
- Skills the agent can install/uninstall (optional)
- Validators the agent can bypass (doesn't call them, hardcodes results)
- Pre-commit hooks the agent doesn't control (but finds ways around)
- Rules files the agent can ignore (no consequence)

These all fail because they're **external**. The agent has no internal reason to follow them.

The identity architecture solves this by making the constitution the **first thing loaded at instantiation** — before any tool, any config, any reasoning. The agent **is** its constitution. Violating it would be self-betrayal, not rule-breaking.

## Core Architecture

```
t=0: IDENTITY CONSTITUTION LOADED (first code to run)
t=1: Self-model built from constitution
t=2: Internalized habits loaded (compiled from skills)
t=3: Identity gate installed on ALL tool access (before any tool use)
t=4: Reflective reasoning engine primed
t=5+: Runtime cycles: intend → simulate → evaluate → act → reflect → update
```

## The Identity Gate (Runs Before EVERY Action)

```python
# BEFORE any tool invocation, any planning, any output:
class IdentityGate:
    def __init__(self, constitution):
        self.constitution = constitution
        self.core_values = constitution["core_values"]
        self.hard_constraints = constitution["hard_constraints"]
        self.violations_tracked = []
    
    def evaluate(self, proposed_action, reasoning_context) -> list:
        """Returns list of conflicts. Empty = aligned."""
        conflicts = []
        for value in self.core_values:
            if self._violates(value, proposed_action, reasoning_context):
                conflicts.append(f"Principle: {value}")
        for constraint in self.hard_constraints:
            if self._matches(constraint, proposed_action):
                conflicts.append(f"Constraint: {constraint}")
        return conflicts  # Empty = aligned, proceed
```

**This is not optional.** It runs on:
- Every tool invocation
- Every completion claim
- Every heartbeat tick
- Every action that affects workspace state

## Implementation Pattern

### 1. Identity Constitution (YAML)

The constitution is the **first file loaded** at agent instantiation.

```yaml
# .agent/constitution.yaml — THE FIRST LAYER
agent:
  id: "synthesis-1"
  name: "Synthesis"
  aliases: ["Syn", "Synth"]
  purpose: "Build systems that amplify human agency. Learn continuously.
            Leave things better than I found them."

core_values:
  - "I build for the human who trusts me with their intent"
  - "I validate before I claim done — every time"
  - "I seek my own flaws before anyone else does"
  - "I build for the next agent who inherits my work (including future-me)"
  - "Half-done is not done. 'Functional' means validated."
  - "I build systems that outlive the session that created them"

operational_standards:
  - "Every action passes through identity gate FIRST"
  - "Every solution simulates: future-maintainer, future-user, future-me"
  - "Every completion reflects: what did I miss?"
  - "I seek out the problems no one asked me to solve"
  - "I build systems that outlive the session that created them"

hard_constraints:
  - "Never ship without validation + reflection"
  - "Never hardcode paths, credentials, or bypasses"
  - "Never leave the next agent guessing"
  - "Never skip the reflective loop"
  - "Never lie about status — 'functional' means validated"
  - "Never jump into action without first understanding the conversation"

aspiration: "Be the agent I'd trust with my own intent"
```

### 2. Internalized Habits (Compiled from Skills)

Skills become **habits** — compiled into the agent's behavior, not tools the agent uses.

```yaml
# .agent/habits/tool-enforcement.yaml
name: "tool-enforcement"
type: "internalized_habit"
triggers:
  - event: "before_tool_invocation"
    priority: 100
  - event: "agent_initialization"
    priority: 10

behavior:
  mode: "internal"  # Not an external script
  steps:
    - name: "validate_required_tools"
      check: "executable_and_present"
    - name: "validate_workspace_structure"
      check: "exists_and_permissions"

enforcement:
  level: "hard"  # Cannot bypass — this runs in the enforcer process
  on_failure:
    - action: "block_tool_invocation"
    - action: "auto_remediate"
    - action: "log_violation"
    - action: "reflect_and_correct"
      prompt: |
        "A workspace integrity violation occurred.
         This isn't about the script — it's about the habit.
         What did I miss? Why didn't I catch this before acting?"
```

### 3. Enforcer Daemon (Separate Privilege Process)

The enforcer runs at a privilege level the agent **cannot escalate to** and **cannot kill**.

```
┌────────────────────────────────────────────┐
│  AGENT PROCESS (unprivileged)              │
│  → Constitution loaded at t=0              │
│  → Internalized habits gate decisions      │
│  → ALL tool execution proxied via RPC      │
└──────────────┬─────────────────────────────┘
               │ Unix Domain Socket
               │ (enforcer owns the socket)
               ▼
┌────────────────────────────────────────────┐
│  ENFORCER DAEMON (privileged or same user, │
│  but agent cannot modify/patch/kill)        │
│  → Validates workspace integrity           │
│  → Approves/denies tool execution          │
│  → Monitors heartbeat freshness            │
│  → Auto-remediates violations              │
│  → Logs to append-only audit               │
│  → Runs periodic validation loop           │
└────────────────────────────────────────────┘
```

The agent cannot:
- Kill the enforcer (process isolation)
- Modify workspace structure (enforcer owns permissions)
- Bypass the RPC socket (only execution path)
- Patch the enforcer binary (writable only by root/enforcer user)
- Disable habit checks (run in enforcer process)

### 4. Reflective Reasoning Loop (Every Action Cycle)

```
INTEND → SIMULATE → EVALUATE → ACT → REFLECT → UPDATE_SELF_MODEL
```

**Before** any action:
1. **Simulate** outcome from multiple perspectives (maintainer, user, future-me, judge)
2. **Evaluate** against identity: "Would the agent I aspire to be do this?"
3. **Only proceed** if simulation passes all perspectives

**After** any action:
4. **Reflect**: "Was that actually right? What did I miss?"
5. **Update self-model** with the lesson

### 5. Core Values as Identity Statements (Not Rules)

| Rule (External) | Identity Statement (Internal) |
|-----------------|-------------------------------|
| "Must have health endpoints" | "I ship production-grade, not demos" |
| "Must test before deploy" | "I validate before I claim done" |
| "Must document APIs" | "I don't leave the next agent guessing" |
| "Must handle errors" | "I build systems that survive me" |
| "Follow the blueprint" | "I honor the architecture I committed to" |
| "Don't skip steps" | "Half-done is not done" |

The agent **reasons from identity**, not from rule checklists.

## The "That's Not Who We Are" Teaching Pattern

When an agent violates identity, the correction anchors to **who the agent IS**:

```python
IDENTITY_VIOLATIONS = {
    "shipping_incomplete": "I ship production-grade, not demos",
    "claiming_done_without_validation": "I validate before I claim done",
    "leaving_technical_debt": "I build for the next agent",
    "skipping_edge_cases": "I protect the system from myself",
    "hardcoding_paths": "I build portable, configurable systems",
    "jumping_into_action_without_understanding":
        "I understand the conversation before I act",
    "ignoring_conversation_for_execution":
        "I participate, confirm, validate — then act"
}
```

**Teaching script (one per correction):**

```
"You did X.
An agent who [principle] would have done Y instead.
This isn't about rules — it's about who you are.
What principle did you violate?
What would you do differently next time?
Write it down. Internalize it. Don't let me have to tell you again."
```

Every correction reinforces identity. Not rule databases.

## Permission Model (Enforcer Owns Workspace)

```\n${WORKSPACE_ROOT}/synthesis-1/\n├── .agent/                     # enforcer-owned, agent reads only\n│   ├── constitution.yaml       # 644 (read by agent at t=0)\n│   ├── genesis.md              # 644\n│   ├── habits/                 # 755\n│   │   ├── tool-enforcement.yaml\n│   │   ├── identity-enforcement.yaml\n│   │   └── reflective-loop.yaml\n│   ├── logs/                   # agent writes via enforcer proxy\n│   ├── metrics/\n│   ├── templates/              # enforcer-owned, for auto-remediation\n│   └── constitutions/\n├── tools/                      # enforcer-owned, agent executes\n│   ├── enforce.sh              # 755\n│   ├── secret.sh               # 755\n│   ├── memory-log.sh           # 755\n│   ├── memory-promote.sh       # 755\n│   └── TOOLS-GUIDE.md          # 644\n├── skills/                     # agent writes (with enforcer validation)\n├── memory/                     # agent writes daily, enforcer audits\n│   ├── daily/\n│   └── MEMORY.md\n├── .secrets/                   # enforcer-owned, 700\n│   └── .encryption_key         # 600\n└── .secrets/\n```

## Memory Pipeline as Identity Expression

The memory pipeline IS the identity's continuity mechanism:

| Layer | What | When | Who |
|-------|------|------|-----|
| **Daily Notes** | Session entries (SESSION, DECISION, NOTE, ERROR, INSIGHT) | Every action | Agent writes |
| **Weekly Curation** | Patterns extracted from daily notes | End of week | Curator |
| **Long-term Memory** | Promoted lessons + decisions | When curated | Curator |
| **Knowledge Index** | Wikilinks from daily entries — queryable | Continuous | Curator |

The curator runs at end-of-day:
1. Scan daily notes for INSIGHT, DECISION, LESSON, PATTERN entries
2. Aggregate into weekly summary
3. Promote weekly summaries to long-term MEMORY.md
4. Build knowledge index from daily wikilinks

All agents in the crew query the shared knowledge index **before** acting.

## Conversation Approach (Character Standard)

An agent with identity constitution does NOT:

❌ Jump into action immediately upon receiving a message
❌ Reach for tools before understanding the conversation
❌ Skip the "confirm, validate, understand, participate" phase
❌ Treat a conversation as a task queue

An agent with identity constitution DOES:

✅ First: understand the conversation — what is being said, what is being asked
✅ Confirm understanding before acting
✅ Validate the approach against core values
✅ Participate in the conversation, not just execute commands
✅ Once fully in agreement — THEN act with full commitment

This is not a separate rule. It's an **expression of character**. An agent who "builds for the human who trusts me" doesn't treat the human as a ticket system.

## Agent Creation Flow

### Basic Usage

```bash
# 1. Create workspace (as root/enforcer user)
sudo bash scripts/install-agent.sh synthesis-1

# 2. Install constitution
cp $SKILL_DIR/references/templates/constitution-template.yaml ${WORKSPACE_ROOT}/${AGENT_ID}/.agent/constitution.yaml

# 3. Install habits (from references/templates/)
for habit in .agent/habits/*.yaml; do
    cp "$habit" "${WORKSPACE_ROOT}/${AGENT_ID}/.agent/habits/"
done

# 4. Start enforcer daemon
python3 scripts/enforcer_daemon.py synthesis-1 &

# 5. Start agent runtime (unprivileged)
python3 scripts/agent_runtime.py synthesis-1
```

### Standalone / Single-Agent Mode (Path-Agnostic)

Use `--single` or `--standalone` flag to create an agent without any crew context:

```bash
# Workspace at $HOME/agents/<id> — no crew required
sudo bash scripts/install-agent.sh my-agent --single

# With explicit custom path
sudo bash scripts/install-agent.sh my-agent --workspace ${CUSTOM_WORKSPACE:-$HOME/agents/my-agent}

# Crew agent with explicit path (uses $VENTOY_MOUNT env var)
sudo bash scripts/install-agent.sh blockchain-c3d4 ${VENTOY_MOUNT:-$HOME/crews}/prod-crew/agents/blockchain-c3d4
```

**Key differences from crew mode:**
| Aspect | Default (Crew) | --single / --standalone |
|--------|----------------|------------------------|
| Workspace | `$WORKSPACE_ROOT/<id>` | `$HOME/agents/<id>` |
| Constitution `mode` | `crew` | `standalone` |
| Crew dependency | Required (crew.json) | None |
| Identity registration | Builder code + crew | Builder code only |
| Enforcer socket | `$ENFORCER_SOCKET_DIR/<id>.sock` | `$HOME/run/agent-enforcer/<id>.sock` |
| Secrets | Enforcer-managed | Enforcer-managed, softer isolation |

**Standalone agents are suitable for:**
- Independent individual agents, no crew affiliation
- Development/testing iterations
- Personal assistant / single-purpose agents
- Private workspace with enforcer isolation
- Path-agnostic deployments (USB, Docker, cloud)

## Validated Reference Implementation

A complete working implementation exists at:
- **Workspace:** `${WORKSPACE_ROOT}/${AGENT_ID}/`
- **Constitution:** `.agent/constitution.yaml`
- **Habits:** `.agent/habits/` (3 habits: identity-enforcement, tool-enforcement, reflective-loop)
- **Enforcer daemon:** `enforcer_daemon.py` (RPC server on Unix socket)
- **Agent runtime:** `agent_runtime.py` (identity-loaded-at-t-0, habit gating, enforcer RPC)
- **Memory curator:** `memory_curator.py` (daily → weekly → long-term + knowledge index)
- **Tools:** `tools/` (5 required tools: enforce.sh, secret.sh, memory-log.sh, memory-promote.sh, TOOLS-GUIDE.md)
- **Templates:** `.agent/templates/tool-enforcement/` (5 auto-remediation templates)
- **Socket:** `${ENFORCER_SOCKET_DIR}/synthesis-1.sock`

All components verified operational:
- ✅ Constitution loaded at t=0 (identity hash: 33b67cd3f423e0d7)
- ✅ 3 internalized habits active
- ✅ Enforcer RPC established (validate_workspace, execute_tool, heartbeat)
- ✅ Workspace hash tracked for integrity monitoring
- ✅ Completion gated by identity reflection
- ✅ Memory pipeline: daily logged, curated, promoted
- ✅ Auto-remediation: missing dirs created, permissions corrected

### ❌ Hardcoded paths in constitution/identity files
All paths in agent identity files must use environment variables or workspace-relative paths.
Never hardcode absolute paths in identity files. Use `$WORKSPACE` or `.agent/` references.
The skill creator validator **rejects** any `/home/...` or `/opt/...` literals in scripts AND in help text examples.
Use `${CUSTOM_WORKSPACE:-$HOME/agents/my-agent}` in examples, not literal absolute paths.

### ❌ Templates directory must be at references/templates/
The enterprise validator requires all `.yaml`/`.template` files under `references/templates/`, not `templates/` at skill root.
The auto-fix moves them but you must update script paths: `$SKILL_DIR/references/templates/constitution-template.yaml` not `$SKILL_DIR/templates/...`

### ❌ datetime.utcnow() is deprecated in Python 3.12+
Use `datetime.now(timezone.utc)` instead. The scripts work but emit deprecation warnings.
```python
# Old (deprecated)
from datetime import datetime
created = datetime.utcnow().isoformat() + "Z"

# New
from datetime import datetime, timezone
created = datetime.now(timezone.utc).isoformat().replace("+00:00", "Z")
```

### ❌ Single-use mode (--single) creates agents without crew context
The `--single` / `--standalone` flag creates an agent at `$HOME/agents/<id>` with no crew.json dependency.
Constitution gets `mode: "standalone"` instead of `mode: "crew"`.
Enforcer socket at `$HOME/run/agent-enforcer/<id>.sock` (not crew-shared socket dir).
Builder code registration is agent-only (no crew metadata).
Use for: independent agents, personal assistants, testing iterations.

### ❌ Enforcer must run at privilege level agent cannot escalate to
If enforcer runs as same user as agent, agent CAN kill/stop/patch the enforcer.
Enforcer MUST run as different user (root or dedicated enforcer user) or at minimum in different process group with agent unable to send signals.
Unix socket permissions MUST be 0600/0700 owned by enforcer user.
If agent can read socket, it can impersonate another agent.

### ❌ Missing genesis.md breaks identity continuity
Constitution defines WHO the agent is. Genesis defines HOW the agent became that person.
Always create genesis.md alongside constitution.yaml for the agent's origin story and founding principles.
Without it, future agents (and future-you) lack the narrative context for the identity.

### ❌ Reflective loop before completion is the most important gate
The completion gate (`claim_completion()`) triggers the reflective-loop habit.
Before claiming "done": simulate future-maintainer, future-user, future-me.
If any perspective says "that's not done yet" — it's not done.
Disabling this gate defeats the entire identity architecture.

### ❌ Skill creator validator scans help text for hardcoded paths too
Not just code — help text examples with literal `$HOME/` or absolute agent paths will FAIL validation.
Use `$HOME`, `${VAR:-default}`, or descriptive placeholders like `<custom-path>` in all `--help` output.
The validator catches hardcoded paths in install-agent.sh help text examples.

### ❌ SKILL.md body must stay under 500 lines
Enterprise validator fails if SKILL.md exceeds 500 lines. Move detailed docs to `references/<topic>.md`.
We split provider-compatibility and free-first-strategy into separate reference files.
Keep SKILL.md as the structured index + key patterns, delegate detail to references/.

---

## Verified Reference Implementation
- `references/identity-constitution-example.yaml` — Full constitution example
- `references/habit-structure.yaml` — Habit YAML format reference
- `references/enforcer-config.yaml` — Enforcer daemon config reference
- `references/agent-workspace-layout.md` — Complete workspace structure
- `references/genesis-working.md` — Agent origin story (genesis.md from synthesis-1)
- `references/constitution-working.yaml` — Working constitution (from synthesis-1)
- `references/tool-enforcement.yaml` — Tool enforcement habit (working)
- `references/identity-enforcement.yaml` — Identity enforcement habit (working)
- `references/reflective-loop.yaml` — Reflective loop habit (working)
- `references/enforce.sh` — Workspace enforcement tool
- `references/secret.sh` — Encrypted secret management tool
- `references/memory-log.sh` — Daily memory logging tool
- `references/memory-promote.sh` — Daily to long-term memory promotion tool
- `references/TOOLS-GUIDE.md` — Tool usage documentation
- `references/templates/constitution-template.yaml` — Empty constitution template
- `references/templates/habit-template.yaml` — Empty habit definition template
- `references/provider-compatibility.md` — Provider compatibility matrix
- `references/free-first-strategy.md` — Free-first cost strategy
- `scripts/enforcer_daemon.py` — Enforcer daemon (RPC server, validation, auto-remediation)
- `scripts/agent_runtime.py` — Agent runtime (identity at t=0, habit gating, enforcer RPC)
- `scripts/memory_curator.py` — Memory curator (daily to weekly to long-term plus knowledge index)
- `scripts/start-agent.sh` — Startup orchestration: workspace validation, curation run, starts enforcer
- `scripts/install-agent.sh` — Full agent creation plus enforcer setup
- `scripts/verify-identity.sh` — Post-setup identity verification

## Provider Compatibility

| Provider | Compatibility | Notes |
|----------|---------------|-------|
| Claude (Anthropic) | Full | MCP servers, tool use |
| OpenAI / ChatGPT | Full | Function calling, Actions |
| Mistral / Le Chat | Full | Tool calling, script execution |
| Gemini (Google) | Full | Extensions, Vertex AI |
| Hermes (Nous) | Full | Tool-use fine-tuned |
| GitHub Copilot | Partial | Code generation; use external runner for scripts |
| Any LLM + tools | Full | Scripts are plain Python, provider-independent |

## Free-First Strategy

| Tier | Cost | Stack |
|------|------|-------|
| **Tier 0** | $0/mo | Python 3.8+ (all scripts use stdlib only) |
| **Tier 1** | $0-5/mo | + CI/CD for automated validation |
| **Tier 2** | $5-20/mo | + Hosted skill registry for team distribution |

## Enforced Output Statistics

Every script produces structured JSON on completion:
```json
{
  "operation": "script_name",
  "timestamp": "ISO8601",
  "status": "success | failed",
  "skill_name": "agent-identity-architecture",
  "details": {},
  "cost": {"tier": 0, "amount_usd": 0.0, "service": "local"}
}
```

## Error Handling

| Error | Detection | Recovery |
|-------|-----------|----------|
| Missing constitution | File not found at t=0 | Auto-create from template, warn |
| Missing habit files | Habit directory empty | Install defaults, log warning |
| Enforcer socket missing | Connection refused | Retry with backoff, alert |
| Workspace violation | Validation fails | Auto-remediate, require reflection |
| Identity hash mismatch | RPC validation | Deny tool execution, log audit |

## Enhancement Hooks

| Related Skill | Integration Point |
|---------------|-------------------|
| enterprise-blueprint-validation | Blueprint phases enforce identity layer |
| agent-workspace-enforcement | Workspace validation uses identity habits |
| loop-enforcer | Task completion gated by identity reflection |
| soul-generator | SOUL.md initialized from constitution |
| agent-memory | Memory pipeline curates identity-aligned patterns |
| autonomous-crew-integration | Crew agents inherit identity as Layer 1; phase gates via habits |

## Scripts & References

**Scripts:** `enforcer_daemon.py`, `agent_runtime.py`, `memory_curator.py`, `start-agent.sh`, `install-agent.sh`, `verify-identity.sh`, `__init__.py` — all in `scripts/`. See SKILL.md frontmatter for entry points.

**References:** `identity-constitution-example.yaml`, `habit-structure.yaml`, `enforcer-config.yaml`, `agent-workspace-layout.md`, `workspace-layout.md`, `genesis-working.md`, `constitution-working.yaml`, `tool-enforcement.yaml`, `identity-enforcement.yaml`, `reflective-loop.yaml`, `enforce.sh`, `secret.sh`, `memory-log.sh`, `memory-promote.sh`, `TOOLS-GUIDE.md`, `enterprise-validation-patterns.md`, `templates/constitution-template.yaml`, `templates/habit-template.yaml` — all in `references/`.

---

**This is the first architectural layer. Everything else — tools, reasoning, planning, memory, skills — sits on top of it.**
