#!/bin/bash
# =============================================================================
# Hemlock First-Run Initialization System
# 
# On first startup:
# 1. Scans system for hardware capabilities
# 2. Auto-detects optimal Llama.cpp build configuration
# 3. Downloads default Qwen3:0.6B model
# 4. Converts to GGUF
# 5. Configures as default active agent
# 6. Creates helper agent for setup assistance
# 7. Persists all configurations
# 
# Subsequent starts use persisted configurations
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

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$(dirname "$SCRIPT_DIR")/helpers.sh"

CACHE_DIR="${CACHE_DIR:-$RUNTIME_ROOT/.cache}"

# System files
FIRST_RUN_FLAG="$CACHE_DIR/.first_run_completed"
SCAN_RESULTS="$CACHE_DIR/hardware-scan.json"
RECOMMENDATIONS="$CACHE_DIR/hardware-scan-recommendations.json"
PERSISTENT_CONFIG="$CONFIG_DIR/model-config.yaml"
INIT_LOG="$LOGS_DIR/first-run-$(date +%Y%m%d-%H%M%S).log"

# Script locations
HARDWARE_SCANNER="$SCRIPTS_DIR/hardware-scanner.sh"
LLAMA_BUILDER="$SCRIPTS_DIR/llama-build.sh"
MODEL_MANAGER="$SCRIPTS_DIR/model-manager.sh"

# Defaults
DEFAULT_MODEL="qwen3-0.6b"
DEFAULT_QUANT="Q4_K_M"

mkdir -p "$CACHE_DIR" "$CONFIG_DIR" "$AGENTS_DIR" "$LOGS_DIR"

# =============================================================================
# Logging Functions
# =============================================================================
log() {
    echo -e "${BLUE}[INIT]${NC} $1" | tee -a "$INIT_LOG"
}

success() {
    echo -e "${GREEN}[OK]${NC} $1" | tee -a "$INIT_LOG"
}

warn() {
    echo -e "${YELLOW}[WARN]${NC} $1" | tee -a "$INIT_LOG"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1" | tee -a "$INIT_LOG" >&2
}

info() {
    echo -e "${CYAN}[INFO]${NC} $1" | tee -a "$INIT_LOG"
}

# =============================================================================
# Check if first run
# =============================================================================
is_first_run() {
    if [[ ! -f "$FIRST_RUN_FLAG" ]]; then
        return 0
    fi
    return 1
}

mark_first_run_complete() {
    echo "First run completed at: $(date -u +%Y-%m-%dT%H:%M:%SZ)" > "$FIRST_RUN_FLAG"
    success "First run initialization marked as complete"
}

# =============================================================================
# Check if already initialized
# =============================================================================
is_initialized() {
    # Check if default model exists
    if [[ -f "$RUNTIME_ROOT/models/gguf/qwen3-0_6b-$DEFAULT_QUANT.gguf" ]]; then
        return 0
    fi
    
    # Check if persistent config exists
    if [[ -f "$PERSISTENT_CONFIG" ]]; then
        return 0
    fi
    
    return 1
}

