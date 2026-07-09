#!/usr/bin/env bash
# crew-sync.sh - Sync knowledge across agents and rebuild indexes
set -euo pipefail

show_help() {
    cat <<'EOF'
Crew Sync - Synchronize knowledge across agents and update indexes

Usage: bash crew-sync.sh [options]

Options:
  --crew-id <id>        Crew ID (auto-detect)
  --workspace <path>    Crew workspace (auto-detect)
  --full                Full sync (communications + agent knowledge + shared)
  --comms-only          Sync communications only
  --knowledge-only      Sync agent knowledge to shared only
  --reindex             Rebuild search index after sync
  --semantic            Rebuild semantic vectors (requires CREW_SEMANTIC_ENABLED=true)
  --help                Show this help

Example:
  bash crew-sync.sh --full --reindex
  bash crew-sync.sh --comms-only
  CREW_SEMANTIC_ENABLED=true bash crew-sync.sh --full --reindex --semantic
EOF
    exit 0
}

# Handle --help BEFORE any workspace detection
if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
    show_help
fi

# Auto-detect crew workspace
detect_crew_workspace() {
    local dir="$(pwd)"
    while [[ "$dir" != "/" ]]; do
        if [[ -f "$dir/crew.json" ]]; then
            echo "$dir"
            return 0
        fi
        dir="$(dirname "$dir")"
    done
    return 1
}

CREW_WORKSPACE="${CREW_WORKSPACE:-}"
if [[ -z "$CREW_WORKSPACE" ]]; then
    CREW_WORKSPACE="$(detect_crew_workspace)" || {
        echo "ERROR: Not in a crew workspace"
        exit 1
    }
fi

CREW_ID="$(jq -r .crew_id "$CREW_WORKSPACE/crew.json" 2>/dev/null || echo "unknown")"
CREW_MODE="$(jq -r .crew_type "$CREW_WORKSPACE/crew.json" 2>/dev/null || echo "development")"
SHARED_DIR="$CREW_WORKSPACE/shared"
AGENTS_DIR="$CREW_WORKSPACE/agents"
INDEX_DIR="$CREW_WORKSPACE/index"

FULL_SYNC=false
COMMS_ONLY=false
KNOWLEDGE_ONLY=false
REINDEX=false
SEMANTIC=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --help|-h) show_help ;;
        --crew-id) CREW_ID="$2"; shift 2 ;;
        --workspace) CREW_WORKSPACE="$2"; shift 2 ;;
        --full) FULL_SYNC=true; shift ;;
        --comms-only) COMMS_ONLY=true; shift ;;
        --knowledge-only) KNOWLEDGE_ONLY=true; shift ;;
        --reindex) REINDEX=true; shift ;;
        --semantic) SEMANTIC=true; shift ;;
        *) echo "ERROR: Unknown option: $1"; show_help ;;
    esac
done

# Default to full sync if no specific mode
if [[ "$COMMS_ONLY" == "false" && "$KNOWLEDGE_ONLY" == "false" && "$FULL_SYNC" == "false" ]]; then
    FULL_SYNC=true
fi

echo "=== Crew Sync: $CREW_ID ==="
echo "  Mode: $CREW_MODE"
if [[ "$FULL_SYNC" == "true" ]]; then
    echo "  Sync: Full (comms + knowledge + reindex)"
elif [[ "$COMMS_ONLY" == "true" ]]; then
    echo "  Sync: Communications only"
elif [[ "$KNOWLEDGE_ONLY" == "true" ]]; then
    echo "  Sync: Knowledge only"
fi
[[ "$REINDEX" == "true" ]] && echo "  Reindex: Yes"
[[ "$SEMANTIC" == "true" ]] && echo "  Semantic: Yes"
echo ""

# Sync communications
if [[ "$FULL_SYNC" == "true" || "$COMMS_ONLY" == "true" ]]; then
    echo "  → Syncing communications..."
    bash "$HOME/.hermes/skills/devops/crew-knowledge-system/scripts/crew-comm.sh" sync
    echo "    ✅ Communications synced to shared/documents/communications"
fi

# Sync agent knowledge to shared (production mode)
if [[ "$CREW_MODE" == "production" && ("$FULL_SYNC" == "true" || "$KNOWLEDGE_ONLY" == "true") ]]; then
    echo "  → Syncing agent knowledge to shared..."
    synced=0
    for agent_dir in "$AGENTS_DIR"/*/; do
        [[ -d "$agent_dir" ]] || continue
        agent_id=$(basename "$agent_dir")
        agent_knowledge="$agent_dir/knowledge"
        shared_knowledge="$SHARED_DIR/knowledge"
        
        if [[ -d "$agent_knowledge" ]]; then
            # Copy new/updated files from agent to shared (by category)
            for cat_dir in "$agent_knowledge"/*/; do
                [[ -d "$cat_dir" ]] || continue
                cat_name=$(basename "$cat_dir")
                mkdir -p "$shared_knowledge/$cat_name"
                
                # Copy with agent prefix to avoid conflicts
                for file in "$cat_dir"/*.md; do
                    [[ -f "$file" ]] || continue
                    base=$(basename "$file")
                    # Check if file is newer than shared version
                    shared_file="$shared_knowledge/$cat_name/${agent_id}-${base}"
                    if [[ ! -f "$shared_file" || "$file" -nt "$shared_file" ]]; then
                        cp "$file" "$shared_file"
                        ((synced++))
                    fi
                done
            done
        fi
    done
    echo "    ✅ Synced $synced agent knowledge files to shared"
fi

# Rebuild index
if [[ "$REINDEX" == "true" ]]; then
    echo "  → Rebuilding search index..."
    REINDEX_ARGS="rebuild"
    [[ "$SEMANTIC" == "true" ]] && REINDEX_ARGS="rebuild --semantic"
    CREW_WORKSPACE="$CREW_WORKSPACE" bash "$HOME/.hermes/skills/devops/crew-knowledge-system/scripts/crew-indexer.sh" $REINDEX_ARGS
    echo "    ✅ Search index rebuilt"
fi

# Update crew manifest with sync timestamp
python3 -c "
import json, datetime
with open('$CREW_WORKSPACE/crew.json') as f:
    crew = json.load(f)
crew['last_synced'] = datetime.datetime.utcnow().isoformat() + 'Z'
crew['sync_mode'] = 'full' if $FULL_SYNC else ('comms' if $COMMS_ONLY else 'knowledge')
with open('$CREW_WORKSPACE/crew.json', 'w') as f:
    json.dump(crew, f, indent=2)
"

echo ""
echo "=== Sync Complete ==="
echo "  Crew: $CREW_ID"
echo "  Last synced: $(date -u +%Y-%m-%dT%H:%M:%SZ)"