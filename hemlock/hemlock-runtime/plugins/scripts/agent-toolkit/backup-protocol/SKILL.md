---
name: backup-protocol
description: Automated backup scheduling and point-in-time recovery for agents.
  Provides scheduled backups, backup verification, and restore capabilities.
version: 2.1.0
metadata:
  hermes:
    tags:
    - backup
    - recovery
    - automation
    - scheduling
    category: devops
    complexity: intermediate
author: openclaw
license: MIT
---
# Backup Protocol

## Overview

Automated backup system for agent data with:
- Scheduled backups (hourly, daily, weekly)
- Backup verification (checksum validation)
- Point-in-time recovery
- Incremental and full backup modes
- Automatic backup rotation (keep last N backups)

## Installation

This plugin is injected automatically when you select `backup-protocol` during agent setup.

## Usage

### Create Backup

```bash
bash plugins/backup-protocol/backup.sh --agent <agent_id> --type full
bash plugins/backup-protocol/backup.sh --agent <agent_id> --type incremental
```

### Restore from Backup

```bash
bash plugins/backup-protocol/backup.sh --agent <agent_id> --restore <backup_path>
```

### List Available Backups

```bash
bash plugins/backup-protocol/backup.sh --agent <agent_id> --list
```

### Schedule Automatic Backups

```bash
# Daily backups at 2 AM
bash plugins/backup-protocol/backup.sh --agent <agent_id> --schedule daily --time 02:00

# Weekly backups on Sunday at 3 AM
bash plugins/backup-protocol/backup.sh --agent <agent_id> --schedule weekly --day Sunday --time 03:00
```

## Backup Types

### Full Backup
Complete copy of all agent data including:
- tools/
- skills/
- memory/
- sessions/
- .secrets/ (encrypted)
- config files

### Incremental Backup
Only backs up changed files since last backup. Faster and uses less space.

## Backup Location

Backups are stored in: `~/.openclaw/backups/agents/<agent_id>/`

Each backup includes:
- Timestamped directory
- Checksum file for verification
- Backup manifest (JSON)

## Verification

All backups are automatically verified after creation:
```bash
# Manual verification
bash plugins/backup-protocol/backup.sh --agent <agent_id> --verify <backup_path>
```

## Retention Policy

Default retention:
- Keep last 10 full backups
- Keep last 5 incremental backups
- Auto-delete older backups

Configure in `backup-protocol/config.yaml`:
```yaml
retention:
  full_backups: 10
  incremental_backups: 5
  age_days: 30
```

## Recovery

### Full Recovery
```bash
bash plugins/backup-protocol/backup.sh --agent <agent_id> --restore <backup_path> --full
```

### Selective Recovery
```bash
# Restore only skills
bash plugins/backup-protocol/backup.sh --agent <agent_id> --restore <backup_path> --selective skills/

# Restore only tools
bash plugins/backup-protocol/backup.sh --agent <agent_id> --restore <backup_path> --selective tools/
```

## Safety Features

- Backup created before any restoration
- Checksum verification before restore
- Rollback capability if restore fails
- No data loss guarantee

## Integration

This protocol integrates with:
- Agent lifecycle management
- Plugin manager (automatic backup before plugin injection)
- Crew management (backup crew state before dormancy)

## Troubleshooting

### Backup Failed
Check logs: `~/.openclaw/logs/backup-<agent_id>.log`

### Restore Failed
Verify backup integrity: `bash plugins/backup-protocol/backup.sh --agent <agent_id> --verify <backup_path>`

### Disk Space Low
Clean old backups: `bash plugins/backup-protocol/backup.sh --agent <agent_id> --cleanup`
