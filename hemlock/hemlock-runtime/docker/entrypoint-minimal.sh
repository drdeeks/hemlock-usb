#!/usr/bin/env bash
# Minimal entrypoint: gateway daemon + brain MCP. Nothing else.
# The gateway fronts platforms and spawns the brain MCP (stdio) from its config.
set -e

echo "[minimal] generating gateway config..."
python3 /opt/hermes/docker/gen-openclaw-config.py 2>&1 | sed 's/^/[minimal]   /' || \
    echo "[minimal] config generation skipped — gateway starts unconfigured"

echo "[minimal] starting gateway daemon..."
exec openclaw gateway run --allow-unconfigured
