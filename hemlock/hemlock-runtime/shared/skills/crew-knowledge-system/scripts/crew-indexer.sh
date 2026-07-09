#!/usr/bin/env bash
# crew-indexer.sh - Crew knowledge indexer (local + optional semantic)
set -euo pipefail

show_help() {
    cat <<'EOF'
Crew Indexer - Index and search crew knowledge base

Usage: bash crew-indexer.sh <command> [options]

Commands:
  index                 Index all crew knowledge (default)
  index-agent <id>      Index specific agent's knowledge directory
  search <query>        Search crew knowledge (keyword + category filter)
  semantic-search <query>  Semantic vector search (requires TURBOPUFFER_API_KEY)
  hybrid-search <query>    Combined keyword + semantic search
  rebuild               Rebuild entire index from scratch
  rebuild --semantic    Rebuild with semantic vectors
  status                Show index status
  list [category]       List indexed documents

Options:
  --crew-id <id>        Crew ID (default: auto-detect from workspace)
  --workspace <path>    Crew workspace root (default: auto-detect)
  --category <cat>      Filter by category (architecture|api|ui|infra|process|debugging|research)
  --agent <id>          Filter by agent ID
  --tags <tags>         Filter by tags (comma-separated)
  --limit <n>           Limit results (default: 10)
  --help                Show this help

Environment:
  CREW_SEMANTIC_ENABLED    Enable semantic search (default: false)
  TURBOPUFFER_API_KEY      Turbopuffer API key for semantic search
  OPENAI_API_KEY           OpenAI API key for embeddings
  CREW_WORKSPACE           Crew workspace root

Example:
  bash crew-indexer.sh index
  bash crew-indexer.sh search "oauth authentication" --category architecture
  bash crew-indexer.sh index-agent ui-a1b2
  CREW_SEMANTIC_ENABLED=true bash crew-indexer.sh rebuild --semantic
  bash crew-indexer.sh semantic-search "how do we handle token expiry"
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
        echo "ERROR: Not in a crew workspace (no crew.json found)"
        exit 1
    }
fi

CREW_ID="$(jq -r .crew_id "$CREW_WORKSPACE/crew.json" 2>/dev/null || echo "unknown")"
CREW_TYPE="$(jq -r .crew_type "$CREW_WORKSPACE/crew.json" 2>/dev/null || echo "development")"
SHARED_DIR="$CREW_WORKSPACE/shared"
AGENTS_DIR="$CREW_WORKSPACE/agents"
INDEX_DIR="$CREW_WORKSPACE/index"

CREW_SEMANTIC_ENABLED="${CREW_SEMANTIC_ENABLED:-false}"
TURBOPUFFER_API_KEY="${TURBOPUFFER_API_KEY:-}"
OPENAI_API_KEY="${OPENAI_API_KEY:-}"

COMMAND="${1:-index}"
shift || true

# Parse options
FILTER_CATEGORY=""
FILTER_AGENT=""
FILTER_TAGS=""
LIMIT=10

while [[ $# -gt 0 ]]; do
    case $1 in
        --help|-h) show_help ;;
        --crew-id) CREW_ID="$2"; shift 2 ;;
        --workspace) CREW_WORKSPACE="$2"; shift 2 ;;
        --category) FILTER_CATEGORY="$2"; shift 2 ;;
        --agent) FILTER_AGENT="$2"; shift 2 ;;
        --tags) FILTER_TAGS="$2"; shift 2 ;;
        --limit) LIMIT="$2"; shift 2 ;;
        *) break ;;
    esac
done

# Ensure index directories exist
mkdir -p "$INDEX_DIR"/{by-category,by-agent,by-tag,semantic}

