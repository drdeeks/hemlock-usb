# USB Setup Assistant Fixes & Patterns

This reference documents the critical fixes and patterns applied to the USB Setup Assistant (`usb-setup-assistant.sh`) during Hemlock enterprise integration.

## Critical Fixes

### 1. NodeSource 404 Fix (Ubuntu 24.04)
**Problem**: `https://deb.nodesource.com/node_lts.x/nodistro` returns 404 on Ubuntu 24.04
**Fix**: Use Ubuntu codename (`noble` for 24.04) instead of `nodistro`

```bash
# Before (broken):
curl -fsSL "https://deb.nodesource.com/setup_lts.x" | sudo -E bash -

# After (fixed):
UBUNTU_CODENAME="$(lsb_release -cs 2>/dev/null || echo noble)"
curl -fsSL "https://deb.nodesource.com/setup_lts.x" | sudo -E bash -
# Or manually:
echo "deb https://deb.nodesource.com/node_lts.x/noble $(lsb_release -cs) main" | sudo tee /etc/apt/sources.list.d/nodesource.list
```

### 2. Sudo Enforcement & Caching Pattern
**Requirement**: USB setup scripts must run with root privileges
**Pattern**: Enforce at top of script, cache password for session

```bash
# Sudo enforcement at top
if [[ $EUID -ne 0 ]]; then
    echo "This script must be run with sudo/root privileges."
    echo "Re-run with: sudo $0 $*"
    exit 1
fi

# Sudo caching
SUDO_CACHE_FILE="/tmp/usb-sudo-cache-$$"
SUDO_CACHED=false

cache_sudo_password() {
    if [[ "$SUDO_CACHED" == "true" ]]; then return 0; fi
    if [[ -f "$SUDO_CACHE_FILE" ]]; then
        export SUDO_ASKPASS="$SUDO_CACHE_FILE"
        SUDO_CACHED=true
        return 0
    fi
    log "Caching sudo password for session..."
    read -s -p "Enter sudo password: " sudo_pass
    echo
    if [[ -z "$sudo_pass" ]]; then error "No password entered"; return 1; fi
    if ! echo "$sudo_pass" | sudo -S -v 2>/dev/null; then error "Invalid sudo password"; return 1; fi
    cat > "$SUDO_CACHE_FILE" << ASKPASS_EOF
#!/usr/bin/env bash
echo "$sudo_pass"
ASKPASS_EOF
    chmod 700 "$SUDO_CACHE_FILE"
    export SUDO_ASKPASS="$SUDO_CACHE_FILE"
    SUDO_CACHED=true
    success "Sudo cached for session"
}

clear_sudo_cache() {
    if [[ -f "$SUDO_CACHE_FILE" ]]; then
        shred -u "$SUDO_CACHE_FILE" 2>/dev/null || rm -f "$SUDO_CACHE_FILE"
    fi
    sudo -k 2>/dev/null || true
    unset SUDO_ASKPASS
    SUDO_CACHED=false
}

# Call at start
trap 'clear_sudo_cache' EXIT TERM
trap 'warn "Interrupted"; clear_sudo_cache; exit 130' INT
cache_sudo_password
```

### 3. Menu Navigation with Sub-menu Return
**Problem**: After sub-menu action, script exited to main menu instead of returning to sub-menu
**Solution**: `run_submenu()` helper pattern

```bash
run_submenu() {
    local submenu_name="$1"
    local menu_function="$2"
    local return_prompt="${3:-Return to ${submenu_name} menu?}"
    
    while true; do
        "$menu_function"
        echo ""
        if ! confirm "$return_prompt" "y"; then
            break
        fi
        echo ""
    done
}

# Usage in main:
case "$choice" in
    2)
        run_submenu "USB Drive Management" setup_usb_drive
        ;;
    3)
        run_submenu "VM Boot & Headless Config" setup_vm_boot
        ;;
    4)
        run_submenu "Build Essentials" install_essentials
        ;;
    # ... etc
esac

# Each sub-menu function follows same pattern:
setup_usb_drive() {
    print_header "USB Drive Preparation"
    echo "  1) Ventoy install/upgrade"
    echo "  2) Create persistence"
    # ...
    
    while true; do
        read -p "Select [1-6/q]: " choice
        case "$choice" in
            1) install_ventoy ;;
            2) create_persistence ;;
            # ...
            q) return 0 ;;
        esac
        if ! confirm "Return to USB Drive Management menu?" "y"; then break; fi
    done
}
```

### 4. SSH Host Manager (Option 10)
**New Feature**: Complete SSH host management as Option 10 in main menu

```bash
_ssh_host_manager() {
    run_submenu "SSH Host Manager" _ssh_host_manager_menu
}

_ssh_host_manager_menu() {
    print_header "SSH Host Manager"
    echo "  1) Add SSH Host"
    echo "      Add hostname, user, port, key path"
    echo "  2) List SSH Hosts"
    echo "      Show all configured SSH hosts"
    echo "  3) Remove SSH Host"
    echo "      Remove host by name"
    echo "  4) Test SSH Connection"
    echo "      Test connection to a configured host"
    echo "  5) Generate SSH Config"
    echo "      Generate ~/.ssh/config from host entries"
    echo "  0) Back to Main Menu"
    
    while true; do
        read -p "Select [0-5]: " choice
        case "$choice" in
            0) return 0 ;;
            1) _ssh_host_add ;;
            2) _ssh_host_list ;;
            3) _ssh_host_remove ;;
            4) _ssh_host_test ;;
            5) _ssh_host_config ;;
            *) print_error "Invalid option" ;;
        esac
        if ! confirm "Return to SSH Host Manager menu?" "y"; then break; fi
    done
}

# Sub-functions:
_ssh_host_add() { ... }
_ssh_host_list() { ... }
_ssh_host_remove() { ... }
_ssh_host_test() { ... }
_ssh_host_config() { ... }
```

