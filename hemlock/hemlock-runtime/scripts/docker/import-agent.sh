#!/bin/bash
# =============================================================================
# OpenClaw Enterprise Framework - Agent Import Script
# 
# Imports an exported agent image into the local framework
# 
# Usage:
#   ./scripts/docker/import-agent.sh my-exported-agent:latest
#   ./scripts/docker/import-agent.sh docker.io/user/my-agent:v1.0.0
#   ./scripts/docker/import-agent.sh --from-registry my-agent
# =============================================================================

set -uo pipefail

# Load common library
SOURCE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "${SOURCE_DIR}/lib/common.sh"

# =============================================================================
# Configuration
# =============================================================================
IMPORT_DIR="${IMPORT_DIR:-./imported-agents}"
DOCKER_COMPOSE="${DOCKER_COMPOSE:-docker-compose}"

# =============================================================================
# Functions
# =============================================================================

usage() {
    cat <<EOF
Usage: $(basename "$0") [OPTIONS] <image|agent-id>

Import an exported OpenClaw agent into the local framework.

Options:
  -r, --registry    Pull from registry before importing
  -d, --dir DIR     Import directory (default: ./imported-agents)
  -n, --name NAME   Custom agent name for import
  -h, --help        Show this help message

Examples:
  $(basename "$0") my-exported-agent:latest
  $(basename "$0") -r docker.io/user/my-agent:v1.0.0
  $(basename "$0") -d ./my-agents my-agent
EOF
    exit 0
}

parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -r|--registry)
                PULL_FROM_REGISTRY=true
                shift
                ;;
            -d|--dir)
                IMPORT_DIR="$2"
                shift 2
                ;;
            -n|--name)
                AGENT_NAME="$2"
                shift 2
                ;;
            -h|--help)
                usage
                ;;
            *)
                if [[ -z "${AGENT_IMAGE:-}" ]]; then
                    AGENT_IMAGE="$1"
                fi
                shift
                ;;
        esac
    done
}