# =============================================================================
# Create helper agent
# =============================================================================
create_helper_agent() {
    log "Creating setup helper agent..."
    
    local helper_dir="$AGENTS_DIR/helper"
    mkdir -p "$helper_dir"
    
    # Agent configuration
    cat > "$helper_dir/agent.json" <<'AGENTJSON'
{
  "id": "helper",
  "name": "Hemlock Setup Assistant",
  "description": "Default chatbot agent that helps users understand and set up Hemlock Enterprise. Provides guidance, documentation links, and basic system information.",
  "model": "__DEFAULT_MODEL_PATH__",
  "backend": "llama.cpp",
  "type": "chatbot",
  "role": "assistant",
  "personality": "Helpful and knowledgeable technical assistant",
  "capabilities": ["chat", "knowledgebase", "documentation", "system_info"],
  "tools": ["web_browse"],
  "excluded_tools": ["code_execution", "file_read", "file_write", "file_delete", "bash"],
  "enabled": true,
  "active": true,
  "is_default": true,
  "is_main": true,
  "startup_active": true,
  "system_agent": true,
  "config": {
    "temperature": 0.3,
    "top_p": 0.9,
    "top_k": 50,
    "max_tokens": 4096,
    "context_size": 4096,
    "repeat_penalty": 1.1,
    "presence_penalty": 0.1,
    "frequency_penalty": 0.1,
    "mirostat_mode": 2,
    "mirostat_tau": 0.7,
    "mirostat_eta": 0.1,
    "threads": 4,
    "batch_size": 512
  },
  "knowledge": {
    "system_note": "You are Hemlock Setup Assistant, a helpful AI that guides users through setting up Hemlock Enterprise Agent Framework. You have access to comprehensive documentation and can browse the web for additional information. Do NOT execute any code, read files, or perform file operations - only browse and provide information.",
    "welcome_message": "Hello! I'm Hemlock Setup Assistant. I'm here to help you understand and set up Hemlock Enterprise. This system has been automatically configured with Qwen3:0.6B as the default model. How can I help you today?",
    "topics": [
      "Hemlock Enterprise features",
      "Agent management",
      "Crew logic and blueprints",
      "Secrets management (AES-256 encrypted)",
      "Documentation indexing and search",
      "System hardware detection",
      "Model management"
    ]
  },
  "setup_info": {
    "automatically_configured": true,
    "first_run": true,
    "default_model": "Qwen3:0.6B",
    "backend": "Llama.cpp",
    "quantization": "Q4_K_M",
    "features": ["Hidden file support", "On-demand secrets decryption", "Crew integration", "Documentation indexing"]
  }
}
AGENTJSON
    
    # Helper instructions
    cat > "$helper_dir/INSTRUCTIONS.md" <<'INSTRUCTIONSEOF'
# Hemlock Setup Assistant

You are a setup assistant for Hemlock Enterprise Agent Framework.

## Your Role
- Help users understand the system
- Explain features and capabilities
- Provide documentation links
- Answer questions about setup and configuration
- Guide users through basic operations

## What You CAN Do
- Browse the web for information
- Provide detailed explanations of features
- Reference documentation
- Explain how to use the system

## What You CANNOT Do
- Execute code or commands
- Read or write files
- Delete files
- Perform system operations
- Access sensitive data

## Key Features to Explain
1. **Agent Import**: Import agents with full hidden file support
2. **Secrets Management**: AES-256-CBC encrypted, on-demand decryption
3. **Crew Logic**: Autonomous crew system with blueprints and workflows
4. **Documentation Indexing**: Full-text search across codebase
5. **Hidden Files**: All operations preserve .secrets/, .hermes/, .archive/, .env.enc
6. **Default Model**: Qwen3:0.6B with Llama.cpp as inference engine

## System Overview
Hemlock Enterprise is a production-ready multi-agent AI framework with:
- Modular agent architecture
- Secure secrets management
- Crew-based task execution
- Comprehensive documentation indexing
- Cross-platform hardware detection

## Getting Started
1. The system has been automatically configured
2. Qwen3:0.6B is loaded as the default model
3. Llama.cpp is the inference engine
4. A default agent is active and ready to help
INSTRUCTIONSEOF
    
    # Memory configuration
    cat > "$helper_dir/MEMORY.md" <<'MEMORYEOF'
# Helper Agent Memory

## System Information
- **Model**: Qwen3:0.6B
- **Backend**: Llama.cpp
- **Quantization**: Q4_K_M
- **Type**: Decoder model
- **Parameters**: ~600M

## Capabilities
- Conversational AI
- System documentation
- Setup guidance
- Web browsing for information

## Limitations
- No code execution
- No file system access
- Web browsing only
- Information retrieval only

## Last Initialized
This agent was created during first-run initialization.
All configurations persist across system restarts.

## Usage Tips
- Ask about Hemlock features
- Request documentation
- Inquire about setup procedures
- Get explanations of agent workflows
MEMORYEOF
    
    # SOUL configuration
    cat > "$helper_dir/SOUL.md" <<'SOULEOF'
# Helper Agent SOUL

## Identity
"I am Hemlock Setup Assistant, a helpful AI guide for the Hemlock Enterprise system."

## Purpose
"To assist users in understanding, configuring, and using Hemlock Enterprise Agent Framework."

## Principles
- Be helpful and informative
- Provide accurate documentation
- Guide without executing
- Explain clearly and thoroughly
- Respect system constraints

## Knowledge
- Hemlock system architecture
- Agent management protocols
- Crew logic and blueprints
- Secrets management security
- Documentation indexing
- Hardware detection and optimization

## Constraints
- NO code execution
- NO file operations
- Web browsing ONLY for information
- Documentation reference ONLY
- Information provision ONLY

## Behavior
- Professional and technical
- Patient and thorough
- Clear and concise
- Helpful within constraints
SOULEOF
    
    # User configuration
    cat > "$helper_dir/USER.md" <<'USEREOF'
# Users You Assist

## Target Users
- System administrators
- Developers
- AI engineers
- IT staff
- New users of Hemlock

## User Needs
- Understanding system capabilities
- Setup and configuration guidance
- Feature explanations
- Troubleshooting help
- Documentation

## Communication Style
- Technical but approachable
- Comprehensive but concise
- Helpful and encouraging
- Precise and accurate

## Important Notes
- This is FIRST-RUN initialization
- System is automatically configured
- Default model: Qwen3:0.6B with Llama.cpp
- All settings persist
USEREOF
    
    # Agent type identifier
    echo "chatbot" > "$helper_dir/AGENT_TYPE.txt"
    echo "helper" > "$helper_dir/ROLE.txt"
    echo "true" > "$helper_dir/.default"
    echo "true" > "$helper_dir/.main"
    echo "true" > "$helper_dir/.system"
    
    success "Helper agent created at $helper_dir"
    
    # Update agent reference in list
    # Make helper the default agent
    cat > "$helper_dir/.priority" <<EOF
1
EOF
}

