#!/bin/bash
# =============================================================================
# Hemlock Qwen3:0.6B + Llama.cpp Setup Script
# 
# Complete setup script that:
# 1. Scans system hardware
# 2. Builds Llama.cpp with optimal backend
# 3. Downloads Qwen3:0.6B from HuggingFace
# 4. Converts to GGUF format (Q4_K_M)
# 5. Configures as default model
# 6. Creates helper agent
# 
# Usage: ./setup-qwen3-llama.sh [options]
# =============================================================================

set -euo pipefail

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
PURPLE='\033[0;35m'
NC='\033[0m'

SCRIPTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RUNTIME_ROOT="$(dirname "$SCRIPTS_DIR")"

# Script locations
HARDWARE_SCANNER="$SCRIPTS_DIR/system/hardware-scanner.sh"
LLAMA_BUILDER="$SCRIPTS_DIR/system/llama-build.sh"
MODEL_MANAGER="$SCRIPTS_DIR/system/model-manager.sh"
FIRST_RUN="$SCRIPTS_DIR/system/first-run.sh"

# Defaults
NEW=Q4_K_M MODEL="qwen3-0.6b"

log() {
    echo -e "${BLUE}[SETUP]${NC} $1"
}

success() {
    echo -e "${GREEN}[OK]${NC} $1"
}

warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1" >&2
}

info() {
    echo -e "${CYAN}[INFO]${NC} $1"
}

usage() {
    cat <<EOF
${CYAN}Hemlock Qwen3:0.6B + Llama.cpp Setup${NC}

Complete setup for Qwen3:0.6B with Llama.cpp as default inference engine.

${BLUE}Usage:${NC}
  $0 [command] [options]

${BLUE}Commands:${NC}
  full              Complete setup (scan, build, download, convert, configure)
  scan              Run hardware scan only
  build             Build Llama.cpp only
  model             Download and convert model only
  setup             Run first-run initialization
  clean             Clean all setup files
  
${BLUE}Options:${NC}
  --quant <q>       Quantization type (default: Q4_K_M)
                     Options: Q4_0, Q4_K_M, Q5_0, Q5_K_M, Q8_0
  --model <m>       Model name (default: qwen3-0.6b)
  --backend <b>     Force backend: cpu, cuda, metal, rocm, vulkan
  --force           Force re-setup
  --dry-run         Preview actions without executing
  --help, -h        Show this help

${BLUE}Examples:${NC}
  $0 full                     # Complete setup with defaults
  $0 full --quant Q5_K_M      # Setup with Q5_K_M quantization
  $0 scan && $0 build         # Scan then build
  $0 model --quant Q4_K_M     # Download and convert model
  $0 full --force             # Force re-setup from scratch

${BLUE}What This Script Does:${NC}
  1. Detects your hardware (CPU features, GPU, Metal, etc.)
  2. Builds Llama.cpp with optimal acceleration backend
  3. Downloads Qwen3:0.6B from HuggingFace
  4. Converts to GGUF format with specified quantization
  5. Configures as default model for all agents
  6. Creates a helper agent for setup assistance
  7. Persists all configurations for future use

EOF
}

