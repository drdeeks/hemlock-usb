#!/usr/bin/env bash
# =============================================================================
# memory-promote.sh — Review daily notes and promote to MEMORY.md
# =============================================================================
#
# Usage:
#   bash scripts/memory-promote.sh                  # Review today + yesterday
#   bash scripts/memory-promote.sh 2026-04-20       # Specific date
#   bash scripts/memory-promote.sh --week           # Last 7 days
#
# Shows daily notes and prompts for which entries to promote to MEMORY.md.
# NEVER deletes daily files — they are preserved forever.
# =============================================================================

set -euo pipefail

WS="${HERMES_HOME:-.}"
MEMORY_DIR="$WS/memory"
LONG_TERM="$WS/MEMORY.md"

mkdir -p "$MEMORY_DIR"

# Ensure MEMORY.md exists
if [ ! -f "$LONG_TERM" ]; then
    cat > "$LONG_TERM" << 'EOF'
# MEMORY.md — Long-Term Curated Memory

Distilled wisdom from daily notes. Updated periodically.
Daily raw logs stay in memory/YYYY-MM-DD.md forever.

---

## Key Decisions

## Lessons Learned

## Active Context

## Recurring Patterns

EOF
    echo "Created MEMORY.md"
fi

# Determine date range
DATES=()
if [ "${1:-}" = "--week" ]; then
    for i in $(seq 0 6); do
        DATES+=("$(date -d "$i days ago" +%Y-%m-%d 2>/dev/null || date -v-${i}d +%Y-%m-%d 2>/dev/null)")
    done
elif [ -n "${1:-}" ]; then
    DATES=("$1")
else
    DATES=("$(date +%Y-%m-%d)")
    DATES+=("$(date -d "1 day ago" +%Y-%m-%d 2>/dev/null || date -v-1d +%Y-%m-%d 2>/dev/null)")
fi

echo "=== Memory Promotion Review ==="
echo ""

FOUND=0
for DATE in "${DATES[@]}"; do
    FILE="$MEMORY_DIR/$DATE.md"
    if [ -f "$FILE" ]; then
        echo "--- $DATE ---"
        cat "$FILE"
        echo ""
        FOUND=$((FOUND + 1))
    fi
done

if [ "$FOUND" -eq 0 ]; then
    echo "No daily files found for the selected dates."
    echo "Files checked: ${DATES[*]}"
    echo ""
    echo "Daily notes live at: memory/YYYY-MM-DD.md"
    echo "Log entries with: bash scripts/memory-log.sh \"message\""
    exit 0
fi

echo "=== End of Daily Notes ==="
echo ""
echo "To promote entries to MEMORY.md:"
echo "  1. Read the entries above"
echo "  2. Add key insights to $LONG_TERM"
echo "  3. Daily files are NEVER deleted — they stay in memory/ forever"
echo ""
echo "Log new entries with:"
echo "  bash scripts/memory-log.sh \"what happened\""
echo "  bash scripts/memory-log.sh -t LESSON \"what I learned\""
echo "  bash scripts/memory-log.sh -t TODO \"what needs doing\""
