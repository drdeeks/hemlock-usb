#!/usr/bin/env bash
# validate_tools.sh — verify an agent workspace has the required tool kit.
# Required: enforce.sh, secret.sh, memory-log.sh, memory-promote.sh, TOOLS-GUIDE.md
# Usage:
#   bash scripts/validate_tools.sh --workspace <dir> [--fix --source <tools-dir>]
set -euo pipefail

WORKSPACE=""; FIX=0; SOURCE=""
while [ $# -gt 0 ]; do
    case "$1" in
        --workspace) WORKSPACE="$2"; shift 2 ;;
        --fix) FIX=1; shift ;;
        --source) SOURCE="$2"; shift 2 ;;
        *) echo "unknown flag: $1" >&2; exit 2 ;;
    esac
done
[ -n "$WORKSPACE" ] || { echo "usage: $0 --workspace <dir> [--fix --source <tools-dir>]" >&2; exit 2; }
[ -d "$WORKSPACE" ] || { echo "no such workspace: $WORKSPACE" >&2; exit 2; }

REQUIRED_TOOLS=(enforce.sh secret.sh memory-log.sh memory-promote.sh TOOLS-GUIDE.md)
REQUIRED_DIRS=(tools skills memory .secrets)

fail=0
for d in "${REQUIRED_DIRS[@]}"; do
    if [ -d "$WORKSPACE/$d" ]; then
        echo "PASS dir  $d/"
    else
        echo "FAIL dir  $d/ missing"
        fail=$((fail+1))
        [ "$FIX" -eq 1 ] && { mkdir -p "$WORKSPACE/$d"; echo "  fixed: created $d/"; fail=$((fail-1)); }
    fi
done

for t in "${REQUIRED_TOOLS[@]}"; do
    f="$WORKSPACE/tools/$t"
    if [ -f "$f" ]; then
        case "$t" in
            *.sh) [ -x "$f" ] && echo "PASS tool $t (executable)" || { echo "FAIL tool $t not executable"; fail=$((fail+1)); } ;;
            *)    echo "PASS tool $t" ;;
        esac
    else
        echo "FAIL tool $t missing"
        fail=$((fail+1))
        if [ "$FIX" -eq 1 ] && [ -n "$SOURCE" ] && [ -f "$SOURCE/$t" ]; then
            cp "$SOURCE/$t" "$f"
            case "$t" in *.sh) chmod 755 "$f" ;; esac
            echo "  fixed: copied from $SOURCE"
            fail=$((fail-1))
        fi
    fi
done

echo "---"
if [ "$fail" -eq 0 ]; then echo "TOOL KIT COMPLETE"; else echo "$fail problem(s) — rerun with --fix --source <tools-dir>"; fi
[ "$fail" -eq 0 ]
