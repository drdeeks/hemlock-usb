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
# 0. Prints tool enforcement rules banner (session-start)
# 1. Fixes ownership (root → agent)
# 2. Ensures required directories exist
# 3. Renames forbidden directories (cache→media, memories→memory, archives→.archive)
# 4. Archives runtime artifacts (cron, docs, platforms, etc.)
# 5. Removes bloat files
# 6. Validates required files exist
# 7. Fixes chmod 700 violations
# 8. Verifies tools/ directory standard (including inject-context.sh)
# 9. Checks SOUL.md identity
# =============================================================================

set -euo pipefail

WS="${1:-${HEMLOCK_HOME:-$HERMES_HOME}}"

if [ -z "$WS" ] || [ ! -d "$WS" ]; then
    echo "ERROR: Workspace not found: $WS"
    echo "Set \$HEMLOCK_HOME (or legacy \$HERMES_HOME) or pass path as argument."
    exit 1
fi

FIXED=0

# ---------------------------------------------------------------------------
# 0. Session-start rules banner (tool enforcement)
# ---------------------------------------------------------------------------
echo "=== Enforcing: $WS ==="
echo ""
echo "--- Tool Enforcement Rules ---"
echo "1. Use write_file/read_file/patch/search_files/execute_code properly"
echo "2. Terminal only for git operations and build/restart commands"
echo "3. Never write to /tmp for persistent data"
echo "4. NEVER chmod 700 or chmod 000 — use 755 (dirs) / 644 (files)"
echo "5. All files must be inside \$HERMES_HOME — never create agent-* directories"
echo "6. Write to files, never overwrite memory — append only"
echo "7. Check .secrets/ before asking user for credentials"
echo "8. Check TOOLS.md and knowledge base before asking for assistance"
echo "9. Any task needing more than two edits/steps → create a to-do list first"
echo "------------------------------"

# ---------------------------------------------------------------------------
# 1. Fix ownership
# Baked/volume model: the container runs as root and each agent lives on its
# OWN volume, so root-owned files are correct by design — nothing to fix (and
# the slim image ships no sudo). Only reconcile ownership in the legacy uid-1000
# bind-mount model, and only if sudo is actually available.
# ---------------------------------------------------------------------------
if [ "$(id -u)" -ne 0 ]; then
    ROOT_COUNT=$(find "$WS" -maxdepth 3 -user root -not -path '*/.git/*' 2>/dev/null | wc -l)
    if [ "$ROOT_COUNT" -gt 0 ] && command -v sudo >/dev/null 2>&1; then
        sudo chown -R "$(id -u):$(id -g)" "$WS" 2>/dev/null && FIXED=$((FIXED + ROOT_COUNT))
        echo "Fixed ownership on $ROOT_COUNT file(s)"
    fi
fi

# ---------------------------------------------------------------------------
# 2. Ensure required directories (CL-018: lean per-agent workspace)
# Removed from required: media/{images/{agents,misc},files} — agents don't
# get media subtrees by default. Added: knowledge, avatar.
# ---------------------------------------------------------------------------
for d in memory sessions skills projects .archive knowledge avatar \
         tools logs .secrets; do
    if [ ! -d "$WS/$d" ]; then
        mkdir -p "$WS/$d"
        echo "Created: $d/"
        FIXED=$((FIXED + 1))
    fi
done

# ---------------------------------------------------------------------------
# 3. cache/ migration (CL-018: route to .archive/cache-<ts>/ since media/ is
# no longer a default directory; preserves any files without polluting the
# lean workspace).
# ---------------------------------------------------------------------------
if [ -d "$WS/cache" ]; then
    ts=$(date +%Y%m%d-%H%M%S)
    mkdir -p "$WS/.archive/cache-$ts"
    mv "$WS/cache" "$WS/.archive/cache-$ts/" 2>/dev/null
    echo "cache/ → .archive/cache-$ts/ (lean workspace per CL-018)"
    FIXED=$((FIXED + 1))
fi

# ---------------------------------------------------------------------------
# 4. memories/ → memory/
# ---------------------------------------------------------------------------
if [ -d "$WS/memories" ]; then
    mkdir -p "$WS/memory"
    cp -a "$WS/memories"/. "$WS/memory/" 2>/dev/null
    rm -rf "$WS/memories"
    echo "memories/ → memory/"
    FIXED=$((FIXED + 1))
fi

# ---------------------------------------------------------------------------
# 5. archives/ → .archive/
# ---------------------------------------------------------------------------
if [ -d "$WS/archives" ]; then
    mkdir -p "$WS/.archive"
    cp -a "$WS/archives"/. "$WS/.archive/" 2>/dev/null
    rm -rf "$WS/archives"
    echo "archives/ → .archive/"
    FIXED=$((FIXED + 1))
