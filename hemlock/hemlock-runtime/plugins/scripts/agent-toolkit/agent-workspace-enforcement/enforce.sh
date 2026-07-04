#!/usr/bin/env bash
# =============================================================================
# enforce.sh — Agent workspace enforcement
# =============================================================================
#
# Deterministic workspace cleanup and structure enforcement.
# Run from heartbeat, cron, or manually.
#
# Usage:
#   bash scripts/enforce.sh                    # Enforce $HERMES_HOME
#   bash scripts/enforce.sh /path/to/workspace # Enforce specific workspace
#
# This script:
# 1. Fixes ownership (root → agent)
# 2. Ensures required directories exist
# 3. Renames forbidden directories (cache→media, memories→memory, archives→.archive)
# 4. Archives runtime artifacts (cron, docs, platforms, etc.)
# 5. Removes bloat files
# 6. Validates required files exist
# 7. Fixes chmod 700 violations
# 8. Verifies tools/ directory standard
# 9. Checks SOUL.md identity
# =============================================================================

set -euo pipefail

WS="${1:-$HERMES_HOME}"

if [ -z "$WS" ] || [ ! -d "$WS" ]; then
    echo "ERROR: Workspace not found: $WS"
    echo "Set \$HERMES_HOME or pass path as argument."
    exit 1
fi

FIXED=0

echo "=== Enforcing: $WS ==="

# ---------------------------------------------------------------------------
# 0. Fix ownership
# ---------------------------------------------------------------------------
ROOT_COUNT=$(find "$WS" -maxdepth 3 -user root -not -path '*/.git/*' 2>/dev/null | wc -l)
if [ "$ROOT_COUNT" -gt 0 ]; then
    sudo chown -R "$(id -u):$(id -g)" "$WS" 2>/dev/null && FIXED=$((FIXED + ROOT_COUNT))
    echo "Fixed ownership on $ROOT_COUNT file(s)"
fi

# ---------------------------------------------------------------------------
# 1. Ensure required directories
# ---------------------------------------------------------------------------
for d in memory sessions skills projects .archive \
         media/images/agents media/images/misc media/files \
         tools logs .secrets .backups; do
    if [ ! -d "$WS/$d" ]; then
        mkdir -p "$WS/$d"
        echo "Created: $d/"
        FIXED=$((FIXED + 1))
    fi
done

