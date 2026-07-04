# Hermes Framework Disaster Recovery Procedures

## Overview

This document outlines disaster recovery procedures for the Hermes framework, including backup strategies, recovery steps, and business continuity planning.

## Backup Strategy

### Backup Types

| Type | Description | Frequency | Retention |
|------|-------------|-----------|-----------|
| Full | Complete backup of all data | Daily | 7 days |
| Incremental | Changes since last backup | Hourly | 24 hours |
| Snapshot | Point-in-time copy | On-demand | 30 days |

### Backup Sources

| Source | Path | Priority | Size (est.) |
|--------|------|----------|-------------|
| Sessions | `sessions/` | Critical | Variable |
| Memory | `memory/` | Critical | < 100MB |
| Skills | `skills/` | High | < 50MB |
| Config | `config.yaml` | Critical | < 1MB |
| Orchestration | `orchestration/` | High | < 10MB |
| Logs | `logs/` | Low | Variable |

## Recovery Procedures

### Scenario 1: Single File Recovery

**Use Case**: Accidental deletion or corruption of a single file.

**Steps**:
1. Identify the file and approximate time of last known good state
2. List available backups: `hermes backup list`
3. Find backup containing the file: `hermes backup inspect <backup_id>`
4. Extract single file: `hermes backup extract <backup_id> --file <path>`
5. Verify file integrity

**Estimated Time**: 5-10 minutes

### Scenario 2: Full System Recovery

**Use Case**: Complete system failure or data corruption.

**Steps**:
1. Stop all running agents: `hermes agent stop --all`
2. Identify last known good backup: `hermes backup list --status verified`
3. Verify backup integrity: `hermes backup verify <backup_id>`
4. Restore from backup: `hermes backup restore <backup_id>`
5. Restart services: `hermes start`
6. Verify system health: `hermes health-check`

**Estimated Time**: 15-30 minutes

### Scenario 3: Point-in-Time Recovery

**Use Case**: Recover to specific point before data corruption.

**Steps**:
1. Identify corruption timestamp from logs
2. List snapshots before corruption: `hermes backup list --type snapshot`
3. Select appropriate snapshot based on timestamp
4. Restore snapshot: `hermes backup restore <snapshot_id> --target /path/to/restore`
5. Manually merge recovered data if needed

**Estimated Time**: 20-40 minutes

### Scenario 4: Agent State Recovery

**Use Case**: Recover specific agent state after crash.

**Steps**:
1. Identify affected agent ID
2. Find backups containing agent sessions: `hermes backup search --agent <agent_id>`
3. Restore agent sessions directory
4. Restart agent: `hermes agent start <agent_id>`
5. Verify agent state

**Estimated Time**: 10-15 minutes

## Backup Verification

### Automated Verification

All backups are automatically verified after creation:
- SHA256 checksum calculation
- Manifest integrity check
- File count validation

### Manual Verification

```bash
# Verify specific backup
hermes backup verify <backup_id>

# Verify all recent backups
hermes backup verify --recent 5

# Test restore to temporary location
hermes backup restore <backup_id> --target /tmp/test-restore --dry-run
```

## Monitoring and Alerts

### Backup Health Checks

| Check | Frequency | Alert Threshold |
|-------|-----------|-----------------|
| Last backup age | Hourly | > 24 hours |
| Backup size anomaly | Daily | > 50% change |
| Verification failures | Real-time | Any failure |
| Storage capacity | Daily | > 80% full |

### Alert Configuration

```yaml
alerts:
  backup_age:
    threshold: 86400  # seconds
    channels: [email, slack]
  backup_size:
    threshold_percent: 50
    channels: [email]
  verification:
    threshold: 1  # any failure
    channels: [email, slack, pagerduty]
```

## Business Continuity

### RTO/RPO Targets

| Component | RTO | RPO |
|-----------|-----|-----|
| Agent Sessions | 30 min | 1 hour |
| Memory/Skills | 1 hour | 24 hours |
| Configuration | 15 min | 24 hours |
| Logs | 4 hours | 7 days |

### Failover Procedures

1. **Primary Site Failure**
   - Activate secondary site
   - Restore from latest backup
   - Redirect traffic to secondary
   - RTO: 1-2 hours

2. **Data Corruption**
   - Stop affected services
   - Identify corruption point
   - Restore from pre-corruption backup
   - RTO: 30-60 minutes

## Testing Schedule

| Test Type | Frequency | Duration | Owner |
|-----------|-----------|----------|-------|
| File recovery | Monthly | 30 min | On-call |
| Full restore | Quarterly | 2 hours | DevOps |
| DR drill | Annually | 1 day | All teams |

## Contact Information

### Emergency Contacts

| Role | Name | Contact |
|------|------|---------|
| On-call Engineer | Rotation | oncall@company.com |
| DevOps Lead | TBD | devops-lead@company.com |
| System Owner | TBD | system-owner@company.com |

### Escalation Path

1. On-call Engineer (0-15 min)
2. DevOps Lead (15-30 min)
3. System Owner (30+ min)

## Appendix

### Backup Commands Reference

```bash
# Create backup
hermes backup create [--type full|incremental|snapshot] [--sources <list>]

# List backups
hermes backup list [--type <type>] [--status <status>]

# Inspect backup
hermes backup inspect <backup_id>

# Verify backup
hermes backup verify <backup_id>

# Restore backup
hermes backup restore <backup_id> [--target <path>] [--verify]

# Delete backup
hermes backup delete <backup_id>

# Search backups
hermes backup search [--agent <id>] [--file <pattern>]
```

### Recovery Checklist

- [ ] Identify failure type and scope
- [ ] Stop affected services
- [ ] Identify appropriate backup
- [ ] Verify backup integrity
- [ ] Perform restoration
- [ ] Verify restored data
- [ ] Restart services
- [ ] Monitor for issues
- [ ] Document incident

---

*Last Updated: 2026-05-13*
*Document Version: 1.0*
