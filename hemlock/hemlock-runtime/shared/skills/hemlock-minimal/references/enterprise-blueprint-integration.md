# Enterprise Blueprint Integration

Hemlock Minimal includes the `enterprise-blueprint` skill for generating and maintaining enterprise-grade technical blueprints with synchronized checklists.

## Location

```
/home/ubuntu/hemlock-minimal/
├── blueprint/
│   ├── blueprint.md      # Master specification (Enterprise Grade validated)
│   ├── checklist.md      # Phase-synchronized enforcement checklist
│   └── project.json      # Project metadata
└── skills/
    └── enterprise-blueprint/  # Full blueprint toolkit (installed from drdeeks repo)
```

## Blueprint Toolkit Usage

```bash
cd /home/ubuntu/hemlock-minimal/skills/enterprise-blueprint

# Validate blueprint (100% passing = Enterprise Grade)
python3 scripts/validate_blueprint.py ../../blueprint/blueprint.md --json

# Sync checklist after blueprint changes
python3 scripts/generate_checklist.py ../../blueprint/blueprint.md --sync

# Assign agents to phases/modules
python3 scripts/assign_agents.py ../../blueprint --assign "architect:PHASE-1"
python3 scripts/assign_agents.py ../../blueprint --assign "mcp-engineer:MOD-002"
python3 scripts/assign_agents.py ../../blueprint --report
```

## Blueprint Status (Current)

- **Validation**: 48/48 checks PASSED (Enterprise Grade)
- **Phases**: 8 (Pre-Build → Launch & Live Ops)
- **Modules**: 14 (Gateway Core, MCP Bridge, Hermes Loop, Volume Mgr, Telegram, iMessage, Session Mgr, Agent Identity, Memory Hierarchy, Startup Injection, Skill Installer, Export/Import, Multiboot USB, Health/Doctor)
- **Feature Flags**: 14 (FEAT_*)
- **Change Log**: CL-001 (initial creation)

## Creating New Blueprints

```bash
python3 scripts/init_blueprint.py "New Project" \
  --path ./output/new-project \
  --phases "Pre-Build,Foundation,Core,Integration,Launch"
```

## Blueprint Workflow

```bash
# 1. Initialize new blueprint
python3 scripts/init_blueprint.py "Project Name" --path ./output/project-name \
  --phases "Pre-Build,Foundation,Auth,Core,Integration,Launch"

# 2. Populate blueprint top-down (Part I → Part VII)
# Replace all markers following sequence:
# Part I (vision, architecture) → Part II (module registry) 
# → Part III (specifications) → Part IV (data architecture) 
# → Part V (change control) → Part VI (phase checklists) → Part VII (quality)

# 3. Validate
python3 scripts/validate_blueprint.py ./output/project-name/blueprint.md --verbose

# 4. Sync checklist
python3 scripts/generate_checklist.py ./output/project-name/blueprint.md --sync
```

## Validator Checks (48 Total)

| Category | Checks |
|---|---|
| Document header | Version, Date, READ FIRST preamble |
| Required parts | PART I-VII all present |
| Rollback tags | PHASE tags, 6+ section tags |
| Module registry | MOD-NNN entries, FEAT_* flags |
| Specifications | Vision, Architecture, Tech Stack, Module ID, Feature Flag |
| Change log | CL-NNN entries, required fields, append-only |
| Data architecture | DB schema, API contracts, migration naming |
| Quality standards | p95 budgets, test coverage, circuit breaker |
| Placeholder hygiene | No [TODO], minimal unfilled placeholders |

## Rating Scale

- **Enterprise Grade**: 0 FAIL, ≤4 WARN
- **Production Ready**: 0 FAIL, ≤9 WARN  
- **Needs Hardening**: 0 FAIL, >9 WARN
- **Incomplete**: ≤3 FAIL
- **Not Enterprise Grade**: >3 FAIL

## Reference

- enterprise-blueprint skill: `/shared-skills/enterprise-blueprint/SKILL.md`
- Blueprint standard: `references/blueprint-standard.md`
- Phase templates: `references/phase-templates.md`
- Enterprise rules: `references/enterprise-rules.md`
- Checklist patterns: `references/checklist-patterns.md`
- Agent roles: `references/agent-roles.md`