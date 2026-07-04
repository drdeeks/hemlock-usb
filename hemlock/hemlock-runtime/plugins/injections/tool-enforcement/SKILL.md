---
name: tool-enforcement
description: Enforces workspace structure and tool availability for agents.
  Ensures all required tools are present and properly configured.
version: 1.0.0
metadata:
  hermes:
    tags:
    - enforcement
    - tools
    - workspace
    - structure
    category: devops
    complexity: basic
author: openclaw
license: MIT
---
# Tool Enforcement

## Overview

Ensures agent workspace has all required tools and proper structure:
- Validates tools/ directory exists
- Checks required tools are present
- Enforces tool permissions
- Validates tool functionality

## Required Tools

Every agent must have:
- `enforce.sh` - Workspace structure enforcement
- `secret.sh` - Encrypted secret management
- `memory-log.sh` - Memory logging
- `memory-promote.sh` - Memory promotion
- `TOOLS-GUIDE.md` - Tool usage documentation

## Installation

This plugin is injected automatically during agent creation/import.

## Usage

### Validate Tools

```bash
bash plugins/tool-enforcement/validate.sh --agent <agent_id>
```

### Fix Missing Tools

```bash
bash plugins/tool-enforcement/validate.sh --agent <agent_id> --fix
```

### Check Permissions

```bash
bash plugins/tool-enforcement/validate.sh --agent <agent_id> --check-permissions
```

## Enforcement Rules

### Directory Structure
- tools/ must exist
- skills/ must exist
- memory/ must exist
- .secrets/ must exist (700 permissions)

### File Permissions
- Shell scripts (.sh): 755
- Documentation (.md): 644
- .secrets/ directory: 700
- Secret files: 600

### Required Files
All 5 required tools must be present and executable.

## Integration

Works with:
- Plugin manager (Tier 1 mandatory toolkit)
- Agent creation script
- Agent import script
- Workspace enforcement skill

## Troubleshooting

### Tools Missing
Run: `bash plugins/tool-enforcement/validate.sh --agent <agent_id> --fix`

### Permission Errors
Run: `bash plugins/tool-enforcement/validate.sh --agent <agent_id> --fix-permissions`