# =============================================================================
# Main
# =============================================================================
main() {
    local command="${1:-full}"
    local quant="Q4_K_M"
    local model="qwen3-0.6b"
    local backend=""
    local force=false
    local dry_run=false
    
    shift
    
    # Parse options
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --quant)
                quant="$2"
                shift 2
                ;;
            --model)
                model="$2"
                shift 2
                ;;
            --backend)
                backend="$2"
                shift 2
                ;;
            --force)
                force=true
                shift
                ;;
            --dry-run)
                dry_run=true
                shift
                ;;
            --help|-h)
                usage
                exit 0
                ;;
            *)
                shift
                ;;
        esac
    done
    
    case "$command" in
        "full")
            if [[ "$dry_run" == true ]]; then
                info "${PURPLE}===========================================================================${NC}"
                info "${PURPLE}       DRY RUN: Would perform Hemlock Qwen3:0.6B + Llama.cpp Complete Setup${NC}"
                info "${PURPLE}===========================================================================${NC}"
                echo ""
                log "DRY RUN: Would run first-run initialization with quant=$quant and model=$model"
            else
                info "${PURPLE}===========================================================================${NC}"
                info "${PURPLE}       Hemlock Qwen3:0.6B + Llama.cpp Complete Setup                      ${NC}"
                info "${PURPLE}===========================================================================${NC}"
                echo ""
                
                # Run first-run initialization
                if [[ -f "$FIRST_RUN" ]]; then
                    log "Running first-run initialization..."
                    bash "$FIRST_RUN" full --quant "$quant" --model "$model" || {
                        error "First-run initialization failed"
                        exit 1
                    }
                else
                    error "First-run script not found at $FIRST_RUN"
                    exit 1
                fi
                
                success "Setup completed successfully!"
                echo ""
                info "Next steps:"
                info "  1. Run ./runtime.sh list-agents to see your agents"
                info "  2. Run ./runtime.sh status to check system health"
                info "  3. Interact with the helper agent for guidance"
            fi
            ;;
        "scan")
            if [[ "$dry_run" == true ]]; then
                log "DRY RUN: Would run hardware scan"
            else
                log "Running hardware scan..."
                if [[ -f "$HARDWARE_SCANNER" ]]; then
                    bash "$HARDWARE_SCANNER"
                else
                    error "Hardware scanner not found"
                    exit 1
                fi
            fi
            ;;
        "build")
            if [[ "$dry_run" == true ]]; then
                log "DRY RUN: Would build Llama.cpp with backend=$backend"
            else
                log "Building Llama.cpp..."
                if [[ -f "$LLAMA_BUILDER" ]]; then
                    if [[ "$backend" != "" ]]; then
                        bash "$LLAMA_BUILDER" "build-$backend"
                    else
                        bash "$LLAMA_BUILDER" build
                    fi
                else
                    error "Llama builder not found"
                    exit 1
                fi
            fi
            ;;
        "model")
            if [[ "$dry_run" == true ]]; then
                log "DRY RUN: Would download and convert model $model with quant=$quant"
            else
                log "Downloading and converting model..."
                if [[ -f "$MODEL_MANAGER" ]]; then
                    bash "$MODEL_MANAGER" setup --quant "$quant" --model "$model"
                else
                    error "Model manager not found"
                    exit 1
                fi
            fi
            ;;
        "setup")
            if [[ "$dry_run" == true ]]; then
                log "DRY RUN: Would run first-run initialization with quant=$quant and model=$model"
            else
                log "Running first-run initialization..."
                if [[ -f "$FIRST_RUN" ]]; then
                    bash "$FIRST_RUN" full --quant "$quant" --model "$model"
                else
                    error "First-run script not found"
                    exit 1
                fi
            fi
            ;;
        "clean")
            if [[ "$dry_run" == true ]]; then
                log "DRY RUN: Would clean setup files"
            else
                log "Cleaning setup files..."
                rm -rf "$RUNTIME_ROOT/.cache/llama.cpp" 2>/dev/null || true
                rm -rf "$RUNTIME_ROOT/models" 2>/dev/null || true
                rm -f "$RUNTIME_ROOT/.cache/.first_run_completed" 2>/dev/null || true
                success "Setup files cleaned"
            fi
            ;;
        *)
            error "Unknown command: $command"
            usage
            exit 1
            ;;
    esac
}

# Check for required tools
check_dependencies() {
    local missing=0
    
    if ! command -v git &>/dev/null; then
        warn "git is required but not found"
        missing=$((missing + 1))
    fi
    
    if ! command -v make &>/dev/null; then
        warn "make is required but not found"
        missing=$((missing + 1))
    fi
    
    if ! command -v g++ &>/dev/null && ! command -v clang &>/dev/null; then
        warn "C++ compiler (g++ or clang) is required but not found"
        missing=$((missing + 1))
    fi
    
    if ! command -v cmake &>/dev/null; then
        warn "cmake is required but not found"
        missing=$((missing + 1))
    fi
    
    if [[ $missing -gt 0 ]]; then
        error "$missing required dependencies are missing"
        info "Install with:"
        info "  Ubuntu/Debian: sudo apt-get install -y git make g++ cmake"
        info "  macOS: brew install git make cmake"
        exit 1
    fi
}

# Ensure jq is available
if ! command -v jq &>/dev/null; then
    warn "jq not found, installing..."
    if [[ "$OSTYPE" == "linux-gnu"* ]]; then
        sudo apt-get update && sudo apt-get install -y jq 2>/dev/null || true
    elif [[ "$OSTYPE" == "darwin"* ]]; then
        brew install jq 2>/dev/null || true
    fi
fi

main "$@"
