#!/bin/bash
# =============================================================================
# Restore Script - Recover from backup archives
# =============================================================================

set -euo pipefail

if [[ -z "${1:-}" ]]; then
    echo "Usage: $(basename "$0") <BACKUP_FILENAME>"
    exit 1
fi

BACKUP_FILE="$1"

if [[ ! -f .env ]]; then
    echo "Error: .env file not found"
    exit 1
fi

source .env

if [[ ! -f "${BACKUP_ROOT}/${BACKUP_FILE}" ]]; then
    echo "Error: Backup file not found: ${BACKUP_ROOT}/${BACKUP_FILE}"
    exit 1
fi

echo "Warning: This will overwrite the current runtime."
echo "Type 'yes' to confirm: "
read -r confirm

if [[ "$confirm" != "yes" ]]; then
    echo "Restore cancelled."
    exit 0
fi

# Extract to temp location
TMPDIR=$(mktemp -d)
tar -xzf "${BACKUP_ROOT}/${BACKUP_FILE}" -C "$TMPDIR"

# Sync back to runtime
rsync -a --delete "$TMPDIR/$(basename "$BACKUP_FILE" .tar.gz)/" "${RUNTIME_ROOT}/"

# Clean up
rm -rf "$TMPDIR"

echo "Restore complete."