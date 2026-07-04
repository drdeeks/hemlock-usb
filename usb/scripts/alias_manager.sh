#!/usr/bin/env bash
# ============================================================================
# Alias Manager - USB Compute Automation System
# ============================================================================
#
# Manages aliases stored in ~/.bash_aliases_usb. Can be sourced or run
# directly. All aliases are stored in a format compatible with bash sourcing.
#
# Features:
# - Create/remove/edit aliases
# - Import from existing .bashrc/.bash_aliases
# - Export to portable format
# - List all aliases with descriptions
# - Search aliases by name or command
#
# Usage:
#   ./alias_manager.sh           # Interactive menu
#   ./alias_manager.sh --list    # List all aliases
#   ./alias_manager.sh --add "alias name='command'" "description"
#   ./alias_manager.sh --remove "alias-name"
#   ./alias_manager.sh --search "alias-name"
#   ./alias_manager.sh --export  # Export to stdout
#
# ============================================================================

set -euo pipefail

# ============================================================================
# CONFIGURATION
# ============================================================================

# CL-030: alias file location follows UCA_MODE.
#   usb  → <USB-mount>/usb-hemlock/etc/uca/bash_aliases.sh  (rides with the USB)
#   host → $XDG_CONFIG_HOME/usb-compute-automation/bash_aliases.sh
# Resolution happens AFTER lib/core.sh is sourced — see _resolve_alias_paths below.
ALIAS_FILE=""
ALIAS_BACKUP_DIR=""
ALIAS_EXPORT_FORMAT="table"  # table, csv, json

# Dry-run mode
DRY_RUN=false

# ============================================================================
# LIBRARY IMPORTS
# ============================================================================

# Source core utilities (colors, logging, dry-run, etc.)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="$(cd "$SCRIPT_DIR/../lib" 2>/dev/null && pwd)" || LIB_DIR="$SCRIPT_DIR/lib"
# shellcheck source=../lib/core.sh
source "$LIB_DIR/core.sh"

# shellcheck source=../lib/menu.sh
source "$LIB_DIR/menu.sh"

# shellcheck source=../lib/config.sh
source "$LIB_DIR/config.sh"

# CL-030: helpers for USB persistence detection must come from menu.sh's
# lib (so _uca_install_root can resolve UCA_MODE=usb). When alias_manager is
# invoked directly without menu.sh's env loaded, source the helper file once.
if ! command -v _uca_primary_persistence >/dev/null 2>&1; then
  if [[ -f "$LIB_DIR/usb.sh" ]]; then
    # shellcheck source=../lib/usb.sh
    source "$LIB_DIR/usb.sh"
  fi
fi

# CL-030: Resolve final alias file location ONCE, based on UCA_MODE.
_resolve_alias_paths() {
  local root
  if root=$(_uca_install_root 2>/dev/null) && [[ -n "$root" ]]; then
    ALIAS_FILE="${root}/bash_aliases.sh"
    ALIAS_BACKUP_DIR="${root}/alias_backups"
    return 0
  fi
  # _uca_install_root failed (e.g. UCA_MODE=usb but no USB) — fall back to
  # host config dir but warn loudly so the operator knows.
  print_warning "UCA_MODE=${UCA_MODE:-unset} could not resolve install root; falling back to host \$HOME"
  ALIAS_FILE="${HOME}/.bash_aliases_usb"
  ALIAS_BACKUP_DIR="${HOME}/.alias_backups"
}
_resolve_alias_paths

# Use DRY_RUN from core.sh (already exported)

# ============================================================================
# DRY-RUN SUPPORT (uses core.sh's run_or_dry)
# ============================================================================

run_or_dry() {
    if [[ "$DRY_RUN" == "true" ]]; then
        print_info "[DRY RUN] Would execute: $*"
        return 0
    fi
    "$@"
}

# Report the outcome of a mutation honestly: in dry-run mode nothing was
# actually written, so claim "Would <action>" rather than asserting success.
say_done() {
    if [[ "$DRY_RUN" == "true" ]]; then
        print_info "[DRY RUN] No write performed — would have: $*"
    else
        print_success "$*"
    fi
}

# ============================================================================
# INITIALIZATION
# ============================================================================

