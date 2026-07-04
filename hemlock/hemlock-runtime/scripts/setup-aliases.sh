#!/bin/bash
# =============================================================================
# setup-aliases.sh — Interactive alias setup wizard
#
# Walks users through creating convenient shell aliases for Hemlock commands
# Supports: bash, zsh, fish
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RUNTIME_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

# Shell config files
BASHRC="$HOME/.bashrc"
ZSHRC="$HOME/.zshrc"
FISHRC="$HOME/.config/fish/config.fish"

# =============================================================================
# Helper Functions
# =============================================================================

info() { echo -e "${BLUE}[INFO]${NC}  $*"; }
success() { echo -e "${GREEN}[✓]${NC}  $*"; }
warn() { echo -e "${YELLOW}[WARN]${NC}  $*"; }
error() { echo -e "${RED}[ERROR]${NC} $*" >&2; }

print_header() {
    echo ""
    echo -e "${BOLD}${CYAN}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BOLD}${CYAN}║        HEMLOCK ALIAS SETUP WIZARD                            ║${NC}"
    echo -e "${BOLD}${CYAN}╚══════════════════════════════════════════════════════════════╝${NC}"
    echo ""
}

print_section() {
    echo ""
    echo -e "${BOLD}${BLUE}─── $1 ${BLUE}────────────────────────────────────────────────────────${NC}"
    echo ""
}

# =============================================================================
# Alias Definitions
# =============================================================================

ALIASES_BASH_ZSH='
# Hemlock Runtime
alias hemlock="cd '"$RUNTIME_ROOT"' && ./runtime.sh"
alias hl="cd '"$RUNTIME_ROOT"' && ./runtime.sh"

# Health Checks
alias hl-health="docker exec hemlock_runtime python3 -m health.doctor_bridge --quick"
alias hl-doctor="docker exec hemlock_runtime python3 -m health.doctor_bridge"

# Agent Management
alias hl-agents="ls -la '"$RUNTIME_ROOT"'/agents/"
alias hl-create="'"$RUNTIME_ROOT"'/scripts/agent-create.sh"
alias hl-import="'"$RUNTIME_ROOT"'/scripts/agent-import.sh"

# Docker Operations
alias hl-up="cd '"$RUNTIME_ROOT"' && docker-compose -f docker-compose.runtime.yml up -d"
alias hl-down="cd '"$RUNTIME_ROOT"' && docker-compose -f docker-compose.runtime.yml down"
alias hl-logs="docker-compose -f '"$RUNTIME_ROOT"'/docker-compose.runtime.yml logs -f"
alias hl-ps="docker ps --filter name=hemlock"

# Quick Status
alias hl-status="docker ps --filter name=hemlock --format \"table {{.Names}}\\t{{.Status}}\""
'

ALIASES_FISH='
# Hemlock Runtime
function hemlock
    cd '"$RUNTIME_ROOT"'
    ./runtime.sh $argv
end

function hl
    cd '"$RUNTIME_ROOT"'
    ./runtime.sh $argv
end

# Health Checks
function hl-health
    docker exec hemlock_runtime python3 -m health.doctor_bridge --quick $argv
end

function hl-doctor
    docker exec hemlock_runtime python3 -m health.doctor_bridge $argv
end

# Agent Management
function hl-agents
    ls -la '"$RUNTIME_ROOT"'/agents/ $argv
end

# Docker Operations
function hl-up
    cd '"$RUNTIME_ROOT"'
    docker-compose -f docker-compose.runtime.yml up -d $argv
end

function hl-down
    cd '"$RUNTIME_ROOT"'
    docker-compose -f docker-compose.runtime.yml down $argv
end

function hl-logs
    docker-compose -f '"$RUNTIME_ROOT"'/docker-compose.runtime.yml logs -f $argv
end

function hl-status
    docker ps --filter name=hemlock --format "table {{.Names}}\\t{{.Status}}" $argv
end
'

# =============================================================================
# Detection Functions
# =============================================================================

detect_shell() {
    local shell_name=$(basename "$SHELL")
    echo "$shell_name"
}

find_shell_config() {
    local shell="$1"
    case "$shell" in
        bash)
            if [[ -f "$BASHRC" ]]; then
                echo "$BASHRC"
            else
                echo "$HOME/.bashrc"
            fi
            ;;
        zsh)
            if [[ -f "$ZSHRC" ]]; then
                echo "$ZSHRC"
            else
                echo "$HOME/.zshrc"
            fi
            ;;
        fish)
            if [[ -f "$FISHRC" ]]; then
                echo "$FISHRC"
            else
                mkdir -p "$HOME/.config/fish"
                echo "$FISHRC"
            fi
            ;;
        *)
            echo ""
            ;;
    esac
}

check_aliases_exist() {
    local config_file="$1"
    if grep -q "alias hemlock=" "$config_file" 2>/dev/null || \
       grep -q "function hemlock" "$config_file" 2>/dev/null; then
        return 0
    fi
    return 1
}

# =============================================================================
# Installation Functions
# =============================================================================

