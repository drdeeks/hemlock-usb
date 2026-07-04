#!/bin/bash
# =============================================================================
# Hermes Agent Runner
# Launches Hermes agents with OpenClaw Gateway integration
# =============================================================================

set -euo pipefail

# =============================================================================
# Configuration
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RUNTIME_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
AGENTS_ROOT="${RUNTIME_ROOT}/agents"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log() { echo -e "${BLUE}[INFO]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; }
success() { echo -e "${GREEN}[OK]${NC} $1"; }

# =============================================================================
# Usage
# =============================================================================

usage() {
    cat << EOF
${GREEN}Hermes Agent Runner${NC}

Usage: $0 <AGENT_ID> [OPTIONS]

Arguments:
    AGENT_ID          Agent identifier (e.g., 'mort', 'allman')

Options:
    -h, --help        Show this help
    -d, --detach     Run in detached mode
    -b, --backend     Model backend (ollama, openrouter, nous)
    -m, --model       Model name
    -p, --profile     Hermes profile
    -e, --env         Environment variable (VAR=value)
    --no-build        Skip Docker image build
    --shell           Start shell instead of agent

Examples:
    $0 mort
    $0 mort --detach --model ollama/qwen3:0.6b
    $0 mort --env MODEL_TEMPERATURE=0.5

EOF
    exit 1
}

# =============================================================================
# Validation
# =============================================================================

validate_agent_id() {
    local id="$1"
    
    if ! [[ "$id" =~ ^[a-zA-Z0-9_-]+$ ]]; then
        error "Invalid agent ID '$id'. Use alphanumeric, hyphens, and underscores only."
        return 1
    fi
    
    return 0
}

validate_agent_exists() {
    local agent_path="${AGENTS_ROOT}/${AGENT_ID}"
    
    if [[ ! -d "$agent_path" ]]; then
        error "Agent not found: ${AGENT_ID}"
        error "Create it with: ./scripts/agent-create.sh --id ${AGENT_ID}"
        return 1
    fi
    
    return 0
}

# =============================================================================
# Build Docker Image
# =============================================================================

build_hermes_image() {
    local no_build="${1:-false}"
    
    # Check if image exists
    if docker images hermes-agent:latest -q &> /dev/null; then
        if [[ "$no_build" == "true" ]]; then
            log "Using existing hermes-agent image"
            return 0
        fi
    fi
    
    log "Building Hermes agent image..."
    
    if docker build -t hermes-agent:latest -f "${RUNTIME_ROOT}/hermes/Dockerfile" "${RUNTIME_ROOT}/hermes" 2>&1; then
        success "Hermes agent image built successfully"
    else
        error "Failed to build Hermes agent image"
        return 1
    fi
}

# =============================================================================
# Get Agent Config
# =============================================================================

get_agent_model() {
    local agent_path="${AGENTS_ROOT}/${AGENT_ID}"
    local config_file="${agent_path}/config/agent.json"
    
    if [[ -f "$config_file" ]]; then
        grep -o '"model_name": "[^"]*"' "$config_file" 2>/dev/null | head -1 | cut -d'"' -f4
    fi
}

# =============================================================================
# Main
# =============================================================================

main() {
    local agent_id=""
    local detach=""
    local backend=""
    local model=""
    local profile=""
    local env_vars=()
    local no_build="false"
    local shell_mode="false"
    
    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h|--help) usage ;;
            -d|--detach) detach="-d"; shift ;;
            -b|--backend) backend="$2"; shift 2 ;;
            -m|--model) model="$2"; shift 2 ;;
            -p|--profile) profile="$2"; shift 2 ;;
            -e|--env)
                env_vars+=("$2")
                shift 2
                ;;
            --no-build) no_build="true"; shift ;;
            --shell) shell_mode="true"; shift ;;
            *)
                if [[ -z "$agent_id" ]]; then
                    agent_id="$1"
                else
                    error "Unexpected argument: $1"
                    usage
                fi
                shift
                ;;
        esac
    done
    
    # Validate agent_id
    if [[ -z "$agent_id" ]]; then
        error "Agent ID is required"
        usage
    fi
    
    AGENT_ID="$agent_id"
    
    if ! validate_agent_id "$AGENT_ID"; then
        exit 1
    fi
    
    if ! validate_agent_exists; then
        exit 1
    fi
    
    # Build image
    if [[ "$no_build" != "true" ]]; then
        build_hermes_image "$no_build" || exit 1
    fi
    
    # Get agent config
    local agent_path="${AGENTS_ROOT}/${AGENT_ID}"
    local default_model=$(get_agent_model)
    
    # Set defaults
    backend="${backend:-ollama}"
    model="${model:-${default_model:-ollama/qwen3:0.6b}}"
    
    log "=========================================="
    log "Launching Hermes Agent: ${AGENT_ID}"
    log "=========================================="
    log "  Backend:  $backend"
    log "  Model:    $model"
    [[ -n "$profile" ]] && log "  Profile:  $profile"
    [[ ${#env_vars[@]} -gt 0 ]] && log "  Env:      ${env_vars[*]}"
    log "=========================================="
    
    # Set environment variables
    export AGENT_ID
    export MODEL_BACKEND="$backend"
    export DEFAULT_MODEL="$model"
    export AGENT_DATA="${agent_path}/data"
    export AGENT_WORKSPACE="${agent_path}/workspace"
    
    # Source agent env if exists
    if [[ -f "${agent_path}/config/agent.env" ]]; then
        set -a
        source "${agent_path}/config/agent.env"
        set +a
    fi
    
    # Apply additional env vars
    for var in "${env_vars[@]}"; do
        export "$var"
    done
    
    # Build docker command
    local docker_cmd="docker run"
    
    # Detach mode
    [[ -n "$detach" ]] && docker_cmd="$docker_cmd $detach"
    
    # Name
    docker_cmd="$docker_cmd --name oc-${AGENT_ID}"
    
    # Restart policy
    docker_cmd="$docker_cmd --restart unless-stopped"
    
    # Security options
    docker_cmd="$docker_cmd --read-only=true"
    docker_cmd="$docker_cmd --cap-drop=ALL"
    docker_cmd="$docker_cmd --security-opt=no-new-privileges:true"
    
    # Tmpfs
    docker_cmd="$docker_cmd --tmpfs /tmp:size=64m,mode=1777"
    
    # User
    docker_cmd="$docker_cmd --user 1000:1000"
    
    # Network
    docker_cmd="$docker_cmd --network agents_net"
    
    # Environment
    docker_cmd="$docker_cmd -e AGENT_ID=${AGENT_ID}"
    docker_cmd="$docker_cmd -e MODEL_BACKEND=${backend}"
    docker_cmd="$docker_cmd -e DEFAULT_MODEL=${model}"
    docker_cmd="$docker_cmd -e OPENCLAW_GATEWAY_URL=ws://gateway:18789"
    docker_cmd="$docker_cmd -e HERMES_MODE=openclaw"
    docker_cmd="$docker_cmd -e HERMES_DATA_DIR=/data"
    docker_cmd="$docker_cmd -e HERMES_CONFIG_DIR=/config"
    
    # Add custom env vars
    for var in "${env_vars[@]}"; do
        local var_name="${var%%=*}"
        local var_value="${var#*=}"
        docker_cmd="$docker_cmd -e ${var_name}=${var_value}"
    done
    
    # Volumes
    docker_cmd="$docker_cmd -v ${RUNTIME_ROOT}/hermes/config:/config:ro"
    docker_cmd="$docker_cmd -v ${RUNTIME_ROOT}/canonical:/canonical:ro"
    docker_cmd="$docker_cmd -v ${agent_path}/data:/data:rw"
    docker_cmd="$docker_cmd -v ${agent_path}/workspace:/workspace:rw"
    docker_cmd="$docker_cmd -v ${agent_path}/sessions:/sessions:ro"
    
    # Extra hosts
    docker_cmd="$docker_cmd --add-host=host.docker.internal:host-gateway"
    
    # Image
    docker_cmd="$docker_cmd hermes-agent:latest"
    
    # Command
    if [[ "$shell_mode" == "true" ]]; then
        docker_cmd="$docker_cmd /bin/bash"
    else
        docker_cmd="$docker_cmd hermes --tui"
    fi
    
    # Execute
    echo ""
    log "Executing: docker $(echo "$docker_cmd" | sed 's/docker run//')"
    echo ""
    
    eval "$docker_cmd"
}

main "$@"