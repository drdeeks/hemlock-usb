---
name: enterprise-blueprint
description: Parse, validate, and generate execution checklists from enterprise project blueprints. Provides 58+ validation rules, phase-gated workflow planning, and CI/CD integration. Use when creating project blueprints, validating blueprint structure, generating execution checklists, or planning multi-phase enterprise workflows. Triggers on 'blueprint', 'enterprise blueprint', 'project blueprint', 'blueprint validation', 'checklist generation', 'phase planning'.
version: 1.0.2
license: MIT
metadata:
  category: project-planning
  complexity: enterprise
  tags:
  - enterprise
  - blueprint
  - project planning
  - validation
  - checklist generation
  - workflow planning
  - phase gating
  - CI/CD integration
  - execution planning
---

# Enterprise Blueprint

Standalone enterprise blueprint workflow engine. Parses blueprint structure, validates against 58+ enterprise rules, generates execution checklists, and plans multi-phase workflows. Zero external dependencies — Python 3.8+ stdlib only.

## When to Use

- Creating or reviewing enterprise project blueprints
- Validating blueprint structure (7 chapters, 6+ phases, 15+ tasks)
- Generating phase-by-phase execution checklists
- Planning resource allocation and dependency chains
- CI/CD integration for automated validation gates

## Core Capabilities

### Blueprint Structure Parsing
- **7 Required Chapters**: Part I-VII following enterprise standards
- **Phase Extraction**: Detects and tracks 6-7 development phases
- **Task Breakdown**: Granular checklist items with validation gates
- **Rollback Management**: Phase and section rollback tag tracking

### Enterprise Validation
- **58+ Rules**: Comprehensive validation against enterprise standards
- **Quality Scoring**: 0-100 compliance score with detailed breakdown
- **Chapter Validation**: Ensures all 7 enterprise chapters present
- **Phase Compliance**: Minimum 6 phases, proper structure

### Checklist Generation
- **Phase-by-Phase Breakdown**: Detailed task breakdown per development phase
- **Validation Gates**: Phase completion verification points
- **Progress Tracking**: Real-time completion metrics and dashboard
- **Dependency Mapping**: Sequential phase and task dependencies

### Workflow Planning
- **Timeline Generation**: Phase-based execution schedules
- **Resource Allocation**: Hour estimates and validation requirements
- **Critical Path**: Dependency analysis for bottleneck identification
- **Status Reporting**: Completion tracking and progress dashboards

## Usage

### Validate a Blueprint
```bash
python3 scripts/enterprise_blueprint_checker.py ./project/blueprint.md --validate
```

### Generate Execution Checklist
```bash
python3 scripts/enterprise_blueprint_checker.py ./project/blueprint.md
# Output: ./project/checklist.md
```

### Generate Workflow Plan
```bash
python3 scripts/enterprise_blueprint_checker.py ./project/blueprint.md --workflow
```

### CI/CD Integration (JSON)
```bash
python3 scripts/enterprise_blueprint_checker.py ./project/blueprint.md --validate --json
```

### Initialize New Blueprint
```bash
python3 scripts/init_blueprint.py "My Project" --path ./output/project-name
```

## Output Formats

| Format | Use Case |
|--------|----------|
| Markdown | Human-readable checklists and reports |
| JSON | Machine-readable for CI/CD pipelines |
| Validation Reports | Detailed compliance scores and fix guidance |

## Error Handling

- Detailed error messages with fix guidance
- Graceful degradation for missing or corrupt files
- Automatic rollback and recovery workflows
- Enterprise compliance strict validation

## Key References

- `references/enterprise-rules.md` — 58+ validation rules
- `references/phase-templates.md` — Phase-specific templates
- `references/blueprint-structure.md` — Blueprint structure standards
- `references/checklist-patterns.md` — Checklist generation patterns
- `references/hackathon-blueprint-lessons.md` — Best practices and lessons learned

## File Index (validator-complete)

- `references/agent-roles.md` — Agent Roles Reference
- `references/blueprint-standard.md` — Blueprint Standard Reference (v2)
- `references/cli-wiring.md` — CLI Wiring Reference
- `references/critical-file-protection.md` — Critical File Protection
- `references/lessons/chain-enforcement-lessons.md` — Lessons Learned — Enterprise Blueprint Chain Enforcement
- `references/phase-gating.md` — Phase Gating Reference
- `references/safety-practices.md` — Safety Practices
- `references/testing-framework.md` — Testing Framework Reference
- `references/validation-rules.md` — Validation Rules Reference
- `scripts/assign_agents.py` — enterprise-blueprint — Assign agent roles and track implementation metrics
- `scripts/blueprint_validator.py` — Validator for blueprint chain steps.
- `scripts/enforce_blueprint.py` — enterprise-blueprint — Chain enforcement for blueprint lifecycle.
- `scripts/generate_checklist.py` — Generate execution checklists from enterprise blueprints.
- `scripts/test-runner.py` — Phase-Gated Test Orchestrator
- `scripts/validate_blueprint.py` — Blueprint Validation Script
