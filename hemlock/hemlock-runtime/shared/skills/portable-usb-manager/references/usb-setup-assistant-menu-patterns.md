# USB Setup Assistant Menu Patterns

This reference documents the menu navigation patterns used in `usb-setup-assistant.sh`.

## Core Pattern: run_submenu() Helper

The key to proper sub-menu navigation is the `run_submenu()` helper that:
1. Clears screen and shows sub-menu
2. Executes selected action
3. **Returns to same sub-menu** after action (not main menu)
4. Exits only on explicit user choice

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
```

## Main Menu Usage

```bash
main() {
    while true; do
        show_main_menu
        read -p "Select [0-10]: " choice
        
        case "$choice" in
            1) run_submenu "Complete System Setup" setup_complete_system ;;
            2) run_submenu "USB Drive Management" setup_usb_drive ;;
            3) run_submenu "VM Boot & Headless Config" setup_vm_boot ;;
            4) run_submenu "Build Essentials" install_essentials ;;
            5) configure_network ;;
            6) view_system_status ;;
            7) backup_recovery_options ;;
            8) _system_cleanup ;;
            9) _alias_manager ;;
            10) _ssh_host_manager ;;
            0) exit ;;
            *) print_error "Invalid option" ;;
        esac
    done
}
```

## Sub-Menu Structure Pattern

Each sub-menu follows the same pattern:

```bash
setup_usb_drive() {
    print_header "USB Drive Preparation"
    echo "  1) Install/Upgrade Ventoy"
    echo "      Install fresh or upgrade existing Ventoy"
    echo "  2) Create Persistence"
    echo "      Create persistent storage (20GB default)"
    echo "  3) Add ISO to USB"
    echo "      Copy ISO file to Ventoy partition"
    echo "  4) Remove ISO"
    echo "      Delete ISO from USB"
    echo "  5) Rebuild Persistence"
    echo "      Wipe and recreate persistence"
    echo "  6) Upgrade Ventoy"
    echo "      Upgrade Ventoy version (preserves ISOs)"
    echo "  0) Back to Main Menu"
    
    while true; do
        read -p "Select [0-6]: " choice
        case "$choice" in
            1) install_ventoy ;;
            2) create_persistence ;;
            3) _add_iso_to_usb ;;
            4) _remove_iso_from_usb ;;
            5) _rebuild_persistence ;;
            6) _upgrade_ventoy ;;
            0) return 0 ;;
            *) print_error "Invalid option" ;;
        esac
        if ! confirm "Return to USB Drive Management menu?" "y"; then break; fi
    done
}
```

## SSH Host Manager (Option 10)

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
            4) _ssh_host_config ;;
            *) print_error "Invalid option" ;;
        esac
        if ! confirm "Return to SSH Host Manager menu?" "y"; then break; fi
    done
}
```

## Confirm Helper

```bash
confirm() {
    local prompt="$1"
    local default="${2:-n}"
    if [[ "$default" == "y" ]]; then
        prompt="$prompt [Y/n]: "
    else
        prompt="$prompt [y/N]: "
    fi
    read -p "$(echo -e "${YELLOW}${prompt}${NC}")" response
    response="${response:-$default}"
    [[ "$response" =~ ^[Yy] ]]
}
```

## Menu Option Definitions

| Option | Function | Description |
|--------|----------|-------------|
| 1 | `setup_complete_system` | Full guided setup (USB + VM + Hemlock + Essentials) |
| 2 | `setup_usb_drive` | Ventoy, persistence, ISOs, config |
| 3 | `setup_vm_boot` | VM auto-boot, headless, QEMU/UTM |
| 4 | `install_essentials` | Build tools INTO USB persistence |
| 5 | `configure_network` | SSH forwarding, Tailscale, WireGuard |
| 6 | `view_system_status` | Full diagnostics |
| 7 | `backup_recovery_options` | Backup/restore/clone |
| 8 | `_system_cleanup` | Docker, logs, temp cleanup |
| 9 | `_alias_manager` | alias_manager.sh integration |
| 10 | `_ssh_host_manager` | SSH host management |
| 0 | `exit` | Exit with confirmation |

## Key Principles

1. **Every action returns to its sub-menu** - never main menu
2. **Clear descriptions** - every option explains what it does
3. **Exit option (0)** - explicit back/exit at every level
4. **Confirm on exit** - "Return to X menu? [Y/n]"
5. **Consistent numbering** - 1-N for actions, 0 for back/exit
6. **Descriptive text** - explains what the option accomplishes

## Anti-Patterns to Avoid

| Anti-Pattern | Correct |
|--------------|---------|
| Exit to main menu after action | Return to sub-menu |
| No descriptions on options | Every option has description |
| No return confirmation | "Return to X menu? [Y/n]" |
| Mixed numbering (a,b,c / 1,2,3) | Consistent 1-N + 0 |
| Deep nesting without exit | Every level has 0/back |

## Flow Diagram

```
Main Menu
├── 1) Complete Setup → runs all phases
├── 2) USB Drive
│   ├── 1) Install Ventoy
│   ├── 2) Persistence
│   ├── 3) Add ISO
│   ├── 4) Remove ISO
│   ├── 5) Rebuild Persistence
│   ├── 6) Upgrade Ventoy
│   └── 0) Back → Main
├── 3) VM Boot
│   ├── 1) Headless Config
│   ├── 2) Auto-detect
│   ├── 3) Test SSH
│   ├── 4) Port Forward
│   └── 0) Back → Main
├── 4) Essentials → runs
├── 5) Network → runs
├── 6) Status → runs
├── 7) Backup → sub-menu
├── 8) Cleanup → sub-menu
├── 9) Aliases → sub-menu
├── 10) SSH Hosts → sub-menu
└── 0) Exit
```

## Implementation Notes

- All sub-menus use `run_submenu()` helper
- Each sub-menu is a function that loops until user exits
- `confirm` helper handles Y/n prompts
- Print functions (`print_header`, `print_success`, etc.) from `bash_enhanced.sh`
- Color codes: RED, GREEN, YELLOW, BLUE, CYAN, BOLD, NC