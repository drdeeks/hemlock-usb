#!/usr/bin/env bash
# =============================================================================
# memory-log.sh — Append to today's daily memory file
# =============================================================================
#
# Usage:
#   bash scripts/memory-log.sh "Completed auth-login.sh fix across all agents"
#   bash scripts/memory-log.sh -t "TODO" "Need to review backup timer"
#   bash scripts/memory-log.sh -t "LESSON" "Always use -it with docker exec"
#
# Writes to: $HERMES_HOME/memory/YYYY-MM-DD.md
# Creates the file with header if it doesn't exist.
# NEVER deletes old daily files.
# =============================================================================

set -euo pipefail

WS="${HERMES_HOME:-.}"
TAG=""

# Parse optional -t flag
while getopts "t:" opt; do
    case $opt in
        t) TAG="$OPTARG" ;;
        *) echo "Usage: memory-log.sh [-t TAG] \"message\""; exit 1 ;;
    esac
done
shift $((OPTIND - 1))

MESSAGE="${1:?Usage: memory-log.sh [-t TAG] \"message\"}"

TODAY=$(date +%Y-%m-%d)
TIME=$(date +%H:%M)
FILE="$WS/memory/$TODAY.md"

mkdir -p "$WS/memory"

# Create file with header if new
if [ ! -f "$FILE" ]; then
    echo "# Memory — $TODAY" > "$FILE"
    echo "" >> "$FILE"
fi

# Append entry
if [ -n "$TAG" ]; then
    echo "- **[$TAG]** $TIME — $MESSAGE" >> "$FILE"
else
    echo "- $TIME — $MESSAGE" >> "$FILE"
fi

echo "Logged to memory/$TODAY.md"