install_aliases_bash_zsh() {
    local config_file="$1"
    
    info "Adding aliases to $config_file..."
    
    # Add comment header
    cat >> "$config_file" << 'HEADER'

# ═══════════════════════════════════════════════════════════════
# Hemlock Aliases (added by setup-aliases.sh)
# ═══════════════════════════════════════════════════════════════
HEADER
    
    # Add aliases
    echo "$ALIASES_BASH_ZSH" >> "$config_file"
    
    success "Aliases added to $config_file"
    echo ""
    echo -e "${YELLOW}To activate, run:${NC}"
    echo "  source $config_file"
}

install_aliases_fish() {
    local config_file="$1"
    
    info "Adding functions to $config_file..."
    
    # Add comment header
    cat >> "$config_file" << 'HEADER'

# ═══════════════════════════════════════════════════════════════
# Hemlock Functions (added by setup-aliases.sh)
# ═══════════════════════════════════════════════════════════════
HEADER
    
    # Add functions
    echo "$ALIASES_FISH" >> "$config_file"
    
    success "Functions added to $config_file"
    echo ""
    echo -e "${YELLOW}To activate, run:${NC}"
    echo "  source $config_file"
}

# =============================================================================
# Interactive Wizard
# =============================================================================

show_alias_preview() {
    print_section "Alias Preview"
    
    echo -e "${CYAN}Available aliases:${NC}"
    echo ""
    echo "  ${BOLD}hemlock${NC} or ${BOLD}hl${NC}              - Launch interactive menu"
    echo "  ${BOLD}hl-health${NC}                 - Quick health check (5s)"
    echo "  ${BOLD}hl-doctor${NC}                 - Full health check (60s)"
    echo "  ${BOLD}hl-agents${NC}                 - List all agents"
    echo "  ${BOLD}hl-create${NC}                 - Create new agent"
    echo "  ${BOLD}hl-import${NC}                 - Import agent"
    echo "  ${BOLD}hl-up${NC}                     - Start Docker runtime"
    echo "  ${BOLD}hl-down${NC}                   - Stop Docker runtime"
    echo "  ${BOLD}hl-logs${NC}                   - View runtime logs"
    echo "  ${BOLD}hl-status${NC}                 - Check container status"
    echo ""
}

confirm_installation() {
    local shell="$1"
    local config_file="$2"
    
    print_section "Ready to Install"
    
    echo -e "Shell detected: ${GREEN}$shell${NC}"
    echo -e "Config file: ${GREEN}$config_file${NC}"
    echo ""
    
    if check_aliases_exist "$config_file"; then
        echo -e "${YELLOW}⚠ Aliases already exist in $config_file${NC}"
        echo ""
        read -rp "  Overwrite existing aliases? [y/N]: " confirm
        if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
            info "Installation cancelled"
            return 1
        fi
    fi
    
    read -rp "  Install aliases? [Y/n]: " confirm
    if [[ "$confirm" == "n" || "$confirm" == "N" ]]; then
        info "Installation cancelled"
        return 1
    fi
    
    return 0
}

# =============================================================================
# Main
# =============================================================================

main() {
    print_header
    
    # Detect shell
    local shell=$(detect_shell)
    local config_file=$(find_shell_config "$shell")
    
    if [[ -z "$config_file" ]]; then
        warn "Could not detect shell config file"
        echo ""
        echo "Please manually add aliases to your shell config:"
        echo "  - bash: ~/.bashrc"
        echo "  - zsh: ~/.zshrc"
        echo "  - fish: ~/.config/fish/config.fish"
        exit 1
    fi
    
    # Show preview
    show_alias_preview
    
    # Confirm installation
    if ! confirm_installation "$shell" "$config_file"; then
        exit 0
    fi
    
    # Install based on shell type
    case "$shell" in
        bash|zsh)
            install_aliases_bash_zsh "$config_file"
            ;;
        fish)
            install_aliases_fish "$config_file"
            ;;
        *)
            error "Unsupported shell: $shell"
            exit 1
            ;;
    esac
    
    print_section "Installation Complete"
    
    echo -e "${GREEN}✓ Aliases installed successfully!${NC}"
    echo ""
    echo -e "${CYAN}Quick start:${NC}"
    echo "  1. Run: source $config_file"
    echo "  2. Type: hemlock  (or hl)"
    echo "  3. Enjoy! 🎉"
    echo ""
    echo -e "${CYAN}Available commands:${NC}"
    echo "  hemlock / hl          - Interactive menu"
    echo "  hl-health             - Quick health check"
    echo "  hl-doctor             - Full diagnostics"
    echo "  hl-status             - Container status"
    echo ""
}

# Handle arguments
case "${1:-}" in
    --preview)
        show_alias_preview
        exit 0
        ;;
    --bash)
        install_aliases_bash_zsh "$BASHRC"
        exit 0
        ;;
    --zsh)
        install_aliases_bash_zsh "$ZSHRC"
        exit 0
        ;;
    --fish)
        install_aliases_fish "$FISHRC"
        exit 0
        ;;
    --help|-h)
        echo "Usage: $0 [OPTIONS]"
        echo ""
        echo "Interactive alias setup wizard for Hemlock"
        echo ""
        echo "Options:"
        echo "  --preview    Show alias preview"
        echo "  --bash       Install bash aliases (non-interactive)"
        echo "  --zsh        Install zsh aliases (non-interactive)"
        echo "  --fish       Install fish functions (non-interactive)"
        echo "  --help, -h   Show this help"
        echo ""
        echo "Without options, runs interactive wizard"
        exit 0
        ;;
esac

main
