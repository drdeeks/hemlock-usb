#!/bin/bash
# Hemlock Snapshot Helper Script
# Creates snapshots and automatically copies them to downloads directory

set -e

HEMLOCK_DIR="${HEMLOCK_DIR:-$(cd "$(dirname "$0")/.." && pwd)}"
SNAPS_DIR="${SNAPS_DIR:-$HOME/downloads/hemlock_snaps}"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)

# Ensure snaps directory exists
mkdir -p "$SNAPS_DIR"

# Function to create and store snapshot
create_snapshot() {
    local name="$1"
    local type="$2"  # source, image, or changes
    
    echo "Creating ${type} snapshot: ${name}"
    
    case "$type" in
        source)
            tar -czf "${HEMLOCK_DIR}/hemlock-${name}.tar.gz" \
                --exclude='*.tar' \
                --exclude='*.tar.gz' \
                --exclude='__pycache__' \
                --exclude='.git' \
                --exclude='runtime/*' \
                --exclude='agents/*' \
                --exclude='models/*' \
                --exclude='backups/*' \
                -C "$HEMLOCK_DIR" \
                docker/ health/ tools/ BOOTSTRAP_PROGRESS_CHECKLIST.md
            cp "${HEMLOCK_DIR}/hemlock-${name}.tar.gz" "${SNAPS_DIR}/"
            ;;
        image)
            local image_tag="$3"
            docker save "$image_tag" -o "${HEMLOCK_DIR}/openclaw-framework-${name}.tar"
            cp "${HEMLOCK_DIR}/openclaw-framework-${name}.tar" "${SNAPS_DIR}/"
            ;;
        changes)
            tar -cf - ${@:4} 2>/dev/null | gzip > "${HEMLOCK_DIR}/hemlock-${name}-changes.tar.gz"
            cp "${HEMLOCK_DIR}/hemlock-${name}-changes.tar.gz" "${SNAPS_DIR}/"
            ;;
    esac
    
    # Always update checklist
    cp "${HEMLOCK_DIR}/BOOTSTRAP_PROGRESS_CHECKLIST.md" "${SNAPS_DIR}/BOOTSTRAP_PROGRESS_CHECKLIST.md"
    
    echo "Snapshot created and stored in ${SNAPS_DIR}/"
    ls -lh "${SNAPS_DIR}/" | tail -5
}

# Main
case "${1:-}" in
    source)
        create_snapshot "${2:-source_$TIMESTAMP}" "source"
        ;;
    image)
        create_snapshot "${2:-image_$TIMESTAMP}" "image" "${3:-openclaw/framework:stable}"
        ;;
    changes)
        shift
        create_snapshot "changes_$TIMESTAMP" "changes" "$@"
        ;;
    checklist)
        cp "${HEMLOCK_DIR}/BOOTSTRAP_PROGRESS_CHECKLIST.md" "${SNAPS_DIR}/BOOTSTRAP_PROGRESS_CHECKLIST.md"
        echo "Checklist updated in ${SNAPS_DIR}/"
        ;;
    *)
        echo "Usage: $0 {source|image|changes|checklist} [name] [image_tag] [files...]"
        echo ""
        echo "Commands:"
        echo "  source [name]              - Create source tree snapshot"
        echo "  image [name] [tag]         - Create Docker image snapshot"
        echo "  changes [files...]         - Create snapshot of specific files"
        echo "  checklist                  - Update checklist copy only"
        exit 1
        ;;
esac