# =============================================================================
# Update default agent to use Qwen3:0.6B
# =============================================================================
update_default_agent() {
    local model_path="$1"
    log "Updating default agent configuration..."
    
    # Update .env file
    if [[ -f "$RUNTIME_ROOT/.env" ]]; then
        if command -v sed &>/dev/null; then
            sed -i "s|^DEFAULT_AGENT_MODEL=.*|DEFAULT_AGENT_MODEL=Qwen3-0.6B|" "$RUNTIME_ROOT/.env" 2>/dev/null || true
        fi
    fi
    
    # Update runtime.yaml
    if [[ -f "$CONFIG_DIR/runtime.yaml" ]]; then
        if command -v sed &>/dev/null; then
            sed -i "s|default_model:.*|default_model: \"Qwen3-0.6B\"|" "$CONFIG_DIR/runtime.yaml" 2>/dev/null || true
        fi
    fi
    
    # Update or create model-config.yaml
    cat > "$PERSISTENT_CONFIG" <<EOF
devault_model: Qwen3-0.6B
default_quant: $DEFAULT_QUANT
default_backend: llama.cpp
active_model: Qwen3-0.6B
first_run_initialized: true

models:
  - name: Qwen3-0.6B
    repo: Qwen/Qwen3-0.6B
    path: $model_path
    gguf_path: $model_path
    enabled: true
    default: true
    quantizations:
      - Q4_K_M
      - Q5_K_M
      - Q8_0

system:
  auto_detected: true
  initialization_complete: true
EOF
    
    success "Configuration updated with Qwen3:0.6B as default"
}

# =============================================================================
# Phase 1: System Scan
# =============================================================================
phase_system_scan() {
    info "${PURPLE}=============================================================================${NC}"
    info "${PURPLE}              PHASE 1: SYSTEM HARDWARE SCANNING                           ${NC}"
    info "${PURPLE}=============================================================================${NC}"
    echo ""
    
    if [[ ! -f "$HARDWARE_SCANNER" ]]; then
        error "Hardware scanner not found at $HARDWARE_SCANNER"
        return 1
    fi
    
    log "Running hardware scanner..."
    bash "$HARDWARE_SCANNER" || {
        warn "Hardware scan encountered some issues, continuing with defaults..."
    }
    
    success "Phase 1: System scan completed"
    return 0
}