### 5. Auto-enable Services Pattern
**Problem**: Scripts printed manual instructions instead of enabling services
**Solution**: Auto-enable and start services

```bash
# Before (manual):
echo "To enable: sudo systemctl enable usb-compute-vm.service"
echo "To start:  sudo systemctl start usb-compute-vm.service"

# After (auto):
if systemctl daemon-reload && systemctl enable usb-compute-vm.service && systemctl start usb-compute-vm.service; then
    print_success "Service created, enabled, and started!"
    systemctl status usb-compute-vm.service --no-pager
else
    print_error "Failed to enable/start service"
    return 1
fi
```

### 6. Lightweight GUI for USB
**Requirement**: Drag-drop file viewer for USB
**Solution**: LXQt + pcmanfm-qt + picom

```bash
apt -y install --no-install-recommends \
    xorg xinit lxqt-core pcmanfm-qt lxqt-panel lxqt-runner \
    qterminal pavucontrol-qt lximage-qt
apt -y install picom  # compositor

# Auto-start on boot (optional):
# systemctl enable --now display-manager
```

### 7. Master Deployment Script Pattern (DEPLOY.sh)
**Pattern**: Single script with 3 phases, dry-run, selective install

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

if [[ "$INSTALL_SYSTEM" == "true" ]]; then
    bash "$USB_AUTO_DIR/config/initialize.sh"
fi

if [[ "$INSTALL_USB" == "true" ]]; then
    bash "$USB_AUTO_DIR/usb-setup-assistant.sh"
fi

if [[ "$INSTALL_HEMLOCK" == "true" ]]; then
    # Copy skills, build Docker, start services
fi
```

### 8. Menu Options 0-10
**Complete menu structure with clear descriptions:**

```bash
show_main_menu() {
    print_header "Main Menu"
    echo "  1) Complete System Setup"
    echo "      USB >> VM >> Hemlock >> Essentials"
    echo "  2) Configure Ventoy USB Drive"
    echo "      Install Ventoy, persistence, ISOs"
    echo "  3) Setup VM Auto-Boot & Headless"
    echo "      Auto-boot headless with SSH"
    echo "  4) Install Build Essentials"
    echo "      docker, build tools, nodejs, python INTO USB persistence"
    echo "  5) Configure Network & SSH"
    echo "      Port forwarding, Tailscale, WireGuard"
    echo "  6) View System Status"
    echo "      macOS/Linux/Windows, USB, VM, Persistence"
    echo "  7) Backup & Recovery"
    echo "      Backup/restore persistence, clone USB"
    echo "  8) System Cleanup"
    echo "      Clean docker, logs, temp files"
    echo "  9) Manage Custom Aliases"
    echo "      Aliases stored on USB persistence"
    echo "  10) Manage SSH Hosts"
    echo "      Add/remove/list/test/connect SSH hosts"
    echo "  0) Exit"
}
```

### 9. Sudo Enforcement Pattern
**At top of every USB script:**

```bash
#!/usr/bin/env bash
set -euo pipefail

# Sudo enforcement - MUST be first
if [[ $EUID -ne 0 ]]; then
    echo -e "\033[0;31m✗\033[0m This script must be run with sudo/root privileges."
    echo -e "\033[0;33mℹ\033[0m Re-run with: sudo $0 $*"
    exit 1
fi

# Sudo caching (see pattern above)
cache_sudo_password
```

### 10. NodeSource Fix (Ubuntu codename)
**Auto-detect Ubuntu codename:**

```bash
UBUNTU_CODENAME="$(lsb_release -cs 2>/dev/null || echo noble)"
# noble for Ubuntu 24.04 LTS
# jammy for Ubuntu 22.04 LTS

curl -fsSL "https://deb.nodesource.com/setup_lts.x" | sudo -E bash -
# Or explicitly:
echo "deb https://deb.nodesource.com/node_lts.x/${UBUNTU_CODENAME} main" | sudo tee /etc/apt/sources.list.d/nodesource.list
```

## Files Modified

| File | Changes |
|------|---------|
| `usb-setup-assistant.sh` | All fixes above applied |
| `config/initialize.sh` | 27-phase enhanced bootstrap |
| `bash_enhanced.sh` | Enhanced with USB shortcuts, improved input handling |
| `DEPLOY.sh` | Master deployment script (3 phases) |
| `bash_enhanced.sh` (in scripts/) | Enhanced input handling, aliases |
| `hemlock-tui` | Wrapper for Hemlock TUI |

## Testing

All scripts pass syntax check:
```bash
bash -n usb-setup-assistant.sh
bash -n config/initialize.sh
bash -n DEPLOY.sh
```

## Deployment

```bash
# Full deployment:
sudo bash DEPLOY.sh

# Selective:
sudo bash DEPLOY.sh --no-system
sudo bash DEPLOY.sh --no-usb
sudo bash DEPLOY.sh --no-hemlock
sudo bash DEPLOY.sh --dry-run
```