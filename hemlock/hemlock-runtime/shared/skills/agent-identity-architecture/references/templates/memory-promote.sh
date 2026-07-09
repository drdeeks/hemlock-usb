#!/usr/bin/env bash
# memory-promote.sh - Promote daily memories to long-term memory
# Part of synthesis-1 tool-enforcement habit

set -euo pipefail

WORKSPACE="${WORKSPACE}"
MEMORY_DIR="$WORKSPACE/memory"
DAILY_DIR="$MEMORY_DIR/daily"
MEMORY_FILE="$MEMORY_DIR/MEMORY.md"
SOUL_FILE="$WORKSPACE/.agent/genesis.md"

usage() {
    echo "Usage: $0 [--dry-run]"
    echo "  Promotes daily memories to long-term MEMORY.md"
    echo "  --dry-run  Show what would be promoted without writing"
    exit 1
}

DRY_RUN=false
if [[ "${1:-}" == "--dry-run" ]]; then
    DRY_RUN=true
fi

mkdir -p "$MEMORY_DIR"

if [[ ! -f "$MEMORY_FILE" ]]; then
    cat > "$MEMORY_FILE" << 'EOF'
# MEMORY.md

Curated lessons and patterns.

---

## Lessons

EOF
fi

DATE=$(date +"%Y-%m-%d")
TIMESTAMP=$(date +"%Y-%m-%dT%H:%M:%S")

# Find daily notes to promote (older than 1 day)
PROMOTED_COUNT=0

for daily_file in "$DAILY_DIR"/*.md; do
    [[ -f "$daily_file" ]] || continue
    
    filename=$(basename "$daily_file")
    file_date="${filename%.md}"
    
    # Skip today's file
    [[ "$file_date" == "$(date +"%Y-%m-%d")" ]] && continue
    
    # Check if already promoted (simple check for date marker)
    if grep -q "### $file_date" "$MEMORY_FILE" 2>/dev/null; then
        continue
    fi
    
    content=$(cat "$daily_file")
    
    # Extract lessons/insights (lines containing LESSON, INSIGHT, DECISION)
    lessons=$(echo "$content" | grep -iE "(LESSON|INSIGHT|DECISION|PATTERN)" | head -10)
    
    if [[ -n "$lessons" ]]; then
        ENTRY="### $file_date ($TIMESTAMP)

$lessons

---"
        
        if [[ "$DRY_RUN" == "true" ]]; then
            echo "WOULD PROMOTE:"
            echo "$ENTRY"
            echo "---"
        else
            echo "$ENTRY" >> "$MEMORY_FILE"
        fi
        
        ((PROMOTED_COUNT++))
    fi
done

if [[ "$DRY_RUN" == "true" ]]; then
    echo "Dry run complete. $PROMOTED_COUNT entries would be promoted."
else
    echo "Promoted $PROMOTED_COUNT entries to $MEMORY_FILE"
fi