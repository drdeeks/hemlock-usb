#!/bin/bash
# =============================================================================
# Agent Runner Script - Spawns agent containers with dynamic configuration
# =============================================================================

set -euo pipefail

# Usage function
usage() {
    cat <<EOF
Usage: $(basename "$0") <AGENT_ID> [OVERRIDE...]

Spawns an agent container with the specified ID.

Arguments:
  AGENT_ID    Unique identifier for the agent
  OVERRIDE    Environment overrides in VARIABLE=value format

Examples:
  $(basename "$0") my-agent
  $(basename "$0") my-agent MODEL_BACKEND=ollama DEFAULT_MODEL=codellama
EOF
    exit 1
}

# Check for .env file
if [[ ! -f .env ]]; then
    echo "Error: .env file not found. Copy .env.template to .env and configure."
    exit 1
fi

# Source environment
set -a
source .env
set +a

# Validate agent ID
[[ -z "${1:-}" ]] && usage
AGENT_ID="$1"
shift

# Process overrides
while [[ $# -gt 0 ]]; do
    export "$1"
    shift
done

# Construct paths
export AGENT_ID
AGENT_PATH="${AGENTS_ROOT}/${AGENT_ID}"
AGENT_APP_PATH="${AGENT_PATH}/${AGENT_APP_DIR_NAME}"
AGENT_DATA_PATH="${AGENT_PATH}/${AGENT_DATA_DIR_NAME}"
AGENT_CONFIG_PATH="${AGENT_PATH}/${AGENT_CONFIG_DIR_NAME}"

# Create directories
mkdir -p "$AGENT_APP_PATH" "$AGENT_DATA_PATH" "$AGENT_CONFIG_PATH"
mkdir -p "$LOGS_ROOT"

# Validate model backend
case "$MODEL_BACKEND" in
    ollama)
        if ! curl -sf "${OLLAMA_HOST}/api/tags" > /dev/null 2>&1; then
            echo "Warning: Ollama backend unreachable at ${OLLAMA_HOST}"
        fi
        ;;
    llamacpp)
        if ! curl -sf "${LLAMACPP_HOST}/health" > /dev/null 2>&1; then
            echo "Warning: llama.cpp backend unreachable at ${LLAMACPP_HOST}"
        fi
        ;;
    openrouter)
        if [[ -z "${OPENROUTER_API_KEY:-}" ]]; then
            echo "Error: OPENROUTER_API_KEY must be set for openrouter backend"
            exit 1
        fi
        ;;
esac

# Launch agent
echo "Launching agent: $AGENT_ID"
echo "  Backend: $MODEL_BACKEND"
echo "  Model: $DEFAULT_MODEL"
echo "  Path: $AGENT_PATH"

docker compose -p "$AGENT_ID" -f docker-compose.yml up -d --build

echo ""
echo "Agent '$AGENT_ID' started."
docker compose -p "$AGENT_ID" -f docker-compose.yml ps