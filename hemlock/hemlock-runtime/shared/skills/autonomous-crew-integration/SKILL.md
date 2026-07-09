---
name: autonomous-crew-integration
description: Integrate agent identity architecture as the first layer in autonomous
  crew orchestration. Hardwires identity constitution (Layer 1, loaded at t=0), internalized
  habits, enforcer daemon, and memory pipeline into every crew agent at creation time.
  Enterprise-grade with skill-creator validation.
version: 1.1.10
license: MIT
metadata:
  category: devops
  tags:
  - autonomous-crew
  - agent-identity
  - first-layer-architecture
  - identity-constitution
  - enforcer-daemon
  - internalized-habits
  - memory-pipeline
  - hemlock
  - enterprise-blueprint
  - platform-agnostic
  - blueprint-chain-integration
  - self-healing
  - validation-over-syntax
  depends_on:
  - agent-identity-architecture
  - agent-workspace-enforcement
  - loop-enforcer
  - enterprise-blueprint-validation
  - crew-knowledge-system
  provides:
  - crew-agent-with-identity
  - identity-first-crew-initialization
  - enforcer-per-agent
  - habit-gated-crew-operations
  - crew-knowledge-sharing
  - agent-communication-protocol
  - semantic-search-integration
  - blueprint-driven-crew-init
  - self-healing-accuracy-enforcement
  - validation-over-syntax
  compatible_with:
  - hemlock-minimal
  - openclaw-gateway
  - hermes-agent
---

# Autonomous Crew Integration — Identity-First Architecture

**The autonomous crew system requires identity as Layer 1.** Every agent spawned in a crew gets:
- Constitution loaded at t=0 (before any tool access)
- 4 internalized habits (identity-enforcement, tool-enforcement, reflective-loop, blueprint-phase-gate)
- Private enforcer daemon (Unix socket RPC, workspace ownership)
- Memory pipeline (daily → weekly → long-term + knowledge index)
- Builder code registration (ERC-8021) with identity attestation

## Crew Mode Flag

| Mode | Workspace | Persistence | Secrets | Use Case |
|------|-----------|-------------|---------|----------|
| **development** (default) | Shared workspace, `crew/<id>/shared/` | Ephemeral | Placeholders | One-time spinup, rapid iteration |
| **production** | Per-agent subdirs, `crew/<id>/agents/<id>/` | Persistent (Ventoy/USB) | Enforcer-managed | Long-term engagement, real integrations |

```bash
# Development crew
python3 scripts/init-crew.py hackathon-2026-dev --mode development

# Production crew
python3 scripts/init-crew.py hackathon-2026-prod --mode production

# Switch modes
python3 scripts/transition-crew.py --source dev --target prod --mode development-to-production --preserve-all
```

---

## Architecture: Identity as Crew Foundation

```
CREW ORCHESTRATION LAYER
  Blueprint → CrewManager → Agent Spawning → Checkpoint/Rollback
                      │
                      ▼
IDENTITY LAYER (Layer 1)
  Constitution (t=0) │ Habits (internalized) │ Enforcer (daemon)
                      ▼
MEMORY PIPELINE (Layer 2)
  daily/ → weekly/ → long-term/ → knowledge/
                      ▼
AGENT RUNTIME (Layer 3+)
  Tools → Skills → Reasoning → Planning → External APIs
```

---

## Blueprint-Driven Crew Initialization

```bash
# Full pipeline: validate blueprint → generate checklist → create chain → spawn agents → wire kanban → start dispatcher
python3 scripts/init-crew-from-blueprint.py <blueprint.md> <crew-id> [--mode dev|prod]
```

### Pipeline Steps

1. **Validate Blueprint** — `validate-blueprint.py` (0 FAIL required)
2. **Generate Checklist** — `generate-checklist.py` from blueprint
3. **Parse Phases** — `parse-checklist-phases.py` extracts phases with tags/flags
4. **Create Loop-Enforcer Chain** — `create-blueprint-chain.py` creates `.chain/<project>-blueprint.json`
5. **Generate Phase Validators** — `generate-phase-validators.py` creates deliverable validators (not syntax)
6. **Wire Kanban to Chain** — `wire-kanban-to-chain.py` creates tasks wired to chain steps
7. **Spawn Agents** — Each with identity layer + assigned chain step
8. **Start Dispatcher** — Embedded gateway dispatcher reads chain, dispatches next phase