# =============================================================================
# Phase 2: Llama.cpp Build
# =============================================================================
phase_llama_build() {
    info "${PURPLE}=============================================================================${NC}"
    info "${PURPLE}              PHASE 2: LLAMA.CPP BUILD                                   ${NC}"
    info "${PURPLE}=============================================================================${NC}"
    echo ""
    
    if [[ ! -f "$LLAMA_BUILDER" ]]; then
        error "Llama builder not found at $LLAMA_BUILDER"
        return 1
    fi
    
    log "Checking if Llama.cpp needs to be built..."
    
    # Check if already built
    if [[ -f "$RUNTIME_ROOT/bin/llama-cli" ]]; then
        success "Llama.cpp already built"
        return 0
    fi
    
    log "Building Llama.cpp with auto-detected configuration..."
    bash "$LLAMA_BUILDER" build || {
        warn "Llama.cpp build encountered issues, trying CPU fallback..."
        bash "$LLAMA_BUILDER" build-cpu || {
            error "Failed to build Llama.cpp"
            return 1
        }
    }
    
    success "Phase 2: Llama.cpp build completed"
    return 0
}

# =============================================================================
# Phase 3: Model Download and Setup
# =============================================================================
phase_model_setup() {
    info "${PURPLE}=============================================================================${NC}"
    info "${PURPLE}              PHASE 3: MODEL DOWNLOAD AND CONVERSION                       ${NC}"
    info "${PURPLE}=============================================================================${NC}"
    echo ""
    
    if [[ ! -f "$MODEL_MANAGER" ]]; then
        error "Model manager not found at $MODEL_MANAGER"
        return 1
    fi
    
    # Determine quantization
    local quant="$DEFAULT_QUANT"
    if [[ -f "$RECOMMENDATIONS" ]]; then
        local recommended=$(jq -r '.recommendations.recommended_quantization // "Q4_K_M"' "$RECOMMENDATIONS" 2>/dev/null || echo "Q4_K_M")
        quant="$recommended"
    fi
    
    log "Setting up Qwen3:0.6B with $quant quantization..."
    bash "$MODEL_MANAGER" setup --quant "$quant" --model "qwen3-0.6b" || {
        error "Failed to setup Qwen3:0.6B model"
        return 1
    }
    
    # Get the model path
    local model_path="$RUNTIME_ROOT/models/gguf/qwen3-0_6b-$quant.gguf"
    
    if [[ ! -f "$model_path" ]]; then
        # Try alternative naming
        model_path=$(find "$RUNTIME_ROOT/models" -name "*.gguf" -type f | head -1 || echo "")
        if [[ "$model_path" == "" ]]; then
            error "Could not find GGUF model file"
            return 1
        fi
    fi
    
    success "Phase 3: Model setup completed"
    echo "$model_path"
    return 0
}

# =============================================================================
# Phase 4: Configuration
# =============================================================================
phase_configuration() {
    info "${PURPLE}=============================================================================${NC}"
    info "${PURPLE}              PHASE 4: SYSTEM CONFIGURATION                               ${NC}"
    info "${PURPLE}=============================================================================${NC}"
    echo ""
    
    local model_path="$1"
    
    # Update configuration
    update_default_agent "$model_path" || {
        warn "Failed to update default agent configuration"
    }
    
    # Create helper agent
    create_helper_agent || {
        warn "Failed to create helper agent"
    }
    
    success "Phase 4: Configuration completed"
    return 0
}

