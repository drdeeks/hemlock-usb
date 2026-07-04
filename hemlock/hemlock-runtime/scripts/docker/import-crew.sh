#!/bin/bash
# =============================================================================
# OpenClaw Enterprise Framework - Crew Import Script
# 
# Imports a crew from a Docker image into the local framework
# 
# Usage:
#   ./scripts/docker/import-crew.sh my-exported-crew:latest
#   ./scripts/docker/import-crew.sh docker.io/user/my-crew:v1.0.0
#   ./scripts/docker/import-crew.sh --from-registry my-crew
# =============================================================================

set -uo pipefail

# Load common library
SOURCE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "${SOURCE_DIR}/lib/common.sh"

# =============================================================================
# Configuration
# =============================================================================
IMPORT_DIR="${IMPORT_DIR:-${SOURCE_DIR}/imported-crews}"
CREWS_DIR="${CREWS_DIR:-${SOURCE_DIR}/crews}"
AGENTS_DIR="${AGENTS_DIR:-${SOURCE_DIR}/agents}"
DOCKER_COMPOSE_FILE="${SOURCE_DIR}/docker-compose.yml"

# =============================================================================
# Functions
# =============================================================================

usage() {
    cat <<EOF
Usage: $(basename "$0") [OPTIONS] <image|crew-id>

Import an exported OpenClaw crew from a Docker image.

Options:
  -r, --registry    Pull from registry before importing
  -d, --dir DIR     Import directory (default: ${IMPORT_DIR})
  -n, --name NAME   Custom crew name for import
  -h, --help        Show this help message

Examples:
  $(basename "$0") my-exported-crew:latest
  $(basename "$0") docker.io/user/my-crew:v1.0.0
  $(basename "$0") -r -d ./my-crews my-crew
EOF
    exit 0
}

