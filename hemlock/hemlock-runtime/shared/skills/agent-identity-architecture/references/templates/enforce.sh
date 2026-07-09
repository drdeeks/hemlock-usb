#!/usr/bin/env bash
# enforce.sh - Workspace structure enforcement
# Part of synthesis-1 tool-enforcement habit

set -euo pipefail

WORKSPACE="${WORKSPACE}"
AGENT_ID="${AGENT_ID:-synthesis-1}"

echo "[enforce] Enforcing workspace structure for $AGENT_ID..."

# Required directories
REQUIRED_DIRS=(
    "tools:755"
    "skills:755"
    "memory:755"
    ".secrets:700"
    ".agent:755"
    ".agent/habits:755"
    ".agent/logs:755"
    ".agent/metrics:755"
    ".agent/templates:755"
    ".agent/constitutions:755"
)

# Create directories with correct permissions
for entry in "${REQUIRED_DIRS[@]}"; do
    dir="${entry%:*}"
    perms="${entry#*:}"
    full_path="$WORKSPACE/$dir"
    
    if [[ ! -d "$full_path" ]]; then
        mkdir -p "$full_path"
        echo "[enforce] Created directory: $dir"
    fi
    chmod "$perms" "$full_path"
done

# Required tools
REQUIRED_TOOLS=(
    "enforce.sh"
    "secret.sh"
    "memory-log.sh"
    "memory-promote.sh"
    "TOOLS-GUIDE.md"
)

# Ensure tools exist
for tool in "${REQUIRED_TOOLS[@]}"; do
    tool_path="$WORKSPACE/tools/$tool"
    if [[ ! -f "$tool_path" ]]; then
        echo "[enforce] WARNING: Missing tool: $tool"
    fi
done

# Set file permissions
find "$WORKSPACE" -name "*.sh" -type f -exec chmod 755 {} \;
find "$WORKSPACE" -name "*.md" -type f -exec chmod 644 {} \;
find "$WORKSPACE/.secrets" -type f -exec chmod 600 {} \; 2>/dev/null || true

echo "[enforce] Workspace enforcement complete."
exit 0