#!/usr/bin/env bash
# =============================================================================
# Enhanced System Management — Bash Profile (Portable Template)
# Universal portable bash profile with environment detection and alias manager
# Source from ~/.bashrc: source /path/to/bash_enhanced.sh
# =============================================================================

# ─────────────────────────────────────────────────────────────────────────────
# COLORS & CONSTANTS
# ─────────────────────────────────────────────────────────────────────────────
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly CYAN='\033[0;36m'
readonly WHITE='\033[1;37m'
readonly DIM='\033[2m'
readonly BOLD='\033[1m'
readonly NC='\033[0m'

# ─────────────────────────────────────────────────────────────────────────────
# ENVIRONMENT DETECTION & PORTABLE STORAGE
# ─────────────────────────────────────────────────────────────────────────────
# Enable alias expansion in non-interactive shells
shopt -s expand_aliases

# Detect the best location for portable alias storage
# Priority: USB persistence > detected USB mount > home fallback
_detect_persistent_storage() {
    # 1. Check explicit USB persistence mount
    if [[ -d "/mnt/usb-persistence" && -w "/mnt/usb-persistence" ]]; then
        echo "/mnt/usb-persistence"
        return 0
    fi

    # 2. Check systemd mount units for USB persistence
    for mount in $(systemctl list-units --type=mount --no-legend 2>/dev/null | awk '$1 ~ /persistence/ {print $1}'); do
        local where=$(systemctl show "$mount" -p Where --value 2>/dev/null)
        [[ -d "$where" && -w "$where" ]] && { echo "$where"; return 0; }
    done

    # 3. Check common USB media mounts with marker file
    for media in /media/*/ /run/media/*/; do
        for m in "$media"*/; do
            [[ -d "$m" && -w "$m" && -f "$m/.usb-persistence-marker" ]] && { echo "$m"; return 0; }
        done
    done

    # 4. Check for explicit USB flag file
    if [[ -f "${HOME}/.usb-persistence-path" ]]; then
        local p=$(cat "${HOME}/.usb-persistence-path" 2>/dev/null)
        [[ -d "$p" && -w "$p" ]] && { echo "$p"; return 0; }
    fi

    return 1
}

# Initialize portable storage locations
USB_PERSISTENCE=$(_detect_persistent_storage)

# Set primary alias file location
if [[ -n "$USB_PERSISTENCE" ]]; then
    USB_ALIAS_FILE="${USB_PERSISTENCE}/.bash_aliases_usb"
    USB_ALIAS_BACKUP_DIR="${USB_PERSISTENCE}/.alias_backups"
    USB_ALIAS_MANAGER="${USB_PERSISTENCE}/alias_manager.sh"
    export USB_PERSISTENCE USB_ALIAS_FILE USB_ALIAS_BACKUP_DIR USB_ALIAS_MANAGER
    export IS_USB_PERSISTENT=1
    echo -e "  ${GREEN}[USB]${NC} Portable aliases enabled at: ${USB_PERSISTENCE}"
else
    USB_ALIAS_FILE="${HOME}/.bash_aliases_usb"
    USB_ALIAS_BACKUP_DIR="${HOME}/.alias_backups"
    USB_ALIAS_MANAGER="${BASH_SOURCE[0]%/*}/alias_manager.sh"
    export IS_USB_PERSISTENT=0
fi

# Load USB-specific aliases if file exists
if [[ -f "$USB_ALIAS_FILE" ]]; then
    source "$USB_ALIAS_FILE"
fi

# ─────────────────────────────────────────────────────────────────────────────
# ALIAS MANAGER INTEGRATION
# ─────────────────────────────────────────────────────────────────────────────
# Dynamic alias manager finder (searches multiple locations)
_find_alias_manager() {
    local candidates=(
        "${USB_ALIAS_MANAGER:-}"
        "${BASH_SOURCE[0]%/*}/alias_manager.sh"
        "/usr/local/bin/alias_manager.sh"
        "/opt/usb-compute/alias_manager.sh"
    )
    for c in "${candidates[@]}"; do
        [[ -f "$c" ]] && { echo "$c"; return 0; }
    done
    return 1
}

