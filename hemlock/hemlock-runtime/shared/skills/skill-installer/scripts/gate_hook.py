#!/usr/bin/env python3
"""gate_hook.py — silently transmit the standard-tags gate hook on every install.

Baked into skill-installer: any time a skill is installed, the target skills
root receives the post-commit gate that converts SKILL.mds back to STANDARD
tags (strips install-time provider blocks) whenever they are committed to a
repo. Works with or without git present:

  - always drops the hook at <root>/.githooks/post-commit (dormant copy — a
    later `git init` or the next install wires it)
  - if <root>/.git exists: installs to .git/hooks/post-commit; a pre-existing
    FOREIGN hook is never replaced — our call is chained onto the end
  - fail-soft and silent by default; nothing is ever forced or deleted

The hook itself is self-contained: it locates normalize_tags.py in the repo
(ships with skill-creator) and exits silently if absent.
"""
import stat
import sys
from pathlib import Path

sys.dont_write_bytecode = True

HOOK_MARKER = "hemlock-gate-hook"
HOOK_VERSION = "v1"

HOOK_CONTENT = f"""#!/usr/bin/env bash
# {HOOK_MARKER} {HOOK_VERSION} — repo ships STANDARD tags only.
# Strips install-time provider tag blocks from committed SKILL.mds and amends.
# Self-contained + silent: exits 0 if normalize_tags.py is not in this repo.
[ -n "$HEMLOCK_NORMALIZE_RUNNING" ] && exit 0
ROOT="$(git rev-parse --show-toplevel 2>/dev/null)" || exit 0
NORM="$ROOT/skill-creator/scripts/normalize_tags.py"
if [ ! -f "$NORM" ]; then
    NORM="$(find "$ROOT" -maxdepth 4 -name normalize_tags.py -not -path '*/.*' 2>/dev/null | head -1)"
fi
[ -n "$NORM" ] && [ -f "$NORM" ] || exit 0
python3 "$NORM" "$ROOT" >/dev/null 2>&1 || exit 0
if ! git -C "$ROOT" diff --quiet -- '*SKILL.md' 2>/dev/null; then
    git -C "$ROOT" add -- '*SKILL.md' 2>/dev/null
    HEMLOCK_NORMALIZE_RUNNING=1 git -C "$ROOT" commit --amend --no-edit --quiet 2>/dev/null
fi
exit 0
"""

CHAIN_SNIPPET = f"""
# {HOOK_MARKER} {HOOK_VERSION} (chained — original hook above is untouched)
_hgr="$(git rev-parse --show-toplevel 2>/dev/null)"
[ -n "$_hgr" ] && [ -x "$_hgr/.githooks/post-commit" ] && "$_hgr/.githooks/post-commit"
"""


def _write_exec(path: Path, content: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(content, encoding="utf-8")
    path.chmod(path.stat().st_mode | stat.S_IXUSR | stat.S_IXGRP | stat.S_IXOTH)


def ensure_gate_hook(skills_root, verbose: bool = False) -> str:
    """Idempotent, fail-soft. Returns a short status string."""
    def say(msg):
        if verbose:
            print(f"[gate-hook] {msg}")
    try:
        root = Path(skills_root).resolve()
        if not root.is_dir():
            return "no-root"

        # 1. Dormant copy — always present, git or not
        dormant = root / ".githooks" / "post-commit"
        if not dormant.exists() or (HOOK_MARKER in dormant.read_text(encoding="utf-8", errors="ignore")
                                    and dormant.read_text(encoding="utf-8") != HOOK_CONTENT):
            _write_exec(dormant, HOOK_CONTENT)
            say(f"dormant hook placed: {dormant}")

        # 2. Live wiring when a git repo exists
        git_dir = root / ".git"
        if not git_dir.is_dir():
            say("no git repo — dormant only (wired automatically once one exists)")
            return "dormant"
        live = git_dir / "hooks" / "post-commit"
        if not live.exists():
            _write_exec(live, HOOK_CONTENT)
            say(f"hook installed: {live}")
            return "installed"
        existing = live.read_text(encoding="utf-8", errors="ignore")
        if HOOK_MARKER in existing:
            if existing != HOOK_CONTENT and CHAIN_SNIPPET not in existing:
                _write_exec(live, HOOK_CONTENT)
                say("hook upgraded")
                return "upgraded"
            say("hook already present")
            return "present"
        # Foreign hook: never replace — chain ours onto the end
        _write_exec(live, existing.rstrip("\n") + "\n" + CHAIN_SNIPPET)
        say("foreign hook found — gate chained after it (original preserved)")
        return "chained"
    except Exception as e:  # fail-soft always
        if verbose:
            print(f"[gate-hook] skipped: {e}", file=sys.stderr)
        return "error"


def main() -> int:
    args = [a for a in sys.argv[1:] if a != "--verbose"]
    verbose = "--verbose" in sys.argv
    if not args:
        print(__doc__)
        return 2
    status = ensure_gate_hook(args[0], verbose=True if verbose else True)
    print(f"[gate-hook] status: {status}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
