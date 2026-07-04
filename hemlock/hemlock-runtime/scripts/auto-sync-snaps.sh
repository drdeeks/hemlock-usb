#!/bin/bash
# Auto-sync snapshots to downloads directory
# Run this after creating any snapshot files in the hemlock directory

HEMLOCK_DIR="${HEMLOCK_DIR:-$(cd "$(dirname "$0")/.." && pwd)}"
SNAPS_DIR="${SNAPS_DIR:-$HOME/downloads/hemlock_snaps}"

# Ensure snaps directory exists
mkdir -p "$SNAPS_DIR"

# Sync all snapshot files
rsync -av --include='*.tar' --include='*.tar.gz' --include='BOOTSTRAP_PROGRESS_CHECKLIST.md' --exclude='*' \
    "$HEMLOCK_DIR/" "$SNAPS_DIR/"

echo "Synced $(ls -1 "$SNAPS_DIR" | wc -l) files to $SNAPS_DIR"