init_alias_file() {
    if [[ ! -f "$ALIAS_FILE" ]]; then
        mkdir -p "$(dirname "$ALIAS_FILE")"
        cat > "$ALIAS_FILE" << EOF
# ============================================================================
# USB Compute Automation - Custom Aliases
# ============================================================================
# This file is managed by alias_manager.sh
# Format: alias NAME='COMMAND' # DESCRIPTION
# Lines starting with # are comments
# Empty lines are ignored
#
# To load these aliases, add to your shell rc:
#   [[ -f "$ALIAS_FILE" ]] && source "$ALIAS_FILE"
#
# Or install via: bash_enhanced.sh (automatic)
# ============================================================================

EOF
        # CL-037: route init message to stderr so --export json / --list json
        # produce clean parseable stdout when called on a fresh install.
        print_success "Created alias file: $ALIAS_FILE" >&2
    fi
}

backup_aliases() {
    if [[ -f "$ALIAS_FILE" ]] && [[ -s "$ALIAS_FILE" ]]; then
        if [[ "$DRY_RUN" == "true" ]]; then
            print_info "[DRY RUN] Would back up $ALIAS_FILE before mutation"
            return 0
        fi
        mkdir -p "$ALIAS_BACKUP_DIR"
        local backup_file="$ALIAS_BACKUP_DIR/aliases-$(date +%Y%m%d-%H%M%S).sh"
        cp "$ALIAS_FILE" "$backup_file"
        print_info "Backup saved: $backup_file"
    fi
}

# ============================================================================
# ALIAS OPERATIONS
# ============================================================================