# ---------------------------------------------------------------------------
# 2. cache/ → media/ (preserve received media)
# ---------------------------------------------------------------------------
if [ -d "$WS/cache" ]; then
    mkdir -p "$WS/media/images/agents" "$WS/media/images/misc" "$WS/media/files"
    find "$WS/cache" -type f \
        \( -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.png' \
           -o -iname '*.gif' -o -iname '*.webp' -o -iname '*.svg' \) \
        -exec mv {} "$WS/media/images/misc/" \; 2>/dev/null
    find "$WS/cache" -type f -exec mv {} "$WS/media/files/" \; 2>/dev/null
    rm -rf "$WS/cache"
    echo "cache/ → media/ (contents organized)"
    FIXED=$((FIXED + 1))
fi

# ---------------------------------------------------------------------------
# 3. memories/ → memory/
# ---------------------------------------------------------------------------
if [ -d "$WS/memories" ]; then
    mkdir -p "$WS/memory"
    cp -a "$WS/memories"/. "$WS/memory/" 2>/dev/null
    rm -rf "$WS/memories"
    echo "memories/ → memory/"
    FIXED=$((FIXED + 1))
fi

# ---------------------------------------------------------------------------
# 4. archives/ → .archive/
# ---------------------------------------------------------------------------
if [ -d "$WS/archives" ]; then
    mkdir -p "$WS/.archive"
    cp -a "$WS/archives"/. "$WS/.archive/" 2>/dev/null
    rm -rf "$WS/archives"
    echo "archives/ → .archive/"
    FIXED=$((FIXED + 1))
fi

# ---------------------------------------------------------------------------
# 5. Archive runtime artifacts
# ---------------------------------------------------------------------------
for d in cron docs platforms state sandboxes hooks \
         audio_cache image_cache pairing profiles whatsapp checkpoints; do
    [ -d "$WS/$d" ] || continue
    COUNT=$(find "$WS/$d" -type f 2>/dev/null | wc -l)
    if [ "$COUNT" -eq 0 ]; then
        rmdir "$WS/$d" 2>/dev/null
        echo "Removed empty: $d/"
    else
        mkdir -p "$WS/.archive"
        tar czf "$WS/.archive/${d}-$(date +%Y%m%d).tar.gz" -C "$WS" "$d" 2>/dev/null
        rm -rf "$WS/$d"
        echo "Archived: $d/ → .archive/${d}-$(date +%Y%m%d).tar.gz ($COUNT files)"
    fi
    FIXED=$((FIXED + 1))
done

# ---------------------------------------------------------------------------
# 6. Remove bloat files
# ---------------------------------------------------------------------------
for f in .skills_prompt_snapshot.json .hermes_history .update_check \
         interrupt_debug.log auth.lock SOUL.md.old; do
    if [ -f "$WS/$f" ]; then
        rm -f "$WS/$f"
        echo "Removed: $f"
        FIXED=$((FIXED + 1))
    fi
done
find "$WS" -type d -name "__pycache__" -exec rm -rf {} + 2>/dev/null
find "$WS" -name "*.pyc" -delete 2>/dev/null
find "$WS" -name ".DS_Store" -delete 2>/dev/null

# ---------------------------------------------------------------------------
# 7. Validate required files
# ---------------------------------------------------------------------------
for f in SOUL.md USER.md AGENTS.md agent.json config.yaml; do
    if [ ! -f "$WS/$f" ] || [ ! -s "$WS/$f" ]; then
        echo "MISSING/EMPTY: $f"
        FIXED=$((FIXED + 1))
    fi
done

# ---------------------------------------------------------------------------
# 8. Fix chmod 700 violations
# ---------------------------------------------------------------------------
find "$WS" -type d -perm 700 2>/dev/null | while read -r d; do
    chmod 755 "$d"
    echo "Fixed 700 → 755: $d"
done

# ---------------------------------------------------------------------------
# 9. Verify tools/ directory standard
# ---------------------------------------------------------------------------
TOOLS_DIR="$WS/tools"
if [ -d "$TOOLS_DIR" ]; then
    for f in auth-login.sh secret.sh TOOLS-GUIDE.md; do
        if [ ! -f "$TOOLS_DIR/$f" ]; then
            echo "MISSING: tools/$f"
            FIXED=$((FIXED + 1))
        fi
    done

    # Verify auth-login.sh uses 'hermes model', not 'hermes login'
    if [ -f "$TOOLS_DIR/auth-login.sh" ]; then
        # Check for actual command invocations (not comments)
        if grep -v '^#' "$TOOLS_DIR/auth-login.sh" | grep -q 'hermes login' 2>/dev/null; then
            echo "WRONG COMMAND: auth-login.sh invokes 'hermes login' — should be 'hermes model'"
            FIXED=$((FIXED + 1))
        fi
        if grep -v '^#' "$TOOLS_DIR/auth-login.sh" | grep -q 'python3 -m hermes_cli' 2>/dev/null; then
            echo "WRONG INVOCATION: auth-login.sh uses python3 module — should use 'hermes' binary"
            FIXED=$((FIXED + 1))
        fi
    fi
fi

# ---------------------------------------------------------------------------
# 10. Identity cross-contamination check
# ---------------------------------------------------------------------------
AGENT_NAME=$(basename "$WS")
if [ -f "$WS/SOUL.md" ]; then
    if ! head -1 "$WS/SOUL.md" 2>/dev/null | grep -qi "$AGENT_NAME"; then
        echo "WRONG IDENTITY: SOUL.md doesn't reference '$AGENT_NAME'"
    fi
fi

# ---------------------------------------------------------------------------
# 11. Handle empty stubs
# ---------------------------------------------------------------------------
find "$WS" -maxdepth 1 -name "*.md" -empty -not -name "MEMORY.md" 2>/dev/null | while read -r f; do
    rm -f "$f"
    echo "Removed empty stub: $(basename "$f")"
done

# ---------------------------------------------------------------------------
# 12. Rotate logs
# ---------------------------------------------------------------------------
find "$WS/logs" -name "*.log" -mtime +1 -exec gzip {} \; 2>/dev/null
find "$WS/logs" -name "*.gz" -mtime +30 -delete 2>/dev/null

# ---------------------------------------------------------------------------
# 13. Archive old projects (>30 days)
# ---------------------------------------------------------------------------
find "$WS/projects" -maxdepth 1 -type d -mtime +30 2>/dev/null | while read -r proj; do
    NAME=$(basename "$proj")
    [ "$NAME" = "projects" ] && continue
    tar czf "$WS/.archive/${NAME}-$(date +%Y%m%d).tar.gz" \
        --exclude='node_modules' --exclude='__pycache__' --exclude='.git' \
        -C "$WS/projects" "$NAME" 2>/dev/null
    rm -rf "$proj"
    echo "Archived old project: $NAME"
done

echo ""
echo "=== Done: $FIXED fix(es) ==="
