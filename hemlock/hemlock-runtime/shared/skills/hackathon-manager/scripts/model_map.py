#!/usr/bin/env python3
"""model_map.py — generate or query the hackathon-models.json role-to-model map.

The default mapping mirrors references/qwen-model-selection.md. Store the file
at the workspace root so every project references one source of truth.

Usage:
    python3 scripts/model_map.py init [--out hackathon-models.json]
    python3 scripts/model_map.py get <role> [--file hackathon-models.json]
    python3 scripts/model_map.py list [--file hackathon-models.json]
"""
import argparse
import json
import sys
from pathlib import Path

DEFAULT_MAP = {
    "orchestrator": "qwen3-235b-a22b-thinking-2507",
    "planning": "qwen3-235b-a22b-thinking-2507",
    "code-generation": "qwen3-coder-plus",
    "fast-coding": "qwen3-coder-flash-2025-07-28",
    "analysis": "qwen3-max-preview",
    "execution": "qwen-plus-latest",
    "approval": "qwen-plus-latest",
    "adversarial-analysis": "qwen3-235b-a22b",
    "structured-data": "qwen3-30b-a3b-instruct",
    "vision": "qwen-vl-max-latest",
}


def cmd_init(args):
    out = Path(args.out)
    if out.exists() and not args.force:
        print(f"exists: {out} (use --force to overwrite)", file=sys.stderr)
        return 1
    out.write_text(json.dumps(DEFAULT_MAP, indent=2, sort_keys=True) + "\n")
    print(f"wrote {out} ({len(DEFAULT_MAP)} roles)")
    return 0


def _load(path):
    p = Path(path)
    if p.exists():
        return json.loads(p.read_text())
    return DEFAULT_MAP


def cmd_get(args):
    mapping = _load(args.file)
    model = mapping.get(args.role)
    if model is None:
        print(f"unknown role: {args.role} (roles: {', '.join(sorted(mapping))})",
              file=sys.stderr)
        return 1
    print(model)
    return 0


def cmd_list(args):
    mapping = _load(args.file)
    for role, model in sorted(mapping.items()):
        print(f"{role:>22}  {model}")
    return 0


def main():
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    sub = ap.add_subparsers(dest="cmd", required=True)
    i = sub.add_parser("init"); i.add_argument("--out", default="hackathon-models.json"); i.add_argument("--force", action="store_true")
    g = sub.add_parser("get"); g.add_argument("role"); g.add_argument("--file", default="hackathon-models.json")
    l = sub.add_parser("list"); l.add_argument("--file", default="hackathon-models.json")
    args = ap.parse_args()
    return {"init": cmd_init, "get": cmd_get, "list": cmd_list}[args.cmd](args)


if __name__ == "__main__":
    sys.exit(main())
