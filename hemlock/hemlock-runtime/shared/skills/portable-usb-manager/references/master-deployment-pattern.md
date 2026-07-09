# Master Deployment Pattern (DEPLOY.sh)

This reference documents the master deployment script pattern used for unified Hemlock USB deployment.

## Overview

The `DEPLOY.sh` master deployment script provides a single entry point to deploy the complete Hemlock USB compute environment in three phases.

## Script Structure

```bash
#!/usr/bin/env bash
# DEPLOY.sh - Master deployment with 3 phases

INSTALL_SYSTEM=true
INSTALL_USB=true
INSTALL_HEMLOCK=true
DRY_RUN=false

for arg in "$@"; do
    case "$arg" in
        --no-system) INSTALL_SYSTEM=false ;;
        --no-usb) INSTALL_USB=false ;;
        --no-hemlock) INSTALL_HEMLOCK=false ;;
        --dry-run) DRY_RUN=true ;;
    esac
done
```

## Three Phases

### Phase 1: System Bootstrap
```bash
if [[ "$INSTALL_SYSTEM" == "true" ]]; then
    bash "$USB_AUTO_DIR/config/initialize.sh"
fi
```
- Runs the 27-phase enhanced bootstrap
- Installs all system dependencies
- Configures environment

### Phase 2: USB Compute Automation
```bash
if [[ "$INSTALL_USB" == "true" ]]; then
    bash "$USB_AUTO_DIR/usb-setup-assistant.sh"
fi
```
- Runs the interactive USB setup assistant
- Guides through Ventoy, persistence, VM, Hemlock, essentials

### Phase 3: Hemlock Runtime Deployment
```bash
if [[ "$INSTALL_HEMLOCK" == "true" ]]; then
    # Copy skills to hemlock runtime
    cp -r "$SKILLS_DIR"/* "$HEMLOCK_DIR/skills/"
    
    # Build Docker images
    docker compose -f docker-compose.runtime.yml build
    docker compose -f docker-compose.yml build
    
    # Start services
    docker compose -f docker-compose.runtime.yml up -d
    docker compose -f docker-compose.yml up -d
fi
```

## Selective Deployment Flags

| Flag | Effect |
|------|--------|
| `--no-system` | Skip system bootstrap (Phase 1) |
| `--no-usb` | Skip USB automation (Phase 2) |
| `--no-hemlock` | Skip Hemlock runtime (Phase 3) |
| `--dry-run` | Preview without executing |

## Deployment Commands

```bash
# Full deployment (all 3 phases)
sudo bash DEPLOY.sh

# Skip system bootstrap (already done)
sudo bash DEPLOY.sh --no-system

# Skip USB setup (manual)
sudo bash DEPLOY.sh --no-usb

# Skip Hemlock (manual Docker)
sudo bash DEPLOY.sh --no-hemlock

# Preview what would run
sudo bash DEPLOY.sh --dry-run

# Only Hemlock runtime on existing system
sudo bash DEPLOY.sh --no-system --no-usb
```

## Script Features

- **Colored output**: CYAN headers, GREEN success, YELLOW warnings, RED errors
- **Error handling**: Exits on failure with clear messages
- **Dry-run mode**: Preview without execution
- **Selective phases**: Skip any phase with flags
- **Progress tracking**: Clear phase headers and completion messages
- **Next steps**: Printed at completion with actionable commands

## Integration with HEMLOCK_DIR

```bash
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
USB_AUTO_DIR="$SCRIPT_DIR/usb-compute-automation"
HEMLOCK_DIR="$SCRIPT_DIR/hemlock-runtime"
SKILLS_DIR="$SCRIPT_DIR/hemlock-minimal/skills"
```

The script automatically resolves paths relative to its location.

## Post-Deployment Next Steps

After successful deployment:
1. Log out/in or `source ~/.profile && source ~/.cargo/env`
2. Run `tailscale up` to join tailnet
3. Configure USB: `sudo bash $USB_AUTO_DIR/usb-setup-assistant.sh`
4. Access Hemlock TUI: `bash $USB_AUTO_DIR/hemlock-tui`
5. Check Hemlock: `docker ps | grep hemlock`