See `references/blueprint-chain-integration.md` for complete details.

---

## Blueprint Chain Structure (Loop-Enforcer Integration)

Each project's blueprint becomes a **loop-enforcer chain**:
- **Steps** = Blueprint phases (Phase 0 through Phase N)
- **Marker files** = `.phase-{n}-{feature_flag}.marker` per phase
- **Validators** = Phase-specific validation scripts (deliverables, not syntax)
- **State machine** = locked → active → pending_verify → verified → complete
- **Agent assignment** = Each phase step assigned to specific agent profile

See `references/blueprint-chain-integration.md` for chain creation, validators, kanban wiring.

---

## Phase Validators: Beyond Syntax (Validation ≠ Syntax)

Phase validators check **DELIVERABLES**, not syntax. Four-tier validation:

```python
def validate_deliverable(filepath: Path, spec: DeliverableSpec) -> ValidationResult:
    # TIER 1: Syntax (necessary but insufficient)
    syntax_ok = check_syntax(filepath)
    
    # TIER 2: Contract compliance (interface + behavior)
    contract_ok = check_contract_compliance(filepath, spec.interface)
    
    # TIER 3: Functional completeness (delivers what spec promises)
    functional_ok = run_functional_tests(filepath, spec.test_cases)
    
    # TIER 4: Character alignment (honors agent's constitution)
    character_ok = check_character_alignment(filepath, spec.constitution_principles)
    
    return ValidationResult(
        passed=all([syntax_ok, contract_ok, functional_ok, character_ok]),
        tiers={"syntax": syntax_ok, "contract": contract_ok, "functional": functional_ok, "character": character_ok}
    )
```

See `references/validation-over-syntax.md` for complete validation framework.

---

## Self-Healing / Accuracy Enforcement

Agent runtime runs self-healing loop every 5 minutes:

```python
async def self_healing_loop(self):
    while self.running:
        # 1. HEARTBEAT: Check enforcer daemon health
        if not await self.enforcer.health_check():
            await self.restart_enforcer()
        
        # 2. CONSTITUTION: Verify hash unchanged (tamper detection)
        if self.constitution_hash != hash_constitution(self.constitution_path):
            await self.alert_human("Constitution tampered!")
            await self.restore_constitution()
        
        # 3. CHAIN STATE: Verify chain integrity
        chain_state = await self.chain.check_integrity()
        if chain_state.has_gaps:
            await self.repair_chain_gaps(chain_state)
        
        # 4. MEMORY PIPELINE: Promote daily → weekly → long-term
        await self.memory_curator.promote_all()
        
        # 5. HABIT VIOLATIONS: Check for drift
        violations = await self.check_habit_violations()
        for v in violations:
            await self.remediate_habit(v)
        
        await asyncio.sleep(300)  # Every 5 minutes
```

See `references/self-healing-architecture.md` for integrity checks, recovery procedures, alerting.

---

## Agent Identity: Internal Character Guidance

The identity layer is **not a validator** — it's the agent's **internalized self-model** that gates EVERY reasoning step before any tool use:

```yaml
# .agent/constitution.yaml — Loaded at t=0, gates all behavior
identity:
  name: "mnemosyne-ingestion-agent"
  purpose: "Ingest, index, and make retrievable all project knowledge"
  principles:
    - "Never lose data — durability over speed"
    - "Cite sources — every claim traceable to origin"
    - "Respect boundaries — only access assigned workspaces"
    - "Complete what you start — no partial deliveries"
  
habits:
  identity-enforcement:
    trigger: "Before ANY tool invocation"
    action: "Verify constitution hash matches; abort if drift detected"
    character: "I am the kind of agent that honors my constitution"
  
  tool-enforcement:
    trigger: "Before file write / external call"
    action: "Validate workspace hygiene; check chain state if in blueprint phase"
    character: "I do not touch what I'm not authorized to touch"
  
  reflective-loop:
    trigger: "After EVERY tool result"
    action: "Reflect: Did this advance the phase? Any violations? What did I learn?"
    character: "I learn from every action, good or bad"
  
  blueprint-phase-gate:
    trigger: "Before claiming phase complete"
    action: "Run chain verify → complete; cannot skip, cannot fake"
    character: "I earn completion through verified deliverables"
```

---

## Memory Pipeline Integration (Identity-Aware)