extract_agent_id_from_image() {
    local image="$1"
    
    # Try to extract agent ID from image name
    # Image format: registry/repo:tag or repo:tag or name
    
    # Remove registry prefix if present
    local without_registry=${image#*/}
    
    # Remove tag if present
    local without_tag=${without_registry%:*}
    
    # Try to extract from labels
    local labels
    labels=$(docker inspect --format '{{json .Config.Labels}}' "$image" 2>/dev/null || echo "{}")
    
    local agent_id
    agent_id=$(echo "$labels" | jq -r '."com.openclaw.agent.id"' 2>/dev/null || echo "")
    
    if [[ -n "$agent_id" ]]; then
        echo "$agent_id"
        return 0
    fi
    
    # Fallback to image name
    echo "${without_tag}"
}

import_agent() {
    local image="$1"
    local import_dir="$2"
    local agent_name="$3"
    
    # Validate image exists
    if ! docker inspect "$image" &>/dev/null; then
        if [[ "${PULL_FROM_REGISTRY:-false}" == "true" ]]; then
            log "Pulling image from registry: $image"
            docker pull "$image" || fatal "Failed to pull image: $image"
        else
            fatal "Image not found locally: $image. Use -r/--registry to pull from registry."
        fi
    fi
    
    # Extract agent ID from image
    local agent_id
    agent_id=$(extract_agent_id_from_image "$image") || fatal "Could not determine agent ID from image"
    
    # Use custom name if provided
    local target_name="${agent_name:-${agent_id}}"
    
    log "Importing agent '$agent_id' as '$target_name' to $import_dir"
    
    # Create import directory
    local agent_dir="$import_dir/$target_name"
    safe_mkdir "$agent_dir" || fatal "Failed to create import directory: $agent_dir"
    
    # Copy configuration from image
    log "Extracting configuration from image..."
    
    # Create a temporary container to extract files
    local container_id
    container_id=$(docker create "$image" 2>/dev/null) || fatal "Failed to create temporary container"
    
    # Copy config out of container
    docker cp "$container_id:/app/config/agent.yaml" "$agent_dir/config.yaml" 2>/dev/null || \
        docker cp "$container_id:/app/config/" "$agent_dir/" 2>/dev/null || \
        warn "Could not extract configuration from image"
    
    # Copy any additional files
    docker cp "$container_id:/app/" "$agent_dir/" 2>/dev/null && \
        warn "Copied all files from image to $agent_dir"
    
    # Clean up temporary container
    docker rm "$container_id" >/dev/null 2>&1 || warn "Failed to remove temporary container"
    
    # Check if we got a config file
    if [[ ! -f "$agent_dir/config.yaml" ]]; then
        warn "No config.yaml found in imported agent. Creating default..."
        create_default_config "$agent_dir/config.yaml" "$target_name"
    fi
    
    # Validate the imported configuration
    validate_imported_agent "$agent_dir" || return 1
    
    # Update docker-compose to include the new agent
    add_agent_to_compose "$target_name" "$agent_dir" || warn "Failed to add agent to docker-compose"
    
    success "Successfully imported agent '$target_name' to $agent_dir"
    echo ""
    echo "To start the imported agent:"
    echo "  cd $import_dir/$target_name"
    echo "  docker-compose up -d"
}

create_default_config() {
    local config_file="$1"
    local agent_name="$2"
    
    cat > "$config_file" <<EOF
agent:
  id: $agent_name
  name: $agent_name
  model: "ollama/qwen3:0.6b"
  personality: "default"
  memory:
    enabled: true
    max_chars: 100000
  tools:
    enabled: true
  security:
    read_only: true
    cap_drop: true
EOF
}

validate_imported_agent() {
    local agent_dir="$1"
    
    log "Validating imported agent in $agent_dir..."
    
    # Check for config file
    [[ -f "$agent_dir/config.yaml" ]] || {
        error "Missing config.yaml in $agent_dir"
        return 1
    }
    
    # Validate YAML syntax
    if command -v yq &>/dev/null; then
        yq eval "$agent_dir/config.yaml" >/dev/null 2>&1 || {
            error "Invalid YAML in $agent_dir/config.yaml"
            return 1
        }
    elif command -v python3 &>/dev/null; then
        python3 -c "import yaml; yaml.safe_load(open('$agent_dir/config.yaml'))" 2>/dev/null || {
            error "Invalid YAML in $agent_dir/config.yaml"
            return 1
        }
    else
        warn "Neither yq nor python3 available, skipping YAML validation"
    fi
    
    # Check for required fields
    if ! grep -q "^id:" "$agent_dir/config.yaml" 2>/dev/null; then
        error "Missing 'id' field in config.yaml"
        return 1
    fi
    
    if ! grep -q "^model:" "$agent_dir/config.yaml" 2>/dev/null; then
        warn "Missing 'model' field in config.yaml, using default"
    fi
    
    success "Agent validation passed"
    return 0
}

add_agent_to_compose() {
    local agent_name="$1"
    local agent_dir="$2"
    
    log "Adding agent '$agent_name' to docker-compose.yml..."
    
    # Check if agent already exists in compose
    if grep -q "$agent_name:" docker-compose.yml 2>/dev/null; then
        warn "Agent '$agent_name' already exists in docker-compose.yml"
        return 0
    fi
    
    # Get agent ID from config
    local agent_config="$agent_dir/config.yaml"
    local agent_id
    agent_id=$(grep "^  id:" "$agent_config" 2>/dev/null | head -1 | awk '{print $2}' || echo "$agent_name")
    local model
    model=$(grep "^  model:" "$agent_config" 2>/dev/null | head -1 | awk '{print $2}' | tr -d '"' || echo "ollama/qwen3:0.6b")
    
    # Append agent service to docker-compose.yml
    cat >> docker-compose.yml <<EOF

  # --- Imported Agent: $agent_name ---
  ${agent_id}:
    build:
      context: .
      dockerfile: Dockerfile.agent
      args:
        AGENT_ID: ${agent_id}
        MODEL: ${model}
    container_name: ${agent_id}
    restart: unless-stopped
    environment:
      - AGENT_ID=${agent_id}
      - MODEL=${model}
      - OPENCLAW_GATEWAY_URL=ws://openclaw-gateway:18789
      - OPENCLAW_GATEWAY_TOKEN=\${OPENCLAW_GATEWAY_TOKEN:-change_this_to_a_secure_token}
      - CREW_CHANNEL=""
    volumes:
      - ./${agent_id}-data:/app/data
      - ./${agent_id}-config:/app/config
    networks:
      - agents_net
    cap_drop:
      - ALL
    read_only: true
    tmpfs:
      - /tmp:size=64m
    depends_on:
      openclaw-gateway:
        condition: service_healthy
EOF
    
    success "Added agent '$agent_name' to docker-compose.yml"
}

# =============================================================================
# Main
# =============================================================================

parse_args "$@"

if [[ -z "${AGENT_IMAGE:-}" ]]; then
    error "No agent image specified"
    usage
    exit 1
fi

# Create import directory if it doesn't exist
safe_mkdir "$IMPORT_DIR" || fatal "Failed to create import directory: $IMPORT_DIR"

# Import the agent
import_agent "$AGENT_IMAGE" "$IMPORT_DIR" "${AGENT_NAME:-}"

exit 0