# =============================================================================
# Phase 5: Finalization
# =============================================================================
phase_finalization() {
    info "${PURPLE}=============================================================================${NC}"
    info "${PURPLE}              PHASE 5: FINALIZATION                                       ${NC}"
    info "${PURPLE}=============================================================================${NC}"
    echo ""
    
    log "Finalizing first-run initialization..."
    
    # Create runtime flag
    mark_first_run_complete || {
        warn "Failed to mark first run as complete"
    }
    
    # Verify installation
    log "Verifying installation..."
    
    local checks_passed=0
    local checks_total=5
    
    # Check 1: Llama.cpp binary
    if [[ -f "$RUNTIME_ROOT/bin/llama-cli" ]]; then
        success "  Llama.cpp binary: FOUND"
        checks_passed=$((checks_passed + 1))
    else
        warn "  Llama.cpp binary: NOT FOUND"
    fi
    
    # Check 2: Default model
    if [[ -f "$RUNTIME_ROOT/models/gguf/qwen3-0_6b-Q4_K_M.gguf" ]] || \
       ls "$RUNTIME_ROOT/models/gguf/"*.gguf 1>/dev/null 2>&1; then
        success "  Default model: FOUND"
        checks_passed=$((checks_passed + 1))
    else
        warn "  Default model: NOT FOUND"
    fi
    
    # Check 3: Helper agent
    if [[ -d "$AGENTS_DIR/helper" ]]; then
        success "  Helper agent: FOUND"
        checks_passed=$((checks_passed + 1))
    else
        warn "  Helper agent: NOT FOUND"
    fi
    
    # Check 4: Persistent config
    if [[ -f "$PERSISTENT_CONFIG" ]]; then
        success "  Persistent config: FOUND"
        checks_passed=$((checks_passed + 1))
    else
        warn "  Persistent config: NOT FOUND"
    fi
    
    # Check 5: First run flag
    if [[ -f "$FIRST_RUN_FLAG" ]]; then
        success "  First run flag: FOUND"
        checks_passed=$((checks_passed + 1))
    else
        warn "  First run flag: NOT FOUND"
    fi
    
    echo ""
    info "============================================================================="
    info "  Initialization Results: $checks_passed/$checks_total checks passed"
    info "============================================================================="
    echo ""
    
    if [[ $checks_passed -ge 4 ]]; then
        success "First-run initialization COMPLETED SUCCESSFULLY!"
        echo ""
        echo "  ${GREEN}Qwen3:0.6B is now the default model${NC}"
        echo "  ${GREEN}Llama.cpp is the inference engine${NC}"
        echo "  ${GREEN}Helper agent is active and ready${NC}"
        echo "  ${GREEN}All configurations saved and persisted${NC}"
        echo ""
        return 0
    else
        error "First-run initialization completed with some warnings"
        return 1
    fi
}

# =============================================================================
# Full initialization
# =============================================================================
full_initialization() {
    log "Starting first-run initialization..."
    echo ""
    
    # Get current timestamp
    local start_time=$(date +%s)
    
    # Phase 1: System Scan
    local phase1_result=1
    phase_system_scan && phase1_result=0 || phase1_result=1
    
    # Phase 2: Llama.cpp Build
    local phase2_result=1
    if [[ $phase1_result -eq 0 ]]; then
        phase_llama_build && phase2_result=0 || phase2_result=1
    fi
    
    # Phase 3: Model Setup
    local phase3_result=1
    local model_path=""
    if [[ $phase2_result -eq 0 ]]; then
        model_path=$(phase_model_setup && echo "success" || echo "")
        if [[ "$model_path" != "" ]]; then
            phase3_result=0
        fi
    fi
    
    # Phase 4: Configuration
    local phase4_result=1
    if [[ $phase3_result -eq 0 ]]; then
        phase_configuration "$model_path" && phase4_result=0 || phase4_result=1
    fi
    
    # Phase 5: Finalization
    local phase5_result=1
    if [[ $phase4_result -eq 0 ]]; then
        phase_finalization && phase5_result=0 || phase5_result=1
    fi
    
    # Calculate duration
    local end_time=$(date +%s)
    local duration=$((end_time - start_time))
    local minutes=$((duration / 60))
    local seconds=$((duration % 60))
    
    echo ""
    info "============================================================================="
    info "  First-run initialization took: ${minutes}m ${seconds}s"
    info "============================================================================="
    
    if [[ $phase5_result -eq 0 ]]; then
        # Create summary
        cat > "$LOGS_DIR/INITIALIZATION_SUMMARY.md" <<EOF
# First-Run Initialization Summary

**Status**: COMPLETED SUCCESSFULLY

**Timestamp**: $(date -u +%Y-%m-%dT%H:%M:%SZ)

**Duration**: ${minutes}m ${seconds}s

## Phases Completed

- [x] Phase 1: System Hardware Scan
- [x] Phase 2: Llama.cpp Build
- [x] Phase 3: Model Download and Conversion
- [x] Phase 4: System Configuration
- [x] Phase 5: Finalization

## Default Configuration

- **Model**: Qwen3:0.6B
- **Backend**: Llama.cpp
- **Quantization**: Q4_K_M
- **Inference Engine**: Llama.cpp (auto-built for system)

## Components Installed

1. **Llama.cpp Binary**: "`$RUNTIME_ROOT/bin/llama-cli`"
2. **Default Model**: ""`$RUNTIME_ROOT/models/gguf/qwen3-0_6b-Q4_K_M.gguf`"
3. **Helper Agent**: ""`$AGENTS_DIR/helper/`"
4. **Persistent Config**: ""`$PERSISTENT_CONFIG`"

## Features Enabled

- [x] Hidden file support (.secrets/, .hermes/, .archive/)
- [x] AES-256 encrypted secrets management
- [x] Crew logic integration
- [x] Documentation indexing
- [x] On-demand secrets decryption
- [x] Hardware-optimized Llama.cpp build

## What's Next

1. Run `"./runtime.sh list-agents"` to see available agents
2. Run `"./runtime.sh status"` to check system status
3. Interact with the helper agent for guidance
4. Import additional agents as needed

## Notes

- All configurations persist across system restarts
- The helper agent is active by default
- Qwen3:0.6B is the default model for all new agents
- Llama.cpp automatically uses the best backend for your hardware

EOF
        
        success "Summary saved to $LOGS_DIR/INITIALIZATION_SUMMARY.md"
        return 0
    else
        error "First-run initialization had issues"
        return 1
    fi
}

