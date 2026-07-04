#!/usr/bin/env bash
# =============================================================================
# context-dump.sh — Crash-safe context offload
# =============================================================================
# Dumps the agent's working context to a TIMESTAMPED file so information is
# NEVER erased on shutdown, container failure, or power loss. It is fail-soft
# by design: it must never abort the shutdown path it runs on, so it does NOT
# use `set -e` and swallows its own errors.
#
# Usage:
#   bash tools/context-dump.sh [workspace] [reason]
#     workspace  default: $HERMES_HOME
#     reason     default: manual   (e.g. shutdown, periodic, crash)
#
# Writes (all under <workspace>/sessions/dumps/):
#   context-<YYYYmmdd-HHMMSS>.md   consolidated, human-readable snapshot
#   raw-<YYYYmmdd-HHMMSS>/         verbatim copies of session transcripts
# Also forces a SQLite WAL checkpoint so committed turns are fsynced to the
# main DB file (WAL in synchronous=NORMAL can otherwise lose the last commits
# on hard power loss).
#
# Retention: keeps the most recent CONTEXT_DUMP_KEEP dumps (default 20). The
# authoritative live transcripts in sessions/*.jsonl are NEVER touched — only
# the convenience snapshots are pruned.
#
# Path/location-agnostic: everything resolves from the passed workspace or
# $HERMES_HOME. Drop it into any agent and it works.
# =============================================================================

set -uo pipefail   # deliberately NOT -e: a dump must never fail a shutdown

WS="${1:-${HEMLOCK_HOME:-${HERMES_HOME:-}}}"
REASON="${2:-manual}"

[ -n "$WS" ] && [ -d "$WS" ] || { echo "context-dump: no workspace ('$WS')"; exit 0; }

TS="$(date +%Y%m%d-%H%M%S)"
AGENT="$(basename "$WS")"
DUMP_DIR="$WS/sessions/dumps"
OUT="$DUMP_DIR/context-$TS.md"
mkdir -p "$DUMP_DIR" 2>/dev/null || true

today="$(date +%Y-%m-%d)"
yday="$(date -d 'yesterday' +%Y-%m-%d 2>/dev/null || date -v-1d +%Y-%m-%d 2>/dev/null || echo '')"

# ── 1. Consolidated human-readable snapshot ─────────────────────────────────
{
    echo "# Context Dump — $TS"
    echo
    echo "- agent: \`$AGENT\`"
    echo "- reason: \`$REASON\`"
    echo "- host: \`$(hostname 2>/dev/null || echo unknown)\`"
    echo "- workspace: \`$WS\`"
    echo
    echo "> Recovered context. Read this to resume exactly where the previous session left off."
    echo
    if [ -f "$WS/context.md" ]; then
        echo "## Injected context (context.md)"; echo
        cat "$WS/context.md" 2>/dev/null; echo
    fi
    for d in "$today" "$yday"; do
        [ -n "$d" ] && [ -f "$WS/memory/$d.md" ] || continue
        echo "## Daily memory — $d"; echo
        cat "$WS/memory/$d.md" 2>/dev/null; echo
    done
    latest_jsonl="$(ls -t "$WS"/sessions/*.jsonl 2>/dev/null | head -1)"
    if [ -n "${latest_jsonl:-}" ] && [ -f "$latest_jsonl" ]; then
        echo "## Latest transcript tail — $(basename "$latest_jsonl")"; echo
        echo '```'
        tail -n 60 "$latest_jsonl" 2>/dev/null
        echo '```'
    fi
} > "$OUT" 2>/dev/null || true

# ── 2. Verbatim copies of raw session artifacts ─────────────────────────────
RAW="$DUMP_DIR/raw-$TS"
mkdir -p "$RAW" 2>/dev/null || true
for f in "$WS"/sessions/*.jsonl "$WS"/sessions/sessions.json; do
    [ -f "$f" ] && cp -a "$f" "$RAW/" 2>/dev/null || true
done
# If nothing was copied, drop the empty raw dir to avoid clutter
rmdir "$RAW" 2>/dev/null || true

# ── 3. Flush SQLite WAL so committed turns are durable on the main DB file ───
if command -v python3 >/dev/null 2>&1; then
    while IFS= read -r db; do
        [ -f "$db" ] || continue
        python3 - "$db" <<'PY' 2>/dev/null || true
import sqlite3, sys
try:
    c = sqlite3.connect(sys.argv[1], timeout=2)
    c.execute("PRAGMA wal_checkpoint(PASSIVE);")
    c.close()
except Exception:
    pass
PY
    done < <(find "$WS" -maxdepth 3 \( -name '*.db' -o -name '*.sqlite' -o -name '*.sqlite3' \) 2>/dev/null)
fi

# ── 4. Retention — prune old SNAPSHOTS only (never the live transcripts) ─────
KEEP="${CONTEXT_DUMP_KEEP:-20}"
ls -1dt "$DUMP_DIR"/context-*.md 2>/dev/null | tail -n +"$((KEEP + 1))" | while IFS= read -r old; do
    rm -f "$old" 2>/dev/null || true
    rm -rf "$DUMP_DIR/raw-$(basename "$old" .md | sed 's/^context-//')" 2>/dev/null || true
done

echo "context-dump: wrote $OUT (reason=$REASON)"
exit 0
