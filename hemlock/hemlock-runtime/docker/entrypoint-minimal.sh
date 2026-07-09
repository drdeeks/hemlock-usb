#!/usr/bin/env bash
# Minimal entrypoint: gateway daemon + brain MCP. Nothing else.
# The gateway fronts platforms and spawns the brain MCP (stdio) from its config.
set -e

echo "[minimal] generating gateway config..."
python3 /opt/hermes/docker/gen-openclaw-config.py 2>&1 | sed 's/^/[minimal]   /' || \
    echo "[minimal] config generation skipped — gateway starts unconfigured"

# Agent Identity Kit (CL-041): honor-only. If the operator placed a
# constitution in the data workspace, run the self-healing enforcer daemon so
# every tool call passes the identity gate. No constitution = no enforcement
# (baking a fail-closed gate with no policy would deny everything).
AIK_WS="${AGENT_WORKSPACE:-/data}"
if [ -f "$AIK_WS/.agent/constitution.yaml" ]; then
    echo "[minimal] identity kit: constitution found — starting enforcer (supervised)"
    AGENT_WORKSPACE="$AIK_WS" aik enforcer --supervise >>/logs/enforcer.log 2>&1 &
else
    echo "[minimal] identity kit: no constitution at $AIK_WS/.agent/ — enforcer idle (templates: /opt/aik/node/examples)"
fi

echo "[minimal] starting gateway daemon..."
exec openclaw gateway run --allow-unconfigured