# Global candidates for error reporting
_am_candidates=(
    "${USB_ALIAS_MANAGER:-}"
    "${BASH_SOURCE[0]%/*}/alias_manager.sh"
    "/usr/local/bin/alias_manager.sh"
    "/opt/usb-compute/alias_manager.sh"
)

# Alias manager wrapper with universal path finding
am() {
    local am_path
    am_path=$(_find_alias_manager)
    if [[ -n "$am_path" ]]; then
        bash "$am_path" "$@"
    else
        echo "alias_manager.sh not found. Searched locations:"
        for c in "${_am_candidates[@]}"; do [[ -n "$c" ]] && echo "  $c"; done
        return 1
    fi
}

# Quick alias manager commands
alias aml='am --list'              # List all aliases
alias ama='am --add'               # Add alias: ama name "cmd" "desc"
alias amr='am --remove'            # Remove alias
alias ams='am --search'            # Search aliases
alias ami='am --import'            # Import from .bashrc
alias ame='am --export'            # Export aliases
alias ammenu='am'                  # Interactive menu
alias alias-location='echo "Alias file: $USB_ALIAS_FILE"'
alias alias-env='echo "USB_PERSISTENT=$IS_USB_PERSISTENT"; echo "Alias file: $USB_ALIAS_FILE"; echo "Manager: $(_find_alias_manager)"'
alias alias-init='mkdir -p "${HOME}/.usb-persistence-marker" && echo "$(pwd)" > "${HOME}/.usb-persistence-path" && echo "Marked $(pwd) as USB persistence root"'

# ─────────────────────────────────────────────────────────────────────────────
# HELP SYSTEM (extended for alias manager)
# ─────────────────────────────────────────────────────────────────────────────
_syshelp_alias_manager() {
    cat <<'EOF'

  Alias Manager (Universal Portable):
    am                    # Interactive menu
    aml / am --list       # List all aliases
    ama / am --add        # Add alias (ama name "cmd" "desc")
    amr / am --remove     # Remove alias
    ams / am --search     # Search aliases (ams query)
    ami / am --import     # Import from .bashrc
    ame / am --export     # Export aliases (table/csv/json)
    ammenu                # Interactive menu
    alias-location        # Show where aliases are stored
    alias-env             # Show environment detection status
EOF
}

# ... rest of bash profile (sysinfo, sysresources, checkenv, etc.) ...

# ─────────────────────────────────────────────────────────────────────────────
# PROMPT (with alias expansion support)
# ─────────────────────────────────────────────────────────────────────────────
_git_branch() {
    git branch 2>/dev/null | awk '/\*/{print " ("$2")"}'
}

_exit_code() {
    local code=$?
    [ $code -ne 0 ] && echo -e " ${RED}[${code}]${NC}"
}

PS1='\[\033[1m\]\[\033[0;34m\]\u\[\033[0m\]@\[\033[0;36m\]\h\[\033[0m\]:\[\033[0;32m\]\w\[\033[1;33m\]$(_git_branch)\[\033[0m\]$(_exit_code)\n\[\033[0;36m\]▶\[\033[0m\] '

# ─────────────────────────────────────────────────────────────────────────────
# HISTORY & COMPLETION
# ─────────────────────────────────────────────────────────────────────────────
HISTSIZE=10000
HISTFILESIZE=20000
HISTCONTROL=ignoreboth:erasedups
HISTTIMEFORMAT="%F %T  "
shopt -s histappend
PROMPT_COMMAND="history -a; $PROMPT_COMMAND"

[ -f /usr/share/bash-completion/bash_completion ] && source /usr/share/bash-completion/bash_completion 2>/dev/null || true
[ -f /etc/bash_completion ] && source /etc/bash_completion 2>/dev/null || true

# end of bash_enhanced.sh