#!/bin/bash
# =============================================================================
# OpenClaw Hermes Agent Entrypoint
# 
# Connects Hermes agent to OpenClaw Gateway and starts the agent loop
# Supports both individual agent mode and crew (multi-agent) mode
# =============================================================================

set -euo pipefail

echo "=========================================="
echo "  OpenClaw Hermes Agent Entrypoint"
echo "=========================================="
echo ""
echo "Configuration:"
echo "  Agent ID:       ${AGENT_ID:-not set}"
echo "  Model:          ${MODEL:-not set}"
echo "  Gateway URL:    ${OPENCLAW_GATEWAY_URL:-not set}"
echo "  Crew Channel:   ${CREW_CHANNEL:-none (individual mode)}"
echo ""

# Validate required environment variables
if [[ -z "${AGENT_ID:-}" ]]; then
    echo "ERROR: AGENT_ID environment variable is required"
    exit 1
fi

if [[ -z "${MODEL:-}" ]]; then
    echo "ERROR: MODEL environment variable is required"
    exit 1
fi

if [[ -z "${OPENCLAW_GATEWAY_URL:-}" ]]; then
    echo "ERROR: OPENCLAW_GATEWAY_URL environment variable is required"
    exit 1
fi

if [[ -z "${OPENCLAW_GATEWAY_TOKEN:-}" ]]; then
    echo "ERROR: OPENCLAW_GATEWAY_TOKEN environment variable is required"
    exit 1
fi

# Determine if we're in crew mode
if [[ -n "${CREW_CHANNEL:-}" ]]; then
    echo "Mode: CREW (multi-agent collaboration)"
    echo "Crew Channel: $CREW_CHANNEL"
    echo ""
    
    # Connect to Gateway with crew channel
    echo "Connecting to OpenClaw Gateway with channel '$CREW_CHANNEL'..."
    hermes gateway connect \
      --url "$OPENCLAW_GATEWAY_URL" \
      --token "$OPENCLAW_GATEWAY_TOKEN" \
      --channel "$CREW_CHANNEL" &
    GATEWAY_PID=$!
    
    echo "Gateway connection started (PID: $GATEWAY_PID)"
    echo ""
    
    # Start Hermes agent in crew mode
    echo "Starting Hermes agent in crew mode..."
    exec hermes --agent-id "$AGENT_ID" --model "$MODEL" --crew "$CREW_CHANNEL" --tui
else
    echo "Mode: INDIVIDUAL (single-agent)"
    echo ""
    
    # Connect to Gateway in individual mode
    echo "Connecting to OpenClaw Gateway..."
    hermes gateway connect \
      --url "$OPENCLAW_GATEWAY_URL" \
      --token "$OPENCLAW_GATEWAY_TOKEN" &
    GATEWAY_PID=$!
    
    echo "Gateway connection started (PID: $GATEWAY_PID)"
    echo ""
    
    # Start Hermes agent in individual mode
    echo "Starting Hermes agent in individual mode..."
    exec hermes --agent-id "$AGENT_ID" --model "$MODEL" --tui
fi

# This line should never be reached as exec replaces the process
# But we keep it as a fallback
kill $GATEWAY_PID 2>/dev/null || true
echo "Agent stopped"