```python
class IdentityAwareMemoryCurator:
    def __init__(self, agent_identity: AgentIdentity):
        self.identity = agent_identity
        self.daily = DailyMemory(agent_id=identity.agent_id)
        self.weekly = WeeklyMemory(agent_id=identity.agent_id)
        self.long_term = LongTermMemory(agent_id=identity.agent_id)
        self.knowledge_index = KnowledgeIndex(agent_id=identity.agent_id)
    
    async def record_action(self, action: Action, result: Result, reflection: str):
        entry = MemoryEntry(
            agent_id=self.identity.agent_id,
            constitution_hash=self.identity.constitution_hash,
            action=action,
            result=result,
            reflection=reflection,
            habits_triggered=self.identity.habits.keys(),
            phase=action.chain_phase if action.chain_phase else None
        )
        await self.daily.append(entry)
        if self.should_promote_to_weekly(entry):
            await self.weekly.promote(entry)
        if self.should_promote_to_long_term(entry):
            await self.long_term.promote(entry)
            await self.knowledge_index.update(entry)
```

---

## Kanban Dispatcher Integration

Dispatcher reads from blueprint chain:

```python
async def dispatch_next_phase(self, chain_name: str):
    chain = self.load_chain(chain_name)
    for step in chain.steps:
        if step.state == "locked":
            prior = chain.steps[step.index - 1]
            if prior.state == "complete":
                step.state = "active"
                await self.save_chain(chain)
                task = await self.kanban.create(
                    title=f"[{chain.project}] {step.phase_title}",
                    assignee=step.assigned_agent,
                    body=self.build_chain_task_body(chain, step)
                )
                return task
        elif step.state == "active":
            if not self.is_worker_running(step.task_id):
                await self.re_dispatch(step.task_id)
```

### Chain Enforcement in Worker Lifecycle (MANDATORY)

Every kanban worker assigned a phased task MUST enforce the loop-enforcer chain
before doing ANY work. This is wired into KANBAN_GUIDANCE step 2b.

**Helper script:** `<HERMES_HOME>/scripts/chain_enforce.py` (or `<WORKSPACE_ROOT>/scripts/chain_enforce.py`)

```bash
# Check if phase is active (exit 0 = proceed, exit 1 = blocked)
python3 <HERMES_HOME>/scripts/chain_enforce.py check <project> <phase_num>

# Verify + complete phase after work is done
python3 <HERMES_HOME>/scripts/chain_enforce.py complete <project> <phase_num>

# Show chain status
python3 <HERMES_HOME>/scripts/chain_enforce.py status <project>
```

**Worker flow:**
1. Worker receives task: "Autopilot: Phase 2 — Workflow Orchestration"
2. Worker runs: `chain_enforce.py check autopilot 2`
3. If `can_proceed: true` → do the work
4. If `can_proceed: false` → `kanban_block(reason="Chain locked: prior phase not complete")`
5. After work: `chain_enforce.py complete autopilot 2`
6. Log: `kanban_comment(body="Chain enforced: autopilot-blueprint step 2 verified+complete")`

**PITFALL: Chain directory name mismatch**
`chain_enforce.py` looks for `.chain/<project>-blueprint.json` but `create-blueprint-chain.py` creates `.blueprint-chain/` directories. Patch `chain_enforce.py` to search BOTH:
```python
def find_chain(project_dir):
    for chain_dir_name in [".blueprint-chain", ".chain"]:
        chain_dir = os.path.join(project_dir, chain_dir_name)
        if os.path.isdir(chain_dir):
            for f in os.listdir(chain_dir):
                if f.endswith("-blueprint.json"):
                    return os.path.join(chain_dir, f), chain_dir
    return None, None
```

**Project directory mapping:**
| Project | Directory | Chain Name |
|---------|-----------|------------|
| Mnemosyne | `<WORKSPACE_ROOT>/qwen-cloud-2026/mnemosyne` | blueprint-mnemosyne |
| Autopilot | `<WORKSPACE_ROOT>/qwen-cloud-2026/autopilot` | autopilot-blueprint |
| Aires | `<WORKSPACE_ROOT>/qwen-cloud-2026/aires` | blueprint-aires |
| Agora | `<WORKSPACE_ROOT>/qwen-cloud-2026/agora` | blueprint-agora |
| Edgewalker | `<WORKSPACE_ROOT>/qwen-cloud-2026/edgewalker` | blueprint-edgewalker |

