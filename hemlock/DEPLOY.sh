#!/usr/bin/env bash
# =============================================================================
# Hemlock USB Compute Automation - Master Deployment Script
# Single script to deploy: System bootstrap + USB Automation + Hemlock Runtime
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
USB_AUTO_DIR="$SCRIPT_DIR/usb-compute-automation"
HEMLOCK_DIR="$SCRIPT_DIR/hemlock-runtime"
SKILLS_DIR="$SCRIPT_DIR/hemlock-minimal/skills"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

log() { echo -e "${BLUE}ℹ${NC} $*"; }
success() { echo -e "${GREEN}✓${NC} $*"; }
warn() { echo -e "${YELLOW}⚠${NC} $*"; }
error() { echo -e "${RED}✗${NC} $*" >&2; }

echo -e "${CYAN}${BOLD}"
echo "======================================================================"
echo "  Hemlock USB Compute Automation - Master Deployment"
echo "  System Bootstrap + USB Automation + Hemlock Runtime"
echo "======================================================================"
echo -e "${NC}"

if [[ $EUID -ne 0 ]]; then
    error "Must run with sudo: sudo $0"
    exit 1
fi

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
    echo -e "\n${CYAN}======================================================================${NC}"
    echo -e "${CYAN}  Phase 1: System Bootstrap${NC}"
    echo -e "${CYAN}======================================================================${NC}\n"
    if [[ "$DRY_RUN" == "true" ]]; then
        log "[DRY RUN] Would run: $USB_AUTO_DIR/config/initialize.sh"
    else
        bash "$USB_AUTO_DIR/config/initialize.sh" || { error "System bootstrap failed"; exit 1; }
        success "System bootstrap complete"
    fi
else
    log "Skipping system bootstrap (--no-system)"
fi

if [[ "$INSTALL_USB" == "true" ]]; then
    echo -e "\n${CYAN}======================================================================${NC}"
    echo -e "${CYAN}  Phase 2: USB Compute Automation${NC}"
    echo -e "${CYAN}======================================================================${NC}\n"
    if [[ "$DRY_RUN" == "true" ]]; then
        log "[DRY RUN] Would run: bash $USB_AUTO_DIR/usb-setup-assistant.sh"
    else
        log "Running USB Setup Assistant..."
        bash "$USB_AUTO_DIR/usb-setup-assistant.sh" || { error "USB setup failed"; exit 1; }
        success "USB Compute Automation setup complete"
    fi
else
    log "Skipping USB setup (--no-usb)"
fi

if [[ "$INSTALL_HEMLOCK" == "true" ]]; then
    echo -e "\n${CYAN}======================================================================${NC}"
    echo -e "${CYAN}  Phase 3: Hemlock Runtime Deployment${NC}"
    echo -e "${CYAN}======================================================================${NC}\n"
    
    if [[ -d "$SKILLS_DIR" ]]; then
        log "Installing skills to Hemlock runtime..."
        mkdir -p "$HEMLOCK_DIR/skills"
        if [[ "$DRY_RUN" == "true" ]]; then
            log "[DRY RUN] Would copy skills to $HEMLOCK_DIR/skills"
        else
            cp -r "$SKILLS_DIR"/* "$HEMLOCK_DIR/skills/"
            success "Skills installed to Hemlock runtime"
        fi
    fi
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "[DRY RUN] Would build Docker images"
    else
        log "Building Hemlock Docker images..."
        cd "$HEMLOCK_DIR"
        docker compose -f docker-compose.runtime.yml build 2>&1 | tail -20
        docker compose -f docker-compose.yml build 2>&1 | tail -20
        success "Hemlock Docker images built"
    fi
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "[DRY RUN] Would start services"
    else
        log "Starting Hemlock runtime..."
        docker compose -f "$HEMLOCK_DIR/docker-compose.runtime.yml" up -d
        sleep 5
        docker compose -f "$HEMLOCK_DIR/docker-compose.yml" up -d
        success "Hemlock runtime started"
    fi
else
    log "Skipping Hemlock deployment (--no-hemlock)"
fi

echo -e "\n${CYAN}${BOLD}======================================================================${NC}"
echo -e "${CYAN}${BOLD}  Deployment Complete${NC}"
echo -e "${CYAN}${BOLD}======================================================================${NC}\n"
echo "Package contents deployed:"
echo "  ${GREEN}✓${NC} System bootstrap (initialize.sh)"
echo "  ${GREEN}✓${NC} USB Compute Automation (usb-setup-assistant.sh)"
echo "  ${GREEN}✓${NC} Hemlock Runtime (82 skills + Docker runtime)"
echo
echo "Next steps:"
echo "  1. Log out/in or: source ~/.profile && source ~/.cargo/env"
echo "  2. Run 'tailscale up' to join your tailnet"
echo "  3. Configure USB: sudo bash $USB_AUTO_DIR/usb-setup-assistant.sh"
echo "  4. Access Hemlock TUI: bash $USB_AUTO_DIR/hemlock-tui"
echo "  5. Check Hemlock: docker ps | grep hemlock"
echo
success "All components deployed successfully!"