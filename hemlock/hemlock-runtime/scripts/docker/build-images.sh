#!/bin/bash
# =============================================================================
# OpenClaw Enterprise Framework - Docker Image Build Script
# 
# Builds all Docker images for the framework
# Usage:
#   ./scripts/docker/build-images.sh          # Build all images
#   ./scripts/docker/build-images.sh framework  # Build only framework
#   ./scripts/docker/build-images.sh agent     # Build only agent image
#   ./scripts/docker/build-images.sh export    # Build export image
#   ./scripts/docker/build-images.sh push      # Build and push all images
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

IMAGE_FRAMEWORK="${REGISTRY}/enterprise-framework"
IMAGE_AGENT="${REGISTRY}/agent"
IMAGE_EXPORT="${REGISTRY}/agent-export"

# =============================================================================
# Functions
# =============================================================================

build_framework() {
    log "Building framework image..."
    
    docker build \
        --target framework \
        -t "${IMAGE_FRAMEWORK}:${VERSION}" \
        -t "${IMAGE_FRAMEWORK}:latest" \
        -f Dockerfile \
        . \
        || fatal "Failed to build framework image"
    
    success "Framework image built: ${IMAGE_FRAMEWORK}:${VERSION}"
}

build_agent() {
    local agent_id="${1:-test-e2e-agent}"
    local model="${2:-${DEFAULT_AGENT_MODEL:-ollama/qwen3:0.6b}}"
    
    log "Building agent image for ${agent_id}..."
    
    docker build \
        --build-arg AGENT_ID="${agent_id}" \
        --build-arg MODEL="${model}" \
        -t "${IMAGE_AGENT}-${agent_id}:${VERSION}" \
        -t "${IMAGE_AGENT}-${agent_id}:latest" \
        -f Dockerfile.agent \
        . \
        || fatal "Failed to build agent image for ${agent_id}"
    
    success "Agent image built: ${IMAGE_AGENT}-${agent_id}:${VERSION}"
}

build_export() {
    local agent_id="${1:-test-e2e-agent}"
    
    log "Building export image for ${agent_id}..."
    
    docker build \
        --build-arg AGENT_ID="${agent_id}" \
        --build-arg AGENT_SOURCE_DIR="./agents" \
        -t "${IMAGE_EXPORT}-${agent_id}:${VERSION}" \
        -t "${IMAGE_EXPORT}-${agent_id}:latest" \
        -f Dockerfile.export \
        . \
        || fatal "Failed to build export image for ${agent_id}"
    
    success "Export image built: ${IMAGE_EXPORT}-${agent_id}:${VERSION}"
}

build_all_agents() {
    log "Building all agent images..."
    
    # Build each agent defined in the framework
    for agent_dir in agents/*/; do
        local agent_id=$(basename "${agent_dir}")
        if [[ -f "${agent_dir}config.yaml" ]]; then
            build_agent "${agent_id}" || return 1
        fi
    done
}

push_images() {
    log "Pushing all images to registry..."
    
    # Push framework image
    docker push "${IMAGE_FRAMEWORK}:${VERSION}" || warn "Failed to push framework image"
    docker push "${IMAGE_FRAMEWORK}:latest" || warn "Failed to push framework latest"
    
    # Push agent images
    for agent_dir in agents/*/; do
        local agent_id=$(basename "${agent_dir}")
        docker push "${IMAGE_AGENT}-${agent_id}:${VERSION}" || warn "Failed to push ${agent_id} image"
        docker push "${IMAGE_AGENT}-${agent_id}:latest" || warn "Failed to push ${agent_id} latest"
    done
    
    success "All images pushed to registry"
}

list_images() {
    log "Listing built images..."
    docker images | grep -E "${REGISTRY}|openclaw" || echo "No OpenClaw images found"
}

# =============================================================================
# Main
# =============================================================================

case "${1:-}" in
    "framework")
        build_framework
        list_images
        ;;
    "agent")
        build_agent "${2:-test-e2e-agent}"
        list_images
        ;;
    "export")
        build_export "${2:-test-e2e-agent}"
        list_images
        ;;
    "agents"|"all-agents")
        build_all_agents
        list_images
        ;;
    "push")
        build_framework
        build_all_agents
        push_images
        list_images
        ;;
    "list")
        list_images
        ;;
    "")
        log "Building all images..."
        build_framework
        build_all_agents
        list_images
        log ""
        log "Build complete! Use 'docker images' to view built images."
        log "To push to registry: ./scripts/docker/build-images.sh push"
        ;;
    *)
        error "Unknown command: ${1}"
        echo ""
        echo "Usage:"
        echo "  ${0}          # Build all images"
        echo "  ${0} framework  # Build only framework"
        echo "  ${0} agent     # Build only default agent"
        echo "  ${0} agent <id> # Build specific agent"
        echo "  ${0} export    # Build export image"
        echo "  ${0} agents    # Build all agents"
        echo "  ${0} push      # Build and push all images"
        echo "  ${0} list      # List built images"
        exit 1
        ;;
esac

exit 0