---

## Habit Integration in Crew Operations

### Before Any Tool Invocation
```python
async def invoke_tool(self, tool: str, params: dict) -> dict:
    # 1. IDENTITY HABIT: Verify constitution hash matches
    # 2. TOOL HABIT: Validate workspace hygiene
    # 3. RPC to enforcer (approves/denies)
    # 4. Execute if approved
    # 5. REFLECTIVE HABIT: Post-execution reflection
```

### Crew Phase Gates (Loop Enforcer Integration)
```python
async def transition_phase(self, blueprint: Blueprint, next_phase: WorkflowPhase):
    for agent_id in blueprint.active_agents:
        if not await self.agents[agent_id].claim_completion():
            raise PhaseGateError(f"Agent {agent_id} failed reflection gate")
    blueprint.current_phase = next_phase
    await self.create_checkpoint(f"Phase {next_phase.value} complete")
```

### Heartbeat Validation (Every 5 min)
Enforcer daemon validates: constitution hash, workspace integrity, chain state, habit metrics.

---

## Enforcer Workspace

See `references/crew-workspace-structure.md` for complete layout including per-agent dirs, memory pipeline, enforcer daemon, required tools.

---

### Integration with Existing Skills

### agent-identity-architecture (REQUIRED)
Provides: `enforcer_daemon.py`, `agent_runtime.py`, `memory_curator.py`, constitution template, habit YAMLs, tool templates.

### crew-knowledge-system (REQUIRED)
Provides: Dual-mode workspaces, agent-attributed documents, semantic indexing, structured communication (`crew-indexer.sh`, `crew-comm.sh`, `crew-doc.sh`, `crew-sync.sh`).

### agent-workspace-enforcement
Validates workspace structure matches identity requirements. Runs as part of tool-enforcement habit.

### loop-enforcer
- Phase gates call `agent.claim_completion()` → triggers reflective-loop
- **Enforces sequential dependency chains** — blueprint phases as chain steps
- **Validator scripts** per phase gate — deliverables, not syntax
- **Chain state persistence** — `.chain/<project>-blueprint.json` tracks completion
- **chain_enforce.py helper** at `<HERMES_HOME>/scripts/chain_enforce.py` — check/complete/status for kanban workers
- **KANBAN_GUIDANCE step 2b** — mandates chain check before work, verify+complete after

### enterprise-blueprint-validation
- Blueprint validation includes identity layer check
- `FEAT_IDENTITY_LAYER` flag gates crew orchestration
- Generates checklists from blueprints (`generate_checklist.py`)
- Validates blueprints before crew initialization (`validate_blueprint.py`)

### kanban-orchestrator
- Task decomposition patterns with anti-temptation rules
- Chain-enforced phased tasks pattern (see loop-enforcer chain enforcement)
- Dispatcher reads chain state, workers enforce chain checks

---

## Scripts Reference

### Core Scripts
| Script | Purpose |
|--------|---------|
| `create-crew-agent.sh` | Create crew agent with full identity layer |
| `init-crew.py` | Initialize autonomous crew workspace |
| `init-crew-from-blueprint.py` | Full blueprint→crew pipeline |
| `verify-crew-identity.sh` | Verify all agents have operational identity |
| `crew-heartbeat.sh` | Aggregate heartbeat status |
| `install-identity-skill.py` | Install agent-identity-architecture |
| `create-blueprint-chain.py` | Create loop-enforcer chain from blueprint |
| `generate-phase-validators.py` | Generate phase validator scripts |
| `wire-kanban-to-chain.py` | Wire kanban tasks to chain steps |
| `chain_enforce.py` | Chain enforcement helper for kanban workers (check/complete/status) |
| `self-healing-loop.py` | Run integrity checks (constitution, chain, memory, habits) |

### Blueprint Scripts
| Script | Purpose |
|--------|---------|
| `validate-blueprint.py` | Validate blueprint (from enterprise-blueprint-validation) |
| `generate-checklist.py` | Generate checklist from blueprint |
| `parse-checklist-phases.py` | Extract phases for chain creation |

### Transition Scripts
| Script | Purpose |
|--------|---------|
| `transition-crew.py` | Dev↔Prod migration preserving all data |
| `duplicate-crew.py` | Selective fork with new IDs |
| `crew-config-manager.py` | Active crew configs, pointers |