# List all aliases in a formatted table
list_aliases() {
    local format="${1:-table}"

    if [[ ! -f "$ALIAS_FILE" ]] || [[ ! -s "$ALIAS_FILE" ]]; then
        # CL-037: emit empty-but-valid output for json/csv so consumers can
        # parse the result instead of choking on "no aliases" text.
        case "$format" in
            json) echo "[]" ;;
            csv)  echo "name,command,description" ;;
            *)    print_warning "No aliases found. File: $ALIAS_FILE" >&2 ;;
        esac
        return 0
    fi
    
    # Extract aliases (skip comments and blank lines)
    local -a aliases=()
    local -a descriptions=()
    
    while IFS= read -r line; do
        # Skip comments and blank lines
        [[ "$line" =~ ^[[:space:]]*# ]] && continue
        [[ -z "$line" ]] && continue
        
        # Parse alias line: alias NAME='COMMAND' # DESCRIPTION
        if [[ "$line" =~ ^alias[[:space:]]+([a-zA-Z0-9_-]+)= ]]; then
            local alias_name="${BASH_REMATCH[1]}"
            local alias_cmd
            alias_cmd=$(echo "$line" | sed "s/^alias[[:space:]]*[a-zA-Z0-9_-]*='//" | sed "s/'[[:space:]]*(#.*$//" | sed "s/'$//")
            local description=""
            # Extract description after # character
            if echo "$line" | grep -q "#"; then
                description=$(echo "$line" | sed "s/.*#[[:space:]]*//")
            fi
            
            aliases+=("$alias_name")
            descriptions+=("$description|$alias_cmd")
        fi
    done < "$ALIAS_FILE"
    
    if [[ ${#aliases[@]} -eq 0 ]]; then
        case "$format" in
            json) echo "[]" ;;
            csv)  echo "name,command,description" ;;
            *)    print_warning "No aliases found in $ALIAS_FILE" >&2 ;;
        esac
        return 0
    fi
    
    case "$format" in
        table)
            printf "\n${BOLD}%-20s %-50s %s${NC}\n" "ALIAS" "COMMAND" "DESCRIPTION"
            echo "────────────────────────────────────────────────────────────────────────────────────────"
            for i in "${!aliases[@]}"; do
                local desc cmd
                desc=$(echo "${descriptions[$i]}" | cut -d'|' -f1)
                cmd=$(echo "${descriptions[$i]}" | cut -d'|' -f2)
                # Truncate long commands
                if [[ ${#cmd} -gt 48 ]]; then
                    cmd="${cmd:0:45}..."
                fi
                printf "${CYAN}%-20s${NC} %-50s ${YELLOW}%s${NC}\n" \
                    "${aliases[$i]}" "$cmd" "$desc"
            done
            echo ""
            print_info "Total: ${#aliases[@]} aliases"
            ;;
        csv)
            for i in "${!aliases[@]}"; do
                local desc cmd
                desc=$(echo "${descriptions[$i]}" | cut -d'|' -f1)
                cmd=$(echo "${descriptions[$i]}" | cut -d'|' -f2)
                echo "${aliases[$i]},\"$cmd\",\"$desc\""
            done
            ;;
        json)
            echo "["
            local last=$((${#aliases[@]} - 1))
            for i in "${!aliases[@]}"; do
                local desc cmd
                desc=$(echo "${descriptions[$i]}" | cut -d'|' -f1)
                cmd=$(echo "${descriptions[$i]}" | cut -d'|' -f2)
                printf '  {"name": "%s", "command": "%s", "description": "%s"}' \
                    "${aliases[$i]}" "$cmd" "$desc"
                [[ $i -ne $last ]] && echo ","
            done
            echo "]"
            ;;
    esac
}

# Add a new alias
add_alias() {
    local name="$1"
    local command="$2"
    local description="${3:-}"
    
    # Validate alias name
    if [[ ! "$name" =~ ^[a-zA-Z0-9_-]+$ ]]; then
        print_error "Invalid alias name: $name (use only letters, numbers, underscore, hyphen)"
        return 1
    fi
    
    # Check if alias already exists
    if grep -q "^alias ${name}=" "$ALIAS_FILE" 2>/dev/null; then
        print_warning "Alias '$name' already exists"
        # `|| true`: tolerate EOF/closed stdin under `set -e` (e.g. CLI --add of
        # an existing alias with no TTY) — an unread response means "don't
        # overwrite", not a crash.
        local response=""
        read -p "$(echo -e "${YELLOW}Overwrite? [y/N]: ${NC}")" response || true
        [[ "$response" =~ ^[Yy]$ ]] || return 0
        # Remove existing alias
        backup_aliases
        run_or_dry sed -i "/^alias ${name}=/d" "$ALIAS_FILE"
    else
        backup_aliases
    fi
    
    # Add the alias
    if [[ -n "$description" ]]; then
        run_or_dry bash -c "echo \"alias ${name}='${command}' # ${description}\" >> \"${ALIAS_FILE}\""
    else
        run_or_dry bash -c "echo \"alias ${name}='${command}'\" >> \"${ALIAS_FILE}\""
    fi
    
    say_done "Added alias: $name = '$command'"
    [[ -n "$description" ]] && print_info "Description: $description"
    print_info "Reload with: source $ALIAS_FILE"
}

# Remove an alias
remove_alias() {
    local name="$1"
    
    if [[ ! -f "$ALIAS_FILE" ]]; then
        print_error "Alias file not found: $ALIAS_FILE"
        return 1
    fi
    
    if ! grep -q "^alias ${name}=" "$ALIAS_FILE" 2>/dev/null; then
        print_error "Alias not found: $name"
        return 1
    fi
    
    backup_aliases
    
    # Remove the alias line
    run_or_dry sed -i "/^alias ${name}=/d" "$ALIAS_FILE"
    
    say_done "Removed alias: $name"
    print_info "Reload with: source $ALIAS_FILE"
}

# Edit an existing alias
edit_alias() {
    local name="$1"
    
    if [[ ! -f "$ALIAS_FILE" ]]; then
        print_error "Alias file not found: $ALIAS_FILE"
        return 1
    fi
    
    # Find existing alias
    local existing_line
    existing_line=$(grep "^alias ${name}=" "$ALIAS_FILE" 2>/dev/null | head -1)
    
    if [[ -z "$existing_line" ]]; then
        print_error "Alias not found: $name"
        return 1
    fi
    
    # Parse existing alias
    local existing_cmd
    existing_cmd=$(echo "$existing_line" | sed "s/^alias[[:space:]]*[a-zA-Z0-9_-]*='//" | sed "s/'[[:space:]]*(#.*$//" | sed "s/'$//")
    local existing_desc=""
    # Extract description after # character
    if echo "$existing_line" | grep -q "#"; then
        existing_desc=$(echo "$existing_line" | sed "s/.*#[[:space:]]*//")
    fi
    
    echo -e "\n${CYAN}Editing alias: $name${NC}"
    echo -e "Current command: ${BOLD}$existing_cmd${NC}"
    [[ -n "$existing_desc" ]] && echo -e "Current description: ${BOLD}$existing_desc${NC}"
    echo ""
    
    read -p "$(echo -e "${YELLOW}New command (Enter to keep current): ${NC}")" new_cmd
    new_cmd="${new_cmd:-$existing_cmd}"
    
    read -p "$(echo -e "${YELLOW}Description (Enter to keep current): ${NC}")" new_desc
    new_desc="${new_desc:-$existing_desc}"
    
    backup_aliases
    
    # Remove old alias
    run_or_dry sed -i "/^alias ${name}=/d" "$ALIAS_FILE"
    
    # Add updated alias
    if [[ -n "$new_desc" ]]; then
        run_or_dry bash -c "echo \"alias ${name}='${new_cmd}' # ${new_desc}\" >> \"${ALIAS_FILE}\""
    else
        run_or_dry bash -c "echo \"alias ${name}='${new_cmd}'\" >> \"${ALIAS_FILE}\""
    fi
    
    say_done "Updated alias: $name"
    print_info "Reload with: source $ALIAS_FILE"
}

# Search aliases by name or command
search_aliases() {
    local query="$1"
    
    if [[ ! -f "$ALIAS_FILE" ]]; then
        print_error "Alias file not found: $ALIAS_FILE"
        return 1
    fi
    
    print_info "Searching for: $query"
    echo ""
    
    local found=0
    while IFS= read -r line; do
        [[ "$line" =~ ^[[:space:]]*# ]] && continue
        [[ -z "$line" ]] && continue
        
        if echo "$line" | grep -qi "$query"; then
            echo -e "${CYAN}$line${NC}"
            ((found++))
        fi
    done < "$ALIAS_FILE"
    
    echo ""
    print_info "Found $found matching aliases"
}

# Import aliases from existing .bashrc or .bash_aliases
import_aliases() {
    # Expand tilde in source file path
    local source_file="${1:-$HOME/.bashrc}"
    source_file="${source_file/#~/$HOME}"
    
    if [[ ! -f "$source_file" ]]; then
        print_error "Source file not found: $source_file"
        return 1
    fi
    
    print_info "Importing aliases from: $source_file"
    
    local count=0
    while IFS= read -r line; do
        # Match alias lines
        if [[ "$line" =~ ^alias[[:space:]]+([a-zA-Z0-9_-]+)= ]]; then
            local alias_name="${BASH_REMATCH[1]}"
            local alias_cmd
            alias_cmd=$(echo "$line" | sed "s/^alias[[:space:]]*[a-zA-Z0-9_-]*='//" | sed "s/'$//")
            
            # Skip if already exists
            if ! grep -q "^alias ${alias_name}=" "$ALIAS_FILE" 2>/dev/null; then
                # Write directly to avoid quote escaping issues
                run_or_dry bash -c "cat >> \"${ALIAS_FILE}\" <<'EOF'
$line
EOF"
                print_success "Imported: $alias_name"
                ((count++))
            else
                print_info "Skipped (exists): $alias_name"
            fi
        fi
    done < "$source_file"
    
    echo ""
    print_info "Imported $count aliases from $source_file"
}

# Export aliases to stdout
export_aliases() {
    local format="${1:-table}"
    list_aliases "$format"
}

# ============================================================================
# INTERACTIVE MENU (using stack-based menu framework)
# ============================================================================

# Render function for alias manager menu
alias_menu_render() {
    echo -e "${BOLD}Alias file:${NC} $ALIAS_FILE"
    echo ""
    
    # Count aliases
    local count=0
    if [[ -f "$ALIAS_FILE" ]]; then
        count=$(grep -c "^alias " "$ALIAS_FILE" 2>/dev/null || echo "0")
    fi
    echo -e "${BOLD}Total aliases:${NC} $count"
    echo ""
    
    echo -e "${CYAN}1)${NC} List all aliases"
    echo -e "${CYAN}2)${NC} Add new alias"
    echo -e "${CYAN}3)${NC} Remove alias"
    echo -e "${CYAN}4)${NC} Edit alias"
    echo -e "${CYAN}5)${NC} Search aliases"
    echo -e "${CYAN}6)${NC} Import from .bashrc"
    echo -e "${CYAN}7)${NC} Export aliases"
    echo -e "${CYAN}8)${NC} Open alias file in editor"
    echo -e "${CYAN}9)${NC} View alias file"
    echo -e "${CYAN}0)${NC} Back to main menu"
    echo ""
}

# Handler function for alias manager menu
alias_menu_handler() {
    local choice="$1"
    
    case "$choice" in
        1)
            list_aliases
            echo "stay"
            ;;
        2)
            echo ""
            echo -ne "${YELLOW}Alias name: ${NC}"
            read -e -r name
            echo -ne "${YELLOW}Command: ${NC}"
            read -e -r cmd
            echo -ne "${YELLOW}Description (optional): ${NC}"
            read -e -r desc
            add_alias "$name" "$cmd" "$desc"
            echo "stay"
            ;;
        3)
            echo ""
            list_aliases 2>/dev/null || true
            echo ""
            echo -ne "${YELLOW}Alias name to remove: ${NC}"
            read -e -r name
            remove_alias "$name"
            echo "stay"
            ;;
        4)
            echo ""
            list_aliases 2>/dev/null || true
            echo ""
            echo -ne "${YELLOW}Alias name to edit: ${NC}"
            read -e -r name
            edit_alias "$name"
            echo "stay"
            ;;
        5)
            echo ""
            echo -ne "${YELLOW}Search query: ${NC}"
            read -e -r query
            search_aliases "$query"
            echo "stay"
            ;;
        6)
            echo ""
            echo -ne "${YELLOW}Source file [~/.bashrc]: ${NC}"
            read -e -r source_file
            import_aliases "${source_file:-$HOME/.bashrc}"
            echo "stay"
            ;;
        7)
            echo ""
            echo -e "${BOLD}Export format:${NC}"
            echo -e "  ${CYAN}1)${NC} Table (default)"
            echo -e "  ${CYAN}2)${NC} CSV"
            echo -e "  ${CYAN}3)${NC} JSON"
            echo -ne "${YELLOW}Select format [1-3]: ${NC}"
            read -e -r fmt
            case "$fmt" in
                2) export_aliases "csv" ;;
                3) export_aliases "json" ;;
                *) export_aliases "table" ;;
            esac
            echo "stay"
            ;;
        8)
            if command -v nano &>/dev/null; then
                nano "$ALIAS_FILE"
            elif command -v vim &>/dev/null; then
                vim "$ALIAS_FILE"
            else
                print_error "No editor found (nano, vim)"
                print_info "Manually edit: $ALIAS_FILE"
            fi
            echo "stay"
            ;;
        9)
            echo ""
            if [[ -f "$ALIAS_FILE" ]]; then
                cat "$ALIAS_FILE"
            else
                print_warning "Alias file not found: $ALIAS_FILE"
            fi
            echo "stay"
            ;;
        0)
            print_info "Returning to main menu..."
            echo "back"
            ;;
        *)
            print_error "Invalid option"
            echo "stay"
            ;;
    esac
}

