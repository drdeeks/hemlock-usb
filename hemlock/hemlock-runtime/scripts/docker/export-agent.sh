#!/bin/bash
# =============================================================================
# OpenClaw Enterprise Framework - Agent Export Script
# 
# Exports an agent as a self-contained Docker image
# 
# Usage:
#   ./scripts/docker/export-agent.sh test-e2e-agent
#   ./scripts/docker/export-agent.sh test-e2e-agent my-registry/my-agent:v1.0.0
#   ./scripts/docker/export-agent.sh --all
# =============================================================================

set -uo pipefail

# Load common library
SOURCE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "${SOURCE_DIR}/lib/common.sh"

# =============================================================================
# Configuration
# =============================================================================
REGISTRY="${REGISTRY:-docker.io/openclaw}"
VERSION="${FRAMEWORK_VERSION:-1.0.0}"

# =============================================================================
# Functions
# =============================================================================

usage() {
    cat <<EOF
Usage: $(basename "$0") [OPTIONS] <agent-id> [tag]

Export an OpenClaw agent as a Docker image.

Options:
  -a, --all           Export all agents
  -r, --registry REG  Target registry (default: ${REGISTRY})
  -v, --version VER   Version tag (default: ${VERSION})
  -p, --push          Push to registry after building
  -h, --help          Show this help message

Examples:
  $(basename "$0") test-e2e-agent
  $(basename "$0") test-e2e-agent my-registry/my-agent:v1.0.0
  $(basename "$0") -a
  $(basename "$0") -a -p
  $(basename "$0") -r my-registry.com/openclaw test-e2e-agent
EOF
    exit 0
}

export_agent() {
    local agent_id="$1"
    local tag="$2"
    local push="$3"
    
    local agent_dir="agents/${agent_id}"
    
    if [[ ! -d "$agent_dir" ]]; then
        fatal "Agent directory not found: $agent_dir"
    fi
    
    if [[ ! -f "$agent_dir/config.yaml" ]]; then
        fatal "Agent config not found: $agent_dir/config.yaml"
    fi
    
    # Get model from config
    local model
    model=$(grep "^  model:" "$agent_dir/config.yaml" 2>/dev/null | head -1 | awk '{print $2}' | tr -d '"' || echo "ollama/qwen3:0.6b")
    
    # Determine image name and tags
    if [[ -z "$tag" ]]; then
        tag="${agent_id}:${VERSION}"
    fi
    
    local image_name
    if [[ "$tag" == *:* ]]; then
        # Tag includes registry or has its own tag format
        image_name="$tag"
    else
        image_name="${REGISTRY}/agent-${tag}:${VERSION}"
    fi
    
    log "Exporting agent '${agent_id}' as '${image_name}'..."
    
    # Build the export image
    docker build \
        --build-arg AGENT_ID="${agent_id}" \
        --build-arg AGENT_SOURCE_DIR="./agents" \
        --build-arg MODEL="${model}" \
        -t "${image_name}" \
        -t "${image_name%:*}:latest" \
        -f Dockerfile.export \
        . \
        || fatal "Failed to build export image for ${agent_id}"
    
    success "Built export image: ${image_name}"
    
    # Push if requested
    if [[ "$push" == "true" ]]; then
        log "Pushing to registry..."
        docker push "${image_name}" || warn "Failed to push ${image_name}"
        docker push "${image_name%:*}:latest" || warn "Failed to push latest tag"
        success "Pushed ${image_name} to registry"
    fi
}

export_all_agents() {
    local push="$1"
    
    log "Exporting all agents..."
    
    for agent_dir in agents/*/; do
        local agent_id=$(basename "$agent_dir")
        if [[ -f "$agent_dir/config.yaml" ]]; then
            export_agent "$agent_id" "" "$push" || return 1
        fi
    done
}

# =============================================================================
# Main
# =============================================================================

parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -a|--all)
                EXPORT_ALL=true
                shift
                ;;
            -r|--registry)
                REGISTRY="$2"
                shift 2
                ;;
            -v|--version)
                VERSION="$2"
                shift 2
                ;;
            -p|--push)
                PUSH=true
                shift
                ;;
            -h|--help)
                usage
                ;;
            *)
                if [[ -z "${AGENT_ID:-}" ]]; then
                    AGENT_ID="$1"
                elif [[ -z "${TAG:-}" ]]; then
                    TAG="$1"
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

if [[ "${EXPORT_ALL:-false}" == "true" ]]; then
    export_all_agents "${PUSH:-false}"
else
    if [[ -z "${AGENT_ID:-}" ]]; then
        error "No agent ID specified. Use -a/--all to export all agents."
        usage
        exit 1
    fi
    export_agent "${AGENT_ID}" "${TAG:-}" "${PUSH:-false}"
fi

exit 0