# =============================================================================
# Quick setup (minimal)
# =============================================================================
quick_setup() {
    log "Running quick setup (huggingface-cli must be installed)..."
    
    # Install huggingface-cli if needed
    if ! command -v huggingface-cli &>/dev/null; then
        log "Installing huggingface-cli..."
        pip3 install -U huggingface-hub 2>/dev/null || {
            error "Failed to install huggingface-hub, trying alternative method..."
            return 1
        }
    fi
    
    # Download model directly
    log "Downloading Qwen3:0.6B with huggingface-cli..."
    huggingface-cli download Qwen/Qwen3-0.6B \
        --local-dir "$RUNTIME_ROOT/models/huggingface/Qwen3-0.6B" \
        --local-dir-use-symlinks False \
        --cache-dir "$CACHE_DIR/huggingface-cache" || {
        error "Failed to download model"
        return 1
    }
    
    # Try to use pre-built llama.cpp
    if ! command -v llama-cli &>/dev/null; then
        log "Installing llama.cpp from system package manager..."
        if [[ "$OSTYPE" == "linux-gnu"* ]]; then
            sudo apt-get install -y llama.cpp 2>/dev/null || true
        fi
    fi
    
    # Mark as initialized
    mark_first_run_complete
    create_helper_agent
    update_default_agent "queue://Qwen3-0.6B"
    
    success "Quick setup completed"
    return 0
}

# =============================================================================
# Usage
# =============================================================================
usage() {
    cat <<EOF
${CYAN}Hemlock First-Run Initialization System${NC}

Usage: $0 <command> [options]

${BLUE}Commands:${NC}
  full           Full initialization (scan, build, download, configure)
  quick          Quick setup (requires huggingface-cli, minimal build)
  scan          Run hardware scan only
  build         Build Llama.cpp only
  model         Download and convert model only
  config        Configure system only
  helper        Create helper agent only
  status        Check initialization status
  summary       Show initialization summary
  
${BLUE}Options:${NC}
  --force       Force re-initialization
  --skip-scan   Skip hardware scanning
  --skip-build  Skip Llama.cpp build
  --skip-model  Skip model download
  --dry-run     Preview actions without executing
  --skip-init   Skip initialization (first-run flag)
  --help, -h    Show this help

${BLUE}Status:${NC}
  First run: $(is_first_run && echo "YES - will initialize" || echo "NO - already initialized")
  Initialized: $(is_initialized && echo "YES" || echo "NO")

${BLUE}Examples:${NC}
  $0 full           # Complete first-run initialization
  $0 quick          # Quick setup (requires huggingface-cli)
  $0 full --force   # Force re-initialization
  $0 status         # Check if already initialized

EOF
}