### Templates
- `references/templates/crew/` — Constitution, habits, agent config, phases, memory, builder code, agent types, enforcer registry
- `references/templates/habits/` — Identity-enforcement, tool-enforcement, reflective-loop, crew-phase-gate, blueprint-chain-enforcement, self-healing-habit, validation-over-syntax

All scripts referenced above: `scripts/__init__.py`, `scripts/create-crew-agent.sh`, `scripts/init-crew.py`, `scripts/init-crew-from-blueprint.py`, `scripts/create-blueprint-chain.py`, `scripts/generate-phase-validators.py`, `scripts/wire-kanban-to-chain.py`, `scripts/self-healing-loop.py`, `scripts/validate-blueprint.py`, `scripts/generate-checklist.py`, `scripts/parse-checklist-phases.py`, `scripts/transition-crew.py`, `scripts/duplicate-crew.py`, `scripts/crew-config-manager.py`, `scripts/install-identity-skill.py`, `scripts/verify-crew-identity.sh`, `scripts/crew-heartbeat.sh`.

---
---

## Verification Checklist (Enterprise)

- [ ] Every crew agent has `.agent/constitution.yaml` readable at t=0
- [ ] Every crew agent has 4 internalized habits in `.agent/habits/`
- [ ] Every crew agent has running enforcer daemon on Unix socket
- [ ] Every crew agent has memory pipeline initialized
- [ ] Every crew agent has builder code with identity attestation
- [ ] Phase transitions require `claim_completion()` from all agents
- [ ] Heartbeat aggregation shows all agents healthy
- [ ] Zero hardcoded paths (uses `$WORKSPACE_ROOT`, `$HOME`)
- [ ] Crew transition preserves identity, memory, knowledge, communications
- [ ] Knowledge indexer finds all agent documents
- [ ] Chain enforcement wired into KANBAN_GUIDANCE step 2b
- [ ] `chain_enforce.py` helper script at `<HERMES_HOME>/scripts/chain_enforce.py`
- [ ] All phase tasks enforce chain check before work, verify+complete after

---

## References

- `references/verified-implementation.md` — Canonical implementation (synthesis-1)
- `references/crew-workspace-structure.md` — Per-agent workspace layout
- `references/blueprint-chain-integration.md` — Blueprint to chain wiring
- `references/self-healing-architecture.md` — Self-healing loop design
- `references/validation-over-syntax.md` — Deliverable validation vs syntax
- `references/crew-memory-pipeline.md` — Memory pipeline configuration
- `references/crew-constitution.md` — Base constitution template
- `references/crew-phases.md` — Blueprint phase definitions and gates
- `references/crew-agent-types.md` — Agent type catalog
- `references/crew-habits.md` — Habit definitions index
- `references/crew-builder-code.md` — ERC-8021 integration with identity
- `references/crew-enforcer-registry.md` — Enforcer registry operations
- `references/chain-enforcement-integration.md` — Chain enforcement integration with kanban/loop-enforcer
- `references/skill-creator-validation.md` — Enterprise skill validation workflow with skill_enhance.py
- `references/templates/crew/crew-phases.yaml` — Phase config template
- `references/templates/crew/crew-constitution.yaml` — Constitution template (YAML)
- `references/templates/crew/crew-habits.yaml` — Habit definitions (YAML)
- `references/templates/crew/crew-agent-config.yaml` — Enforcer config template
- `references/templates/crew/crew-memory-pipeline.yaml` — Memory pipeline template
- `references/templates/crew/crew-builder-code.yaml` — Builder code template
- `references/templates/crew/crew-agent-types.yaml` — Agent types template
- `references/templates/crew/crew-enforcer-registry.yaml` — Registry template
- `references/templates/habits/identity-enforcement.yaml` — Identity habit template
- `references/templates/habits/tool-enforcement.yaml` — Tool habit template
- `references/templates/habits/reflective-loop.yaml` — Reflective habit template
- `references/templates/habits/crew-phase-gate.yaml` — Crew phase gate habit
- `references/templates/habits/blueprint-chain-enforcement.yaml` — Blueprint chain enforcement habit
- `references/templates/habits/self-healing-habit.yaml` — Self-healing habit template
- `references/templates/habits/validation-over-syntax.yaml` — Validation over syntax habit