interactive_menu() {
    init_alias_file
    menu_loop "Alias Manager" alias_menu_render alias_menu_handler
}

# ============================================================================
# COMMAND-LINE INTERFACE
# ============================================================================

# Parse command-line arguments
while [[ $# -gt 0 ]]; do
    case "$1" in
        --dry-run|-n)
            DRY_RUN=true
            shift
            ;;
        --list|-l)
            init_alias_file
            list_aliases "${2:-table}"
            exit 0
            ;;
        --add|-a)
            if [[ $# -lt 3 ]]; then
                echo "Usage: $0 [--dry-run] --add NAME COMMAND [DESCRIPTION]"
                exit 1
            fi
            init_alias_file
            add_alias "$2" "$3" "${4:-}"
            exit 0
            ;;
        --remove|-r)
            if [[ $# -lt 2 ]]; then
                echo "Usage: $0 [--dry-run] --remove NAME"
                exit 1
            fi
            init_alias_file
            remove_alias "$2"
            exit 0
            ;;
        --search|-s)
            if [[ $# -lt 2 ]]; then
                echo "Usage: $0 --search QUERY"
                exit 1
            fi
            init_alias_file
            search_aliases "$2"
            exit 0
            ;;
        --import|-i)
            init_alias_file
            import_aliases "${2:-$HOME/.bashrc}"
            exit 0
            ;;
        --export|-e)
            init_alias_file
            export_aliases "${2:-table}"
            exit 0
            ;;
        --help|-h)
            echo "Alias Manager - USB Compute Automation System"
            echo ""
            echo "Usage:"
            echo "  $0                        Interactive menu"
            echo "  $0 --dry-run              Dry-run mode (no changes made)"
            echo "  $0 --list [format]        List all aliases (table/csv/json)"
            echo "  $0 --add NAME CMD [DESC]  Add new alias"
            echo "  $0 --remove NAME          Remove alias"
            echo "  $0 --search QUERY         Search aliases"
            echo "  $0 --import [FILE]        Import from file (default: ~/.bashrc)"
            echo "  $0 --export [format]      Export aliases"
            echo ""
            echo "Examples:"
            echo "  $0 --dry-run --add ll 'ls -la' 'List files in long format'"
            echo "  $0 --add gs 'git status' 'Git status'"
            echo "  $0 --remove ll"
            echo "  $0 --search git"
            echo "  $0 --import ~/.bash_aliases"
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            echo "Use $0 --help for usage information"
            exit 1
            ;;
    esac
done

# If no arguments provided, run interactive menu
if [[ $# -eq 0 ]]; then
    interactive_menu
fi