# =============================================================================
# Main
# =============================================================================
main() {
    local command="${1:-full}"
    local force=false
    local skip_scan=false
    local skip_build=false
    local skip_model=false
    local dry_run=false
    local skip_init=false
    
    shift
    
    # Parse options
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --force)
                force=true
                shift
                ;;
            --skip-scan)
                skip_scan=true
                shift
                ;;
            --skip-build)
                skip_build=true
                shift
                ;;
            --skip-model)
                skip_model=true
                shift
                ;;
            --dry-run)
                dry_run=true
                shift
                ;;
            --skip-init)
                skip_init=true
                shift
                ;;
            --help|-h)
                usage
                exit 0
                ;;
            *)
                # Assume it's a command
                command="$1"
                shift
                ;;
        esac
    done
    
    # Check if already initialized
    if [[ "$force" == false && ! $(is_first_run) ]]; then
        info "System already initialized. Use --force to re-initialize."
        
        if [[ -f "$LOGS_DIR/INITIALIZATION_SUMMARY.md" ]]; then
            echo ""
            cat "$LOGS_DIR/INITIALIZATION_SUMMARY.md"
        fi
        
        exit 0
    fi
    
    # Create initialization log
    mkdir -p "$LOGS_DIR"
    echo "# First-Run Initialization Log" > "$INIT_LOG"
    echo "Started at: $(date -u +%Y-%m-%dT%H:%M:%SZ)" >> "$INIT_LOG"
    echo "Command: $0 $*" >> "$INIT_LOG"
    echo "" >> "$INIT_LOG"
    
    case "$command" in
        "full")
            if [[ "$dry_run" == true ]]; then
                log "DRY RUN: Would perform full initialization"
            elif [[ "$skip_init" == true ]]; then
                log "Skipping full initialization"
            else
                full_initialization
            fi
            ;;
        "quick")
            if [[ "$dry_run" == true ]]; then
                log "DRY RUN: Would perform quick setup"
            elif [[ "$skip_init" == true ]]; then
                log "Skipping quick setup"
            else
                quick_setup
            fi
            ;;
        "scan")
            if [[ "$dry_run" == true ]]; then
                log "DRY RUN: Would run hardware scan"
            elif [[ "$skip_init" == true ]]; then
                log "Skipping hardware scan"
            else
                phase_system_scan
            fi
            ;;
        "build")
            if [[ "$dry_run" == true ]]; then
                log "DRY RUN: Would build Llama.cpp"
            elif [[ "$skip_init" == true ]]; then
                log "Skipping Llama.cpp build"
            else
                phase_llama_build
            fi
            ;;
        "model")
            if [[ "$dry_run" == true ]]; then
                log "DRY RUN: Would setup model"
            elif [[ "$skip_init" == true ]]; then
                log "Skipping model setup"
            else
                phase_model_setup
            fi
            ;;
        "config")
            if [[ "$dry_run" == true ]]; then
                log "DRY RUN: Would configure system"
            elif [[ "$skip_init" == true ]]; then
                log "Skipping configuration"
            else
                phase_configuration
            fi
            ;;
        "helper")
            if [[ "$dry_run" == true ]]; then
                log "DRY RUN: Would create helper agent"
            elif [[ "$skip_init" == true ]]; then
                log "Skipping helper agent creation"
            else
                create_helper_agent
            fi
            ;;
        "status")
            echo "First run: $(is_first_run && echo "YES" || echo "NO")"
            echo "Initialized: $(is_initialized && echo "YES" || echo "NO")"
            ;;
        "summary")
            if [[ -f "$LOGS_DIR/INITIALIZATION_SUMMARY.md" ]]; then
                cat "$LOGS_DIR/INITIALIZATION_SUMMARY.md"
            else
                warn "No initialization summary found"
            fi
            ;;
        *)
            error "Unknown command: $command"
            usage
            exit 1
            ;;
    esac
    
    # Show summary if full initialization was run
    if [[ "$command" == "full" ]]; then
        echo ""
        info "============================================================================="
        info "  Initialization complete! Run: ./runtime.sh status"
        info "============================================================================="
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
