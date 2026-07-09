#!/usr/bin/env bash
# check_permissions.sh — audit workspace file permissions against the rules.
# Rules: *.sh 755, *.md 644, .secrets/ 700, secret files 600.
# REPORT ONLY by doctrine: never auto-chmod — surface findings and let the
# owner decide (restrictive chmod outside .secrets/ has caused data loss).
# Usage: bash scripts/check_permissions.sh --workspace <dir>
set -euo pipefail

WORKSPACE=""
[ "${1:-}" = "--workspace" ] && WORKSPACE="${2:-}"
[ -n "$WORKSPACE" ] || { echo "usage: $0 --workspace <dir>" >&2; exit 2; }
[ -d "$WORKSPACE" ] || { echo "no such workspace: $WORKSPACE" >&2; exit 2; }

issues=0
report() { echo "WARN $1"; issues=$((issues+1)); }

# shell scripts should be 755
while IFS= read -r -d '' f; do
    perm=$(stat -c '%a' "$f")
    [ "$perm" = "755" ] || report "$f is $perm (expected 755)"
done < <(find "$WORKSPACE/tools" -maxdepth 1 -name "*.sh" -print0 2>/dev/null)

# docs should be 644
while IFS= read -r -d '' f; do
    perm=$(stat -c '%a' "$f")
    [ "$perm" = "644" ] || report "$f is $perm (expected 644)"
done < <(find "$WORKSPACE/tools" -maxdepth 1 -name "*.md" -print0 2>/dev/null)

# .secrets/ is the ONLY place 700/600 belongs
if [ -d "$WORKSPACE/.secrets" ]; then
    perm=$(stat -c '%a' "$WORKSPACE/.secrets")
    [ "$perm" = "700" ] || report "$WORKSPACE/.secrets is $perm (expected 700)"
    while IFS= read -r -d '' f; do
        perm=$(stat -c '%a' "$f")
        [ "$perm" = "600" ] || report "$f is $perm (expected 600)"
    done < <(find "$WORKSPACE/.secrets" -type f -print0 2>/dev/null)
fi

# restrictive perms anywhere else are a red flag — report, never fix
while IFS= read -r -d '' f; do
    case "$f" in "$WORKSPACE/.secrets"*) continue ;; esac
    report "$f has restrictive permissions ($(stat -c '%a' "$f")) outside .secrets/ — report to owner, do NOT chmod"
done < <(find "$WORKSPACE" -maxdepth 2 \( -perm 700 -o -perm 000 \) -print0 2>/dev/null)

echo "---"
if [ "$issues" -eq 0 ]; then echo "PERMISSIONS CLEAN"; else echo "$issues finding(s) — owner decides fixes"; fi
[ "$issues" -eq 0 ]
