#!/bin/bash
# =============================================================================
# OpenClaw Enterprise Framework - Crew Export Script
# 
# Exports a crew as a self-contained Docker image with all agents and configurations
# 
# Usage:
#   ./scripts/docker/export-crew.sh my-crew
#   ./scripts/docker/export-crew.sh my-crew my-registry/my-crew:v1.0.0
#   ./scripts/docker/export-crew.sh --all
#   ./scripts/docker/export-crew.sh --all -p
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
CREWS_DIR="${CREWS_DIR:-${SOURCE_DIR}/crews}"
AGENTS_DIR="${AGENTS_DIR:-${SOURCE_DIR}/agents}"

# =============================================================================
# Functions
# =============================================================================

usage() {
    cat <<EOF
Usage: $(basename "$0") [OPTIONS] <crew-id> [tag]

Export an OpenClaw crew as a Docker image.

Options:
  -a, --all           Export all crews
  -r, --registry REG  Target registry (default: ${REGISTRY})
  -v, --version VER   Version tag (default: ${VERSION})
  -s, --skip-agents   Skip exporting individual agent data
  -p, --push          Push to registry after building
  -h, --help          Show this help message

Examples:
  $(basename "$0") my-crew
  $(basename "$0") my-crew my-registry/my-crew:v1.0.0
  $(basename "$0") -a
  $(basename "$0") -a -p
  $(basename "$0") -r my-registry.com/openclaw my-crew
EOF
    exit 0
}

export_crew() {
    local crew_id="$1"
    local tag="$2"
    local push="$3"
    local skip_agents="$4"
    
    local crew_dir="${CREWS_DIR}/${crew_id}"
    
    if [[ ! -d "$crew_dir" ]]; then
        fatal "Crew directory not found: $crew_dir"
    fi
    
    if [[ ! -f "$crew_dir/crew.yaml" ]]; then
        fatal "Crew config not found: $crew_dir/crew.yaml"
    fi
    
    # Determine image name and tags
    if [[ -z "$tag" ]]; then
        tag="${crew_id}:${VERSION}"
    fi
    
    local image_name
    if [[ "$tag" == *:* ]]; then
        image_name="$tag"
    else
        image_name="${REGISTRY}/crew-${tag}:${VERSION}"
    fi
    
    log "Exporting crew '${crew_id}' as '${image_name}'..."
    
    # Read crew.yaml to get agent list
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
    
    log "Crew contains agents: ${agents_in_crew[*]}"
    
    # Validate all agents exist
    local missing_agents=()
    for agent_id in "${agents_in_crew[@]}"; do
        if [[ ! -d "${AGENTS_DIR}/${agent_id}" ]]; then
            missing_agents+=("$agent_id")
        fi
    done
    
    if [[ ${#missing_agents[@]} -gt 0 ]]; then
        warn "Missing agent directories: ${missing_agents[*]}"
        if [[ "$skip_agents" != "true" ]]; then
            fatal "Cannot export crew with missing agents"
        fi
    fi
    
    # Build the crew image
    docker build \
        --build-arg CREW_ID="${crew_id}" \
        --build-arg CREW_SOURCE_DIR="./crews" \
        --build-arg INCLUDE_AGENTS="${skip_agents:-false}" \
        -t "${image_name}" \
        -t "${image_name%:*}:latest" \
        -f Dockerfile.crew \
        . \
        || fatal "Failed to build crew image for ${crew_id}"
    
    success "Built crew image: ${image_name}"
    
    # Push if requested
    if [[ "$push" == "true" ]]; then
        log "Pushing to registry..."
        docker push "${image_name}" || warn "Failed to push ${image_name}"
        docker push "${image_name%:*}:latest" || warn "Failed to push latest tag"
        success "Pushed ${image_name} to registry"
    fi
}

export_all_crews() {
    local push="$1"
    local skip_agents="$2"
    
    log "Exporting all crews..."
    
    if [[ ! -d "$CREWS_DIR" ]]; then
        fatal "Crews directory not found: $CREWS_DIR"
    fi
    
    local crew_count=0
    for crew_dir in "$CREWS_DIR"/*/; do
        local crew_id=$(basename "$crew_dir")
        if [[ -f "$crew_dir/crew.yaml" ]]; then
            export_crew "$crew_id" "" "$push" "$skip_agents" || return 1
            crew_count=$((crew_count + 1))
        fi
    done
    
    if [[ $crew_count -eq 0 ]]; then
        warn "No crews found in $CREWS_DIR"
    else
        success "Exported $crew_count crew(s)"
    fi
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
            -s|--skip-agents)
                SKIP_AGENTS=true
                shift
                ;;
            -p|--push)
                PUSH=true
                shift
                ;;
            -h|--help)
                usage
                ;;
            *)
                if [[ -z "${CREW_ID:-}" ]]; then
                    CREW_ID="$1"
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
    export_all_crews "${PUSH:-false}" "${SKIP_AGENTS:-false}"
else
    if [[ -z "${CREW_ID:-}" ]]; then
        error "No crew ID specified. Use -a/--all to export all crews."
        usage
        exit 1
    fi
    export_crew "${CREW_ID}" "${TAG:-}" "${PUSH:-false}" "${SKIP_AGENTS:-false}"
fi

exit 0
