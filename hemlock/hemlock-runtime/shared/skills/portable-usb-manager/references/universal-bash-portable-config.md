---
name: universal-bash-portable-config
category: system-administration
description: Universal portable bash configuration with environment detection and integrated alias manager
tags: [bash, portable, usb, environment-detection, alias-manager, persistence]
version: 1.0.0
---

# Universal Portable Bash Configuration

## Overview
A class-level skill for creating universally portable bash configurations that auto-detect environment (USB persistence, host, VM, local) and adapt storage locations accordingly. Includes integrated alias manager with portable storage.

## Trigger Conditions
- Creating portable bash profiles that work across USB, VM, host, local
- Need environment-aware configuration storage
- Integrating portable alias/tmux/ssh configurations
- Building USB-bootable development environments

## Core Principles
1. **Detect First, Configure Second** - Always detect environment before setting paths
2. **Fallback Chain** - USB persistence → detected USB → home directory
3. **Self-Documenting** - Every config shows its own location and environment
4. **Stateless Detection** - No permanent state needed; detects on each source

## Detection Priority (in order)
1. Explicit mount: `/mnt/usb-persistence` (writable)
2. Systemd mount units: units with "persistence" in name
3. USB media with marker: `.usb-persistence-marker` file
4. Home marker: `~/.usb-persistence-path` file
5. Fallback: `$HOME/.bash_aliases_usb`

## Key Components

### Environment Detection (`_detect_persistent_storage`)
```bash
# Checks in order:
# 1. /mnt/usb-persistence
# 2. systemd mounts with "persistence"
# 3. /media/*/, /run/media/*/ with .usb-persistence-marker
# 4. ~/.usb-persistence-path file
# 5. Returns empty (home fallback)
```

### Portable Storage Variables
```bash
USB_PERSISTENCE      # Detected path or empty
IS_USB_PERSISTENT    # 1 or 0
USB_ALIAS_FILE       # Primary alias file path
USB_ALIAS_BACKUP_DIR # Backup directory
USB_ALIAS_MANAGER    # alias_manager.sh location
```

### Dynamic Manager Finder
```bash
_find_alias_manager() {
    candidates=(
        "${USB_ALIAS_MANAGER:-}"
        "${BASH_SOURCE[0]%/*}/alias_manager.sh"
        "/usr/local/bin/alias_manager.sh"
        "/opt/usb-compute/alias_manager.sh"
    )
    # Returns first found
}
```

### Universal Wrapper
```bash
am() { local p=$(_find_alias_manager); [[ -n $p ]] && bash "$p" "$@" || error; }
```

## Alias Commands
| Alias | Command | Description |
|-------|---------|-------------|
| `am` / `ammenu` | Interactive menu |
| `aml` | `am --list` |
| `ama name "cmd" "desc"` | Add alias with description |
| `amr name` | Remove alias |
| `ams query` | Search aliases |
| `ami [file]` | Import from `.bashrc` |
| `ame [fmt]` | Export (table/csv/json) |
| `alias-location` | Show alias file path |
| `alias-env` | Show detection status |
| `alias-init` | Mark current dir as USB root |

## Auto-Backup
Every alias change creates timestamped backup in `.alias_backups/`
Format: `aliases-YYYYMMDD-HHMMSS.sh`

## Usage
```bash
# Source in ~/.bashrc or directly
source /path/to/bash_enhanced.sh

# Now available everywhere
ama gs "git status" "Git shortcut"
aml
ams git
amr gs
```

## Testing Checklist
- [ ] Syntax: `bash -n bash_enhanced.sh`
- [ ] Source: `source bash_enhanced.sh` (no errors)
- [ ] Detection: `alias-env` shows correct environment
- [ ] CRUD: `ama test "echo hi" "test" && aml && amr test`
- [ ] Backup: `.alias_backups/` gets timestamped file
- [ ] Import: `ami ~/.bashrc` imports existing aliases
- [ ] Export: `ame json` outputs valid JSON

## Pitfalls
1. **Alias expansion in non-interactive shells** - Must `shopt -s expand_aliases` before defining aliases
2. **Candidates array scope** - Use global `_am_candidates` for error messages, local in finder
3. **USB_ALIAS_MANAGER unset** - Use `${VAR:-}` expansion to avoid unbound variable errors
4. **Parsing order** - Aliases defined after `shopt -s expand_aliases` work; before don't
5. **Marker file** - Create `.usb-persistence-marker` on USB root for reliable detection

## Related Skills
- `drdeeks/unified-usb-skill` - USB orchestration
- `drdeeks/skill-installer` - Skill packaging
- `drdeeks/enterprise-blueprint` - Blueprint validation