extract_crew_id_from_image() {
    local image="$1"
    
    # Remove registry prefix if present
    local without_registry=${image#*/}
    
    # Remove tag if present
    local without_tag=${without_registry%:*}
    
    # Remove crew- prefix if present
    local crew_id=${without_tag#crew-}
    
    # Try to extract from labels
    local labels
    labels=$(docker inspect --format '{{json .Config.Labels}}' "$image" 2>/dev/null || echo "{}")
    
    local extracted_id
    extracted_id=$(echo "$labels" | jq -r '."com.openclaw.crew.id"' 2>/dev/null || echo "")
    
    if [[ -n "$extracted_id" ]]; then
        echo "$extracted_id"
        return 0
    fi
    
    echo "$crew_id"
}

import_crew() {
    local image="$1"
    local import_dir="$2"
    local crew_name="$3"
    
    # Validate image exists
    if ! docker inspect "$image" &>/dev/null; then
        if [[ "${PULL_FROM_REGISTRY:-false}" == "true" ]]; then
            log "Pulling image from registry: $image"
            docker pull "$image" || fatal "Failed to pull image: $image"
        else
            fatal "Image not found locally: $image. Use -r/--registry to pull from registry."
        fi
    fi
    
    # Extract crew ID from image
    local crew_id
    crew_id=$(extract_crew_id_from_image "$image") || fatal "Could not determine crew ID from image"
    
    # Use custom name if provided
    local target_name="${crew_name:-${crew_id}}"
    
    log "Importing crew '$crew_id' as '$target_name' to $import_dir"
    
    # Create import directory
    local crew_import_dir="$import_dir/$target_name"
    safe_mkdir "$crew_import_dir" || fatal "Failed to create import directory: $crew_import_dir"
    
    # Create temporary container to extract files
    local container_id
    container_id=$(docker create "$image" 2>/dev/null) || fatal "Failed to create temporary container"
    
    # Extract crew configuration
    log "Extracting crew configuration from image..."
    docker cp "$container_id:/app/crews" "$crew_import_dir/" 2>/dev/null || \
        warn "Could not extract crew configuration"
    
    # Extract agent configurations if they exist
    docker cp "$container_id:/app/agents" "$crew_import_dir/" 2>/dev/null || \
        warn "Could not extract agent configurations"
    
    # Clean up temporary container
    docker rm "$container_id" >/dev/null 2>&1 || warn "Failed to remove temporary container"
    
    # Check what we extracted
    local extracted_crew_dir="$crew_import_dir/crews/${crew_id}"
    local extracted_agents_dir="$crew_import_dir/agents"
    
    # Move crew files to target location
    if [[ -d "$extracted_crew_dir" ]]; then
        log "Moving crew files to target location..."
        mkdir -p "$CREWS_DIR/$target_name"
        cp -r "$extracted_crew_dir"/* "$CREWS_DIR/$target_name/" 2>/dev/null || \
            fatal "Failed to copy crew files"
        
        # Clean up extracted directory
        rm -rf "$extracted_crew_dir"
    else
        # Try to find crew.yaml directly
        local found_crew_yaml=false
        for crew_subdir in "$crew_import_dir"/*/; do
            if [[ -f "$crew_subdir/crew.yaml" ]]; then
                log "Found crew.yaml in $crew_subdir"
                mkdir -p "$CREWS_DIR/$target_name"
                cp -r "$crew_subdir"/* "$CREWS_DIR/$target_name/" 
                found_crew_yaml=true
                break
            fi
        done
        
        if [[ "$found_crew_yaml" == false ]]; then
            fatal "Could not find crew.yaml in extracted files"
        fi
    fi
    
    # Import agents if they were extracted
    if [[ -d "$extracted_agents_dir" ]]; then
        log "Importing agent configurations..."
        for agent_dir in "$extracted_agents_dir"/*/; do
            local agent_id=$(basename "$agent_dir")
            if [[ -f "$agent_dir/config.yaml" ]]; then
                log "  Importing agent: $agent_id"
                mkdir -p "$AGENTS_DIR/$agent_id"
                cp -r "$agent_dir"/* "$AGENTS_DIR/$agent_id/"
                
                # Validate agent
                if [[ -f "$AGENTS_DIR/$agent_id/config.yaml" ]]; then
                    success "  Agent $agent_id imported"
                else
                    warn "  Failed to import agent $agent_id"
                fi
            fi
        done
    fi
    
    # Validate the imported crew
    validate_imported_crew "$CREWS_DIR/$target_name" || return 1
    
    # Update docker-compose.yml
    add_crew_to_compose "$target_name" || warn "Failed to add crew to docker-compose"
    
    # Clean up temp files
    rm -rf "$crew_import_dir"
    
    success "Successfully imported crew '$target_name' to $CREWS_DIR/$target_name"
    echo ""
    echo "To start the imported crew:"
    echo "  cd $CREWS_DIR/$target_name"
    echo "  ./scripts/crew-start.sh $target_name"
}

validate_imported_crew() {
    local crew_dir="$1"
    
    log "Validating imported crew in $crew_dir..."
    
    if [[ ! -d "$crew_dir" ]]; then
        fatal "Crew directory does not exist: $crew_dir"
    fi
    
    if [[ ! -f "$crew_dir/crew.yaml" ]]; then
        fatal "Missing crew.yaml in $crew_dir"
    fi
    
    # Validate YAML syntax
    if command -v yq &>/dev/null; then
        yq eval "$crew_dir/crew.yaml" >/dev/null 2>&1 || {
            fatal "Invalid YAML in $crew_dir/crew.yaml"
        }
    elif command -v python3 &>/dev/null; then
        python3 -c "import yaml; yaml.safe_load(open('$crew_dir/crew.yaml'))" 2>/dev/null || {
            fatal "Invalid YAML in $crew_dir/crew.yaml"
        }
    else
        warn "Neither yq nor python3 available, skipping YAML validation"
    fi
    
    # Check for required fields
    if ! grep -q "^id:\|^name:\|^crew:" "$crew_dir/crew.yaml" 2>/dev/null; then
        fatal "Missing required fields in crew.yaml"
    fi
    
    success "Crew validation passed"
    return 0
}

add_crew_to_compose() {
    local crew_name="$1"
    local crew_dir="$CREWS_DIR/$crew_name"
    
    log "Adding crew '$crew_name' services to docker-compose.yml..."
    
    # Check if crew already exists in compose
    if grep -q "# Crew: $crew_name" "$DOCKER_COMPOSE_FILE" 2>/dev/null; then
        warn "Crew '$crew_name' already exists in docker-compose.yml"
        return 0
    fi
    
    # Get agents from crew.yaml
    local agents_in_crew=()
    if command -v yq &>/dev/null; then
        agents_in_crew=($(yq eval '.crew.agents[]' "$crew_dir/crew.yaml" 2>/dev/null || echo ""))
    else
        while IFS= read -r line; do
            if [[ "$line" =~ ^\s*-\s*([a-zA-Z0-9_-]+) ]]; then
                agents_in_crew+=("${BASH_REMATCH[1]}")
            fi
        done < "$crew_dir/crew.yaml"
    fi
    
    if [[ ${#agents_in_crew[@]} -eq 0 ]]; then
        warn "No agents found in crew.yaml"
        return 0
    fi
    
    # Add comment header
    cat >> "$DOCKER_COMPOSE_FILE" <<EOF

  # Crew: $crew_name
EOF
    
    # Add each agent from the crew
    for agent_id in "${agents_in_crew[@]}"; do
        cat >> "$DOCKER_COMPOSE_FILE" <<EOF
  oc-${crew_name}-${agent_id}:
    build:
      context: .
      dockerfile: Dockerfile.agent
      args:
        AGENT_ID: ${agent_id}
        MODEL: ollama/qwen3:0.6b
        CREW_CHANNEL: ${crew_name}
    container_name: oc-${crew_name}-${agent_id}
    restart: unless-stopped
    environment:
      - AGENT_ID=${agent_id}
      - MODEL=ollama/qwen3:0.6b
      - CREW_CHANNEL=${crew_name}
      - OPENCLAW_GATEWAY_URL=ws://openclaw-gateway:18789
      - OPENCLAW_GATEWAY_TOKEN=\${OPENCLAW_GATEWAY_TOKEN}
    volumes:
      - ${AGENTS_DIR}/${agent_id}/data:/app/data
      - ${AGENTS_DIR}/${agent_id}/config:/app/config
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
    done
    
    success "Added crew '$crew_name' with ${#agents_in_crew[@]} agent(s) to docker-compose.yml"
}

# =============================================================================
# Main
# =============================================================================

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
                CREW_NAME="$2"
                shift 2
                ;;
            -h|--help)
                usage
                ;;
            *)
                if [[ -z "${CREW_IMAGE:-}" ]]; then
                    CREW_IMAGE="$1"
                else
                    error "Unexpected argument: $1"
                    usage
                    exit 1
                fi
                shift
                ;;
        esac
    done
}

parse_args "$@"

if [[ -z "${CREW_IMAGE:-}" ]]; then
    error "No crew image specified"
    usage
    exit 1
fi

# Create import directory if it doesn't exist
safe_mkdir "$IMPORT_DIR" || fatal "Failed to create import directory: $IMPORT_DIR"

# Import the crew
import_crew "$CREW_IMAGE" "$IMPORT_DIR" "${CREW_NAME:-}"

exit 0
