---
name: hackathon-manager
description: 'Manages hackathon participation end to end: project organization, kanban-driven
  sequential execution, Qwen model-to-role mapping, DashScope provider patterns, submission
  readiness checks, and deadline tracking. Use when: joining a hackathon, organizing multiple
  project tracks, preparing submissions, mapping models to agent roles, or validating a
  project is production-grade before submitting.'
version: 0.1.1
license: MIT
metadata:
  category: productivity
  tags:
  - hackathon participation
  - hackathon submission workflow
  - project track organization
  - qwen model selection
  - dashscope provider pattern
  - submission readiness check
  - kanban sequential execution
---

# Hackathon Manager

> Manages hackathon participation, project organization, and submission workflows.

## Overview

This skill helps manage hackathon participation including project organization, submission workflows, and tracking multiple project ideas across different tracks.

## Core Functions

### Project Organization
- Create project directories for hackathon ideas
- Track project status and progress
- Manage multiple project concepts
- Link projects to specific bounties/tracks

### Submission Management
- Prepare submission metadata
- Track submission deadlines
- Manage team coordination
- Handle on-chain identity integration

### Resource Management
- Track bounties and prize pools
- Map projects to relevant tracks
- Monitor competition landscape
- Manage credentials and API keys

## Key Commands

```bash
# Create project directory
mkdir -p "$WORKSPACE/hackathon/[project-name]"

# Track project status
# (managed through memory files and project directories)

# Prepare submission
# (handled through submission workflows)
```

## Data Structure

```
hackathon/
├── [project-name]/
│   ├── README.md
│   ├── submission.md
│   ├── credentials.json
│   └── progress.md
├── bounties.json
└── projects.json
```

## Integration

- Uses OpenClaw workspace for file operations
- Integrates with hackathon APIs (Devfolio, etc.)
- Manages ERC-8004 identity through stored credentials
- Tracks multiple bounties and prize pools

## Security

- Credentials stored in `.synth-creds.json` with restricted permissions
- API keys never shared publicly
- Submission data managed through secure workflows
- On-chain identity handled through ERC-8004

## Usage

1. Install skill: `openclaw skill add /path/to/skill`
2. Create project directories: `mkdir -p hackathon/[project-name]`
3. Track progress through memory files
4. Prepare submissions using stored credentials
5. Monitor bounties and prize pools
6. Use on-chain identity for verification

## Scripts

| Script | Purpose |
|---|---|
| `scripts/project_tracker.py` | Manage `projects.json`/`bounties.json` — add/list/update projects, deadline countdown |
| `scripts/model_map.py` | Generate or query `hackathon-models.json` role-to-model mapping |
| `scripts/submission_check.py` | Validate a project directory for submission readiness (README, demo, mapping, no committed credentials) |

## References

- `references/qwen-cloud-hackathon-2026.md` — Qwen Cloud Global AI Hackathon 2026 details: 5 tracks, submission requirements, prize structure.
- `references/dashscope-provider-pattern.md` — Reusable DashScope provider code with mock/real swap pattern.
- `references/qwen-model-selection.md` — Model tier guide and role-to-model mapping for all 5 tracks.
- `references/kanban-sequential-execution.md` — one-project-at-a-time kanban doctrine + task template.
- `references/production-quality-standard.md` — production-not-demo standard, demo structure, shared infra patterns.

## Sequential Project Execution

One project at a time via kanban — queue, complete, promote. Full template + doctrine: [references/kanban-sequential-execution.md](references/kanban-sequential-execution.md)

## Shared Infrastructure Pattern

Build reusable components once, copy/adapt across projects:
- **DashScopeProvider**: OpenAI-compatible wrapper for DashScope API. Reuse across all Qwen projects.
- **MockDashScopeProvider**: Returns realistic responses for demo without valid API key. Swap path: `new DashScopeProvider()` instead of `new MockDashScopeProvider()`.
- **Provider injection**: Accept optional `provider` param in constructors (not just `providerConfig`). Enables mock injection for testing.
- **Model mapping JSON**: Single `hackathon-models.json` mapping roles to Qwen models. Reference from all projects.

Key pattern — constructor accepts both config and instance:
```js
constructor({ providerConfig = {}, provider = null }) {
  this.#provider = provider || new DashScopeProvider(providerConfig);
}
```

## Demo Structure

Each project demo should follow this pattern:
1. **Setup**: Create registries, register connectors, create provider (mock or real)
2. **Scenarios**: 3 distinct end-to-end scenarios showing the agent's capability
3. **Analysis**: Adversarial/quality analysis of each scenario's output
4. **Summary**: Stats (API calls, health score, models used)

Mock provider matching: order patterns from most specific to least specific. Check for domain-specific keywords BEFORE general ones to avoid false matches.

## Qwen Model-to-Role Mapping

Map models to agent roles based on task characteristics:
- **Heavy reasoning** (orchestrator, planning): `qwen3-235b-a22b-thinking-2507`
- **Code generation**: `qwen3-coder-plus` or `qwen3-coder-flash-2025-07-28`
- **Flagship reasoning** (analysis, complex decisions): `qwen3-max-preview`
- **Balanced general** (execution, approval): `qwen-plus-latest`
- **Adversarial analysis** (failure detection): `qwen3-235b-a22b`
- **Structured data** (graph operations): `qwen3-30b-a3b-instruct`
- **Vision-language** (image analysis, storyboarding): `qwen-vl-max-latest`
- **Fast coding** (UI, frontend): `qwen3-coder-flash-2025-07-28`

Store mapping in `hackathon-models.json` at workspace root.

## Best Practices

- Keep credentials secure and permissions restricted
- Track project progress systematically via kanban
- Map projects to relevant bounties early
- Prepare submissions well before deadlines
- Use on-chain identity for verification
- For Qwen Cloud Hackathon: Must use Qwen models on Qwen Cloud; public repo required; demo video 3-5 min; map each project to ≥1 track
- Build shared infra (providers, mocks) once, reuse across projects
- One project at a time — complete before starting next
- Each project needs: README, demo.js, working mock, model mapping

## Quality Standard & Delegation

Submissions are FULLY FUNCTIONAL products, never demo fluff; dispatch work to kanban agent profiles instead of hand-coding. Full doctrine: [references/production-quality-standard.md](references/production-quality-standard.md)

## DashScope API Endpoint

The correct DashScope API base URL for the Qwen Cloud Hackathon:
```
https://dashscope-intl.aliyuncs.com/compatible-mode/v1
```
NOT `https://dashscope.aliyuncs.com/compatible-mode/v1` (that's the Chinese endpoint, returns 401 for international keys).