fi

# ---------------------------------------------------------------------------
# 6. Archive runtime artifacts
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
# 7. Remove bloat files
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
# 8. Validate required files
# ---------------------------------------------------------------------------
for f in SOUL.md USER.md AGENTS.md agent.json config.yaml; do
    if [ ! -f "$WS/$f" ] || [ ! -s "$WS/$f" ]; then
        echo "MISSING/EMPTY: $f"
        FIXED=$((FIXED + 1))
    fi
done

# ---------------------------------------------------------------------------
# 9. Fix chmod 700 violations — NEVER 700, NEVER 600
# ---------------------------------------------------------------------------
# Directories: 755 (rwxr-xr-x) — NEVER 700
# Files: 644 (rw-r--r--) — NEVER 600
# Exceptions: .secrets/* and .env and auth.json stay restricted
find "$WS" -type d -perm 700 2>/dev/null | while read -r d; do
    chmod 755 "$d"
    echo "Fixed 700 → 755: $d"
    FIXED=$((FIXED + 1))
done

find "$WS" -type f -perm 600 -not -path '*/.secrets/*' -not -name '.env' -not -name 'auth.json' 2>/dev/null | while read -r f; do
    chmod 644 "$f"
    echo "Fixed 600 → 644: $f"
    FIXED=$((FIXED + 1))
done

# ---------------------------------------------------------------------------
# 9. Verify tools/ directory standard (including inject-context.sh and enforce.sh)
# ---------------------------------------------------------------------------
TOOLS_DIR="$WS/tools"
if [ -d "$TOOLS_DIR" ]; then
    for f in secret.sh memory-log.sh memory-promote.sh jsonfmt.py inject-context.sh enforce.sh context-dump.sh rollback.sh knowledge.sh; do
        if [ ! -f "$TOOLS_DIR/$f" ]; then
            echo "MISSING: tools/$f"
            FIXED=$((FIXED + 1))
        fi
    done
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

# ---------------------------------------------------------------------------
# 14. Document versioning standard (informative — warn, never block or modify)
# Per AGENTS.md §4, authored docs should carry a `version: X.Y.Z` header. We
# only REMIND — the agent (and owner) stay in control of when to bump. Set
# ENFORCE_DOC_VERSION=0 to silence.
# ---------------------------------------------------------------------------
if [ "${ENFORCE_DOC_VERSION:-1}" = "1" ]; then
    for doc in AGENTS.md TOOLS.md; do
        f="$WS/$doc"
        [ -f "$f" ] || continue
        if ! grep -qE '^version:[[:space:]]*[0-9]+\.[0-9]+\.[0-9]+' "$f" 2>/dev/null; then
            echo "DOC VERSION: $doc has no 'version: X.Y.Z' header (see AGENTS.md §4) — consider adding one"
        fi
    done
fi

# ---------------------------------------------------------------------------
# 15. Path-resolution guardrail for AGENT-CREATED scripts (informative)
# Skill-creator concept: DOC/informational files (USER.md, TOOLS.md, notes) MAY
# hardcode reference paths — agents need to know where things live. But TOOLING
# SCRIPTS / actionable deterministic items must stay path-resolving
# ($HEMLOCK_HOME / relative) so they keep working when the workspace is moved or
# dropped into another agent. We only WARN (never rewrite the agent's code).
# Set ENFORCE_SCRIPT_PATHS=0 to silence.
# ---------------------------------------------------------------------------
if [ "${ENFORCE_SCRIPT_PATHS:-1}" = "1" ] && [ -d "$WS/tools" ]; then
    STD_TOOLS=" secret.sh memory-log.sh memory-promote.sh jsonfmt.py inject-context.sh enforce.sh context-dump.sh rollback.sh auth-login.sh knowledge.sh "
    for script in "$WS"/tools/*.sh "$WS"/tools/*.py; do
        [ -f "$script" ] || continue
        base="$(basename "$script")"
        case "$STD_TOOLS" in *" $base "*) continue ;; esac   # skip baked standard tools
        # Flag hardcoded home/data/user paths that should resolve from $HEMLOCK_HOME.
        hits=$(grep -nE '(/home/|/root/|/Users/|/data/agents/[A-Za-z0-9._-]+/)' "$script" 2>/dev/null \
               | grep -vE '\$HEMLOCK_HOME|\$HERMES_HOME|workspace-template' | head -3)
        if [ -n "$hits" ]; then
            echo "PATH GUARD: tools/$base hardcodes an absolute path — prefer \$HEMLOCK_HOME/relative so it stays portable:"
            echo "$hits" | sed 's/^/    /'
        fi
    done
fi

echo ""
echo "=== Done: $FIXED fix(es) ==="