case "$COMMAND" in
    index)
        echo "=== Indexing Crew Knowledge: $CREW_ID ==="
        
        # Index shared knowledge
        echo "  Indexing shared knowledge..."
        index_directory "$SHARED_DIR/knowledge" "shared" "$CREW_TYPE"
        
        # Index agent knowledge directories
        if [[ -d "$AGENTS_DIR" ]]; then
            for agent_dir in "$AGENTS_DIR"/*/; do
                [[ -d "$agent_dir" ]] || continue
                agent_id=$(basename "$agent_dir")
                knowledge_dir="$agent_dir/knowledge"
                if [[ -d "$knowledge_dir" ]]; then
                    echo "  Indexing agent: $agent_id"
                    index_directory "$knowledge_dir" "$agent_id" "$CREW_TYPE"
                fi
            done
        fi
        
        # Update crew manifest
        update_manifest
        
        echo "  ✅ Indexing complete"
        ;;
        
    index-agent)
        AGENT_ID="${1:-}"
        if [[ -z "$AGENT_ID" ]]; then
            echo "ERROR: agent-id required for index-agent"
            exit 1
        fi
        
        agent_dir="$AGENTS_DIR/$AGENT_ID"
        if [[ ! -d "$agent_dir" ]]; then
            echo "ERROR: Agent not found: $AGENT_ID"
            exit 1
        fi
        
        knowledge_dir="$agent_dir/knowledge"
        if [[ ! -d "$knowledge_dir" ]]; then
            echo "ERROR: No knowledge directory for agent: $AGENT_ID"
            exit 1
        fi
        
        echo "=== Indexing Agent: $AGENT_ID ==="
        index_directory "$knowledge_dir" "$AGENT_ID" "$CREW_TYPE"
        update_manifest
        echo "  ✅ Agent index complete"
        ;;
        
    search)
        QUERY="${1:-}"
        if [[ -z "$QUERY" ]]; then
            echo "ERROR: search query required"
            exit 1
        fi
        
        echo "=== Searching Crew Knowledge: $CREW_ID ==="
        echo "  Query: $QUERY"
        [[ -n "$FILTER_CATEGORY" ]] && echo "  Category: $FILTER_CATEGORY"
        [[ -n "$FILTER_AGENT" ]] && echo "  Agent: $FILTER_AGENT"
        echo ""
        
        search_keyword "$QUERY"
        ;;
        
    semantic-search)
        if [[ "$CREW_SEMANTIC_ENABLED" != "true" ]]; then
            echo "ERROR: Semantic search not enabled. Set CREW_SEMANTIC_ENABLED=true"
            exit 1
        fi
        
        QUERY="${1:-}"
        if [[ -z "$QUERY" ]]; then
            echo "ERROR: search query required"
            exit 1
        fi
        
        echo "=== Semantic Search: $CREW_ID ==="
        echo "  Query: $QUERY"
        semantic_search "$QUERY"
        ;;
        
    hybrid-search)
        QUERY="${1:-}"
        if [[ -z "$QUERY" ]]; then
            echo "ERROR: search query required"
            exit 1
        fi
        
        echo "=== Hybrid Search: $CREW_ID ==="
        echo "  Query: $QUERY"
        search_keyword "$QUERY"
        if [[ "$CREW_SEMANTIC_ENABLED" == "true" ]]; then
            echo ""
            echo "--- Semantic Results ---"
            semantic_search "$QUERY"
        fi
        ;;
        
    rebuild)
        REBUILD_SEMANTIC=false
        if [[ "${1:-}" == "--semantic" ]]; then
            REBUILD_SEMANTIC=true
        fi
        
        echo "=== Rebuilding Crew Index: $CREW_ID ==="
        rm -rf "$INDEX_DIR"/{by-category,by-agent,by-tag,semantic}
        mkdir -p "$INDEX_DIR"/{by-category,by-agent,by-tag,semantic}
        
        bash "$0" index
        
        if [[ "$REBUILD_SEMANTIC" == "true" ]]; then
            if [[ "$CREW_SEMANTIC_ENABLED" != "true" ]]; then
                echo "ERROR: --semantic requires CREW_SEMANTIC_ENABLED=true"
                exit 1
            fi
            echo "  Building semantic vectors..."
            build_semantic_vectors
        fi
        
        echo "  ✅ Rebuild complete"
        ;;
        
    status)
        echo "=== Crew Index Status: $CREW_ID ==="
        if [[ -f "$INDEX_DIR/crew-manifest.json" ]]; then
            cat "$INDEX_DIR/crew-manifest.json" | jq .
        else
            echo "  No index manifest found"
        fi
        ;;
        
    list)
        CAT="${1:-}"
        list_documents "$CAT"
        ;;
        
    *)
        echo "ERROR: Unknown command: $COMMAND"
        show_help
        ;;
esac

# ============================================================================
# Internal Functions
# ============================================================================

index_directory() {
    local dir="$1"
    local source_id="$2"
    local crew_type="$3"
    
    if [[ ! -d "$dir" ]]; then
        return 0
    fi
    
    local doc_count=0
    
    # Find all markdown files
    while IFS= read -r -d '' file; do
        # Extract metadata from frontmatter
        local agent_id=$(extract_frontmatter "$file" "agent_id")
        local doc_type=$(extract_frontmatter "$file" "doc_type")
        local category=$(extract_frontmatter "$file" "category")
        local tags=$(extract_frontmatter "$file" "tags")
        local timestamp=$(extract_frontmatter "$file" "timestamp")
        local title=$(extract_title "$file")
        
        # Apply filters
        [[ -n "$FILTER_CATEGORY" && "$category" != "$FILTER_CATEGORY" ]] && continue
        [[ -n "$FILTER_AGENT" && "$agent_id" != "$FILTER_AGENT" ]] && continue
        [[ -n "$FILTER_TAGS" && ! $(echo "$tags" | grep -qE "$(echo "$FILTER_TAGS" | sed 's/,/|/g')") ]] && continue
        
        # Create document entry
        local doc_id="${source_id}-$(basename "$file" .md)"
        local entry=$(jq -n \
            --arg id "$doc_id" \
            --arg source "$source_id" \
            --arg agent "$agent_id" \
            --arg type "$doc_type" \
            --arg cat "$category" \
            --arg tags "$tags" \
            --arg ts "$timestamp" \
            --arg title "$title" \
            --arg path "$file" \
            '{id: $id, source: $source, agent_id: $agent, doc_type: $type, category: $cat, tags: $tags, timestamp: $ts, title: $title, path: $path}')
        
        # Index by category
        if [[ -n "$category" ]]; then
            echo "$entry" | jq -s '.[0]' >> "$INDEX_DIR/by-category/$category.jsonl"
        fi
        
        # Index by agent
        if [[ -n "$agent_id" ]]; then
            echo "$entry" | jq -s '.[0]' >> "$INDEX_DIR/by-agent/$agent_id.jsonl"
        fi
        
        # Index by tags
        IFS=',' read -ra TAG_ARRAY <<< "$tags"
        for tag in "${TAG_ARRAY[@]}"; do
            tag=$(echo "$tag" | xargs)  # trim
            [[ -n "$tag" ]] && echo "$entry" | jq -s '.[0]' >> "$INDEX_DIR/by-tag/$tag.jsonl"
        done
        
        ((doc_count++))
    done < <(find "$dir" -name "*.md" -print0 2>/dev/null)
    
    echo "    Indexed $doc_count documents from $source_id"
}

extract_frontmatter() {
    local file="$1"
    local key="$2"
    
    if [[ ! -f "$file" ]]; then
        echo ""
        return
    fi
    
    # Extract YAML frontmatter value
    awk -v k="$key" '
        /^---$/ { in_fm = !in_fm; next }
        in_fm && $0 ~ "^" k ":" { sub(/^[^:]*:[[:space:]]*/, ""); gsub(/^"|"$/, ""); print; exit }
    ' "$file"
}

