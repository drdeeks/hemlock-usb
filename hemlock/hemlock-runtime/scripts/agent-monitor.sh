#!/bin/bash
# Agent Monitoring Script

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/helpers.sh"

# Check arguments
if [ $# -lt 1 ]; then
    echo "Usage: $0 <agent_id> [--follow]"
    exit 1
fi

AGENT_ID=$1
FOLLOW=${2:-}

# Validate agent
echo "Checking agent $AGENT_ID..."
if ! agent_exists "$AGENT_ID"; then
    echo "Error: Agent $AGENT_ID does not exist"
    exit 1
fi

# Get container name
CONTAINER_NAME=$(get_agent_container "$AGENT_ID")

# Check if agent is running
if ! is_service_running "$CONTAINER_NAME"; then
    echo "Agent $AGENT_ID is not running"
    exit 0
fi

# Show container status
echo "============================================="
echo " Agent $AGENT_ID Status"
echo "============================================="

docker ps --filter "name=$CONTAINER_NAME" --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"

echo "\nContainer Stats:"
docker stats --no-stream "$CONTAINER_NAME" | head -n 5

echo "\nContainer Logs:"
if [ "$FOLLOW" == "--follow" ]; then
    docker logs -f "$CONTAINER_NAME"
else
    docker logs --tail 50 "$CONTAINER_NAME"
fi