# TOOLS-GUIDE.md
# synthesis-1 Tool Usage Documentation

## Overview
This guide documents all tools available to the synthesis-1 agent. Each tool is part of the tool-enforcement habit and must be present and executable.

---

## Required Tools (5 Total)

| Tool | Purpose | Location |
|------|---------|----------|
| `enforce.sh` | Workspace structure enforcement | `tools/enforce.sh` |
| `secret.sh` | Encrypted secret management | `tools/secret.sh` |
| `memory-log.sh` | Daily memory logging | `tools/memory-log.sh` |
| `memory-promote.sh` | Daily to long-term memory promotion | `tools/memory-promote.sh` |
| `TOOLS-GUIDE.md` | This documentation | `tools/TOOLS-GUIDE.md` |

---

## Tool Usage

### enforce.sh
**Purpose:** Validates and enforces workspace structure, tool presence, and file permissions.

```bash
# Run enforcement
bash tools/enforce.sh

# Environment variables
WORKSPACE=${WORKSPACE:-/path/to/workspace}  # Optional
AGENT_ID=synthesis-1          # Optional, defaults to synthesis-1
```

**Checks performed:**
- Required directories exist with correct permissions
- All 5 required tools present and executable
- File permissions correct (scripts 755, docs 644, secrets 600)

---

### secret.sh
**Purpose:** Encrypted secret management using AES-256-CBC.

```bash
# Store a secret
bash tools/secret.sh set GITHUB_TOKEN "ghp_xxxxxxxxxxxx"

# Retrieve a secret
bash tools/secret.sh get GITHUB_TOKEN

# List all secrets
bash tools/secret.sh list

# Delete a secret
bash tools/secret.sh delete GITHUB_TOKEN
```

**Security:**
- Secrets stored in `.secrets/` with 600 permissions
- Encrypted with AES-256-CBC + PBKDF2
- Encryption key stored in `.secrets/.encryption_key` (600 perms)
- Key auto-generated on first run

---

### memory-log.sh
**Purpose:** Append entries to daily memory files.

```bash
# Log a session note
bash tools/memory-log.sh SESSION "Completed user authentication module"

# Log a decision
bash tools/memory-log.sh DECISION "Switched to PostgreSQL for better JSON support" database architecture

# Log an error
bash tools/memory-log.sh ERROR "Connection timeout on API endpoint" api monitoring

# Log an insight
bash tools/memory-log.sh INSIGHT "Batch processing reduces API calls by 80%" performance optimization
```

**Entry Types:**
- `SESSION` - General session notes
- `DECISION` - Architectural/design decisions
- `NOTE` - General notes
- `ERROR` - Errors and issues encountered
- `INSIGHT` - Patterns and learnings discovered

**Links:** Optional wikilinks `[[entity]]` can be appended to associate with knowledge graph entities.

**Output:** Appended to:** `memory/daily/YYYY-MM-DD.md`

---

### memory-promote.sh
**Purpose:** Curate daily memories into long-term MEMORY.md

```bash
# Promote eligible entries
bash tools/memory-promote.sh

# Dry run (preview what would be promoted)
bash tools/memory-promote.sh --dry-run
```

**Promotion Criteria:**
- Daily file older than 1 day
- Not already promoted (checked by date marker)
- Contains LESSON, INSIGHT, DECISION, or PATTERN keywords

**Output:** Appends to `memory/MEMORY.md` with date headers

---

## File Permissions Reference

| Pattern | Permission | Example |
|---------|------------|---------|
| `*.sh` | 755 | `tools/enforce.sh` |
| `*.md` | 644 | `tools/TOOLS-GUIDE.md` |
| `.secrets/*` | 600 | `.secrets/GITHUB_TOKEN.enc` |
| `.secrets/` | 700 | Directory |
| Directories | 755 | `tools/`, `skills/`, `memory/` |

---

## Workspace Structure

```
${WORKSPACE}/
├── .agent/
│   ├── constitution.yaml      # Agent constitution (Layer 1)
│   ├── genesis.md             # Agent genesis testament
│   ├── habits/
│   │   ├── tool-enforcement.yaml
│   │   ├── identity-enforcement.yaml
│   │   └── reflective-loop.yaml
│   ├── logs/
│   ├── metrics/
│   ├── templates/
│   └── constitutions/
├── tools/
│   ├── enforce.sh
│   ├── secret.sh
│   ├── memory-log.sh
│   ├── memory-promote.sh
│   └── TOOLS-GUIDE.md
├── skills/
├── memory/
│   ├── daily/
│   └── MEMORY.md
├── .secrets/
└── .secrets/.encryption_key
```

---

## Enforcement Rules

The tool-enforcement habit runs automatically on:
1. **Before every tool invocation** - Validates workspace hygiene
2. **Agent initialization** - Full workspace validation
3. **Workspace changes** - Incremental validation

**On violation:**
1. Tool invocation blocked
2. Auto-fix attempted (missing dirs, perms, tools from templates)
3. Violation logged to `.agent/logs/habit-violations.jsonl`
4. Reflection required before proceeding

---

## Template Directory

Auto-fix templates located at: `.agent/templates/tool-enforcement/`

Templates include:
- `enforce.sh.template`
- `secret.sh.template`
- `memory-log.sh.template`
- `memory-promote.sh.template`
- `TOOLS-GUIDE.md.template`

---

## Quick Reference

```bash
# Full workspace enforcement
bash tools/enforce.sh

# Secret management
bash tools/secret.sh set KEY "value"
bash tools/secret.sh get KEY
bash tools/secret.sh list

# Memory logging
bash tools/memory-log.sh SESSION "content" [[links...]]
bash tools/memory-log.sh DECISION "content" [[links...]]
bash tools/memory-log.sh INSIGHT "content" [[links...]]

# Memory promotion
bash tools/memory-promote.sh
bash tools/memory-promote.sh --dry-run
```