extract_title() {
    local file="$1"
    # First h1 or filename
    awk '/^# / { sub(/^# /, ""); print; exit } END { if (!NR) print FILENAME }' "$file"
}

search_keyword() {
    local query="$1"
    local results=()
    
    # Search in all category indexes
    for cat_file in "$INDEX_DIR/by-category"/*.jsonl; do
        [[ -f "$cat_file" ]] || continue
        
        while IFS= read -r line; do
            [[ -z "$line" ]] && continue
            local title=$(echo "$line" | jq -r .title)
            local content=$(cat "$(echo "$line" | jq -r .path)" 2>/dev/null | head -200)
            
            if echo -e "$title\n$content" | grep -qi "$query"; then
                results+=("$line")
            fi
        done < "$cat_file"
    done
    
    # Apply filters
    local filtered=()
    for entry in "${results[@]}"; do
        local agent=$(echo "$entry" | jq -r .agent_id)
        local category=$(echo "$entry" | jq -r .category)
        local tags=$(echo "$entry" | jq -r .tags)
        
        [[ -n "$FILTER_AGENT" && "$agent" != "$FILTER_AGENT" ]] && continue
        [[ -n "$FILTER_CATEGORY" && "$category" != "$FILTER_CATEGORY" ]] && continue
        [[ -n "$FILTER_TAGS" && ! $(echo "$tags" | grep -qE "$(echo "$FILTER_TAGS" | sed 's/,/|/g')") ]] && continue
        
        filtered+=("$entry")
    done
    
    # Sort by timestamp (newest first) and limit
    printf '%s\n' "${filtered[@]}" | \
        jq -s 'sort_by(.timestamp) | reverse | .[:'"$LIMIT"']' | \
        jq -r '.[] | "\(.timestamp) | \(.agent_id) | \(.category) | \(.title) | \(.tags)"' | \
        head -n "$LIMIT"
}

semantic_search() {
    local query="$1"
    
    if [[ ! -f "$INDEX_DIR/semantic/vectors.faiss" ]]; then
        echo "  No semantic index found. Run: bash crew-indexer.sh rebuild --semantic"
        return 1
    fi
    
    # Use Python for semantic search
    python3 -c "
import sys, json, numpy as np
sys.path.insert(0, os.path.expanduser('~/.hermes/skills/devops/crew-knowledge-system/scripts'))

# Load index metadata
with open('$INDEX_DIR/semantic/metadata.json') as f:
    metadata = json.load(f)

# Load vectors (placeholder - would use faiss in production)
# For now, return message
print('  Semantic search requires full vector implementation')
print('  Install faiss-cpu and run: pip install faiss-cpu openai')
"
}

build_semantic_vectors() {
    echo "  Building semantic vectors requires:"
    echo "    - TURBOPUFFER_API_KEY"
    echo "    - OPENAI_API_KEY"
    echo "    - python packages: openai, faiss-cpu"
    echo "  Run: pip install openai faiss-cpu"
}

update_manifest() {
    local total_docs=0
    for cat_file in "$INDEX_DIR/by-category"/*.jsonl; do
        [[ -f "$cat_file" ]] && total_docs=$((total_docs + $(wc -l < "$cat_file")))
    done
    
    cat > "$INDEX_DIR/crew-manifest.json" <<MANIFEST
{
  "crew_id": "$CREW_ID",
  "crew_type": "$CREW_TYPE",
  "index_version": "1.0",
  "categories": ["architecture", "api", "ui", "infra", "process", "debugging", "research"],
  "total_documents": $total_docs,
  "last_indexed": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "semantic_vectors": ${CREW_SEMANTIC_ENABLED:-false}
}
MANIFEST
}

list_documents() {
    local cat="${1:-}"
    
    if [[ -n "$cat" ]]; then
        if [[ -f "$INDEX_DIR/by-category/$cat.jsonl" ]]; then
            cat "$INDEX_DIR/by-category/$cat.jsonl" | jq -r '. | "\(.timestamp) | \(.agent_id) | \(.title) | \(.tags)"'
        else
            echo "Category not found: $cat"
        fi
    else
        for cat_file in "$INDEX_DIR/by-category"/*.jsonl; do
            [[ -f "$cat_file" ]] || continue
            cat_name=$(basename "$cat_file" .jsonl)
            count=$(wc -l < "$cat_file")
            echo "$cat_name: $count documents"
        done
    fi
}