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

# ── Skills (CL-045) ───────────────────────────────────────────────────────────
# /skills is a named volume — empty on first start. Seed it with the baked
# kernel (cp -a; the slim image has no rsync), then start the self-healing
# updater to pull the rest from github + operator-added sources. Set
# SKILLS_UPDATE_ENABLED=0 to stay fully offline (kernel only).
if [ -d /opt/skills_seed ] && [ ! -f /skills/.hemlock_skills_seeded ]; then
    echo "[minimal] seeding /skills from the baked kernel set (first start)"
    cp -a /opt/skills_seed/. /skills/ 2>/dev/null || echo "[minimal]   seed copy incomplete"
    date -Iseconds > /skills/.hemlock_skills_seeded
fi
UPDATER="/opt/hermes/docker/skills-auto-update.sh"
if [ "${SKILLS_UPDATE_ENABLED:-1}" = "1" ] && [ -x "$UPDATER" ]; then
    echo "[minimal] starting skills auto-updater (supervised; SKILLS_UPDATE_ENABLED=0 to disable)"
    "$UPDATER" --supervise >>/logs/skills-sync.log 2>&1 &
fi

echo "[minimal] starting gateway daemon..."
exec openclaw gateway run --allow-unconfigured
