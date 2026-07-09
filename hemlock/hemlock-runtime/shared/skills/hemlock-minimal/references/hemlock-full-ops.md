# Hemlock Full Ops — Complete Operational Toolkit

## Overview

The `scripts/hemlock-full/` directory contains 23 validated operational scripts for production agent/crew management. These scripts are sourced by `runtime.sh` and can also be called directly.

## Script Inventory

### Agent Lifecycle (10 scripts)

| Script | Purpose |
|--------|---------|
| `agent-create.sh` | Create agent volume + workspace |
| `agent-import.sh` | Import agent from backup |
| `agent-export.sh` | Export agent (minimal/standard/full) |
| `agent-delete.sh` | Destroy agent volume |
| `agent-attach.sh` | Register MCP bridge in gateway |
| `agent-detach.sh` | Unregister from gateway |
| `agent-run.sh` | Run agent |
| `agent-stop.sh` | Stop agent |
| `agent-restart.sh` | Restart agent |
| `agent-control.sh` | Agent control wrapper |

### Crew Management (6 scripts)

| Script | Purpose |
|--------|---------|
| `crew-create.sh` | Create crew volume + agent refs |
| `crew-import.sh` | Import crew + members |
| `crew-export.sh` | Export crew + members |
| `crew-dissolve.sh` | Destroy crew volume |
| `crew-attach.sh` | Attach all member agents |
| `crew-detach.sh` | Detach all crew agents |

### Import/Export (4 scripts)

| Script | Purpose |
|--------|---------|
| `agent-export.sh` | 3 modes: minimal/standard/full |
| `agent-import.sh` | Import from dir/tarball/volume |
| `crew-export.sh` | Export crew + members |
| `crew-import.sh` | Import crew + members |

### System Operations (6 scripts)

| Script | Purpose |
|--------|---------|
| `backup.sh` | Full system backup (gateway + agents + crews) |
| `backup-interactive.sh` | Menu-driven backup |
| `restore.sh` | Full system restore |
| `hemlock-snapshot.sh` | Snapshot system state |
| `validate.sh` | Runtime validation |
| `enforce.sh` | Enforce standards (fix/validate) |

## Export Modes (Detail)

### Agent Export Modes

| Mode | Includes |
|------|----------|
| **MINIMAL** | agent.json, SOUL.md, config.yaml, tools.md, AGENTS.md |
| **STANDARD** | MINIMAL + tools/, skills/, memory/ (recent 10), sessions/ (recent 5), .secrets/, configs |
| **FULL** | Everything (rsync with node_modules/.git/__pycache__/dist/build excluded) |

### Crew Export Modes

| Mode | Includes |
|------|----------|
| **MINIMAL** | crew.json only |
| **STANDARD** | crew.json + all member agents (standard mode) |
| **FULL** | crew.json + all member agents (full mode) |

## Usage Examples

```bash
# Agent export (3 modes)
./agent-export.sh --id my-agent --mode standard --dest /backups/my-agent
./agent-export.sh --id my-agent --volume my-agent-backup --mode full
./agent-export.sh --id my-agent --container my-agent-ctr --mode minimal --tarball

# Agent import
./agent-import.sh --source /backups/my-agent --id restored-agent
./agent-import.sh --source my-agent-backup.tar.gz --id restored-agent

# Crew operations
./crew-export.sh --name trading-crew --mode full
./crew-import.sh --source /backups/trading-crew --name trading-crew-v2

# Backup/Restore
./backup.sh                                    # Full system backup
./backup-interactive.sh                        # Interactive menu
./restore.sh hemlock-backup-20260612-143022.tar.gz
```

## Validation & Health

```bash
# Runtime validation
./validate.sh                    # Quick check
./runtime-validate.sh            # Full health check
./validate-all-skills.sh         # Validate all skills

# Doctor
python3 -m health.doctor_bridge --quick
python3 -m health.doctor_bridge --json
```

## Enforcement

```bash
./enforce.sh                     # Validate all
./enforce.sh --fix               # Auto-fix issues
./enforce.sh --all               # Enforce all agents/crews
./enforce.sh --fix --all         # Fix all
```

## Backup Strategy

| Frequency | Mode | Script |
|-----------|------|--------|
| Daily | STANDARD | `backup.sh` or `backup-interactive.sh` |
| Weekly | FULL | `backup.sh --full` |
| Pre-change | FULL | `agent-export.sh --mode full` |

## Restore Process

```bash
# Full system restore
./restore.sh hemlock-backup-20260612-143022.tar.gz

# Single agent
./agent-import.sh --source backup.tar.gz --id new-agent

# Single crew
./crew-import.sh --source backup.tar.gz --name new-crew
```

## Transport between Environments

```bash
# Export from source
./agent-export.sh --id my-agent --volume transport-vol --mode full
docker run --rm -v transport-vol:/src -v $(pwd)/exports:/dst alpine \
  tar -czf /dst/my-agent.tar.gz -C /src .

# Import on target
docker run --rm -v hemlock-agent-new:/dst -v $(pwd)/exports:/src alpine \
  tar -xzf /src/my-agent.tar.gz -C /dst
./entrypoint.sh agent-attach new-agent
```