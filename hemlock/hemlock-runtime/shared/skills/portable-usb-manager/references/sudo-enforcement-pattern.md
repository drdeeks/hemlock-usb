# Sudo Enforcement Pattern

This reference documents the sudo enforcement and caching pattern used in USB setup scripts.

## Overview

USB setup scripts must run with root privileges for operations like:
- Ventoy installation (writes to block device)
- Persistence creation (loop devices, filesystems)
- Network configuration (iptables, pfctl)
- System service installation (systemd/LaunchAgent)
- Docker operations

## Core Pattern

### 1. Sudo Enforcement (At Top of Script)

```bash
#!/usr/bin/env bash
set -euo pipefail

# Sudo enforcement - MUST be first
if [[ $EUID -ne 0 ]]; then
    echo -e "\033[0;31m✗\033[0m This script must be run with sudo/root privileges."
    echo -e "\033[0;33mℹ\033[0m Re-run with: sudo $0 $*"
    echo ""
    echo "This is required because the script performs operations that need root:"
    echo "  • Ventoy installation (writes to block device)"
    echo "  • Persistence creation (loop devices, filesystems)"
    echo "  • Network configuration (iptables, pfctl)"
    echo "  • System service installation (systemd/LaunchAgent)"
    echo "  • Docker operations"
    exit 1
fi
```

### 2. Sudo Caching with Auto-Cleanup

```bash
SUDO_CACHE_FILE="/tmp/usb-sudo-cache-$$"
SUDO_CACHED=false

cache_sudo_password() {
    if [[ "$SUDO_CACHED" == "true" ]]; then
        return 0
    fi
    
    if [[ -f "$SUDO_CACHE_FILE" ]]; then
        export SUDO_ASKPASS="$SUDO_CACHE_FILE"
        SUDO_CACHED=true
        return 0
    fi
    
    print_info "Caching sudo password for session (auto-deleted after setup validation)..."
    echo ""
    read -s -p "Enter sudo password: " sudo_pass
    echo ""
    
    if [[ -z "$sudo_pass" ]]; then
        print_error "No password entered"
        return 1
    fi
    
    # Verify password works
    if ! echo "$sudo_pass" | sudo -S -v 2>/dev/null; then
        print_error "Invalid sudo password"
        return 1
    fi
    
    # Create askpass script
    cat > "$SUDO_CACHE_FILE" << ASKPASS_EOF
#!/usr/bin/env bash
echo "$sudo_pass"
ASKPASS_EOF
    chmod 700 "$SUDO_CACHE_FILE"
    export SUDO_ASKPASS="$SUDO_CACHE_FILE"
    SUDO_CACHED=true
    print_success "Sudo cached for session"
    return 0
}

clear_sudo_cache() {
    if [[ -f "$SUDO_CACHE_FILE" ]]; then
        shred -u "$SUDO_CACHE_FILE" 2>/dev/null || rm -f "$SUDO_CACHE_FILE"
        print_info "Sudo cache cleared: $SUDO_CACHE_FILE"
    else
        print_info "Sudo cache already clear (no file found)"
    fi
    sudo -k 2>/dev/null || true
    unset SUDO_ASKPASS
    SUDO_CACHED=false
}

sudo_run() {
    if [[ "$SUDO_CACHED" == "true" && -f "$SUDO_CACHE_FILE" ]]; then
        sudo -A "$@"
    else
        sudo "$@"
    fi
}

# Traps for cleanup
trap 'clear_sudo_cache' EXIT TERM
trap 'print_warning "Interrupted — cleaning up..."; clear_sudo_cache; exit 130' INT

# Call at start
cache_sudo_password
```

### 3. Usage in Functions

```bash
# Use sudo_run instead of sudo
sudo_run systemctl enable hemlock-gateway.service
sudo_run systemctl start hemlock-gateway.service

# Or use sudo directly (will use cached password via SUDO_ASKPASS)
sudo systemctl enable hemlock-gateway.service
```

## Global Traps

```bash
# Trap to ensure cache cleanup on exit
trap 'clear_sudo_cache' EXIT TERM
trap 'print_warning "Interrupted — cleaning up..."; clear_sudo_cache; exit 130' INT
```

## DRY-RUN Support

```bash
DRY_RUN=false
for arg in "$@"; do
    if [[ "$arg" == "--dry-run" ]] || [[ "$arg" == "-n" ]]; then
        DRY_RUN=true
    fi
done

run_or_dry() {
    if [[ "$DRY_RUN" == "true" ]]; then
        print_info "[DRY RUN] Would execute: $*"
        return 0
    fi
    "$@"
}
```

Then use: `run_or_dry sudo_run systemctl enable service`

## Key Points

1. **EUID check at very top** - before any operations
2. **Cache at start** - single password prompt, cached for session
3. **Auto-cleanup** - trap on EXIT/TERM/INT ensures cache cleared
4. **shred for security** - overwrite password file before deletion
4. **SUDO_ASKPASS** - uses cached password without re-prompting
4. **Sudo -A** - uses askpass when cached

## Usage in initialize.sh

The pattern is used at the start of `config/initialize.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail

# Sudo enforcement
if [[ $EUID -ne 0 ]]; then
    echo "Must run with sudo"
    exit 1
fi

# Sudo caching setup...
# (see pattern above)

cache_sudo_password
```

## Security Notes

- Password cached in memory (tmpfs) - not written to disk persistently
- `shred` overwrites before deletion
- 700 permissions on cache file
- Auto-cleanup on exit, interrupt, or error
- No password stored in logs or history