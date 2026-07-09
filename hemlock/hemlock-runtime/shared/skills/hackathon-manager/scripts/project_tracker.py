#!/usr/bin/env python3
"""project_tracker.py — manage hackathon projects.json and bounties.json.

Matches the documented data structure:
    hackathon/
    ├── <project>/ (README.md, submission.md, progress.md)
    ├── bounties.json
    └── projects.json

Usage:
    python3 scripts/project_tracker.py add <name> --track <track> [--deadline YYYY-MM-DD]
    python3 scripts/project_tracker.py list
    python3 scripts/project_tracker.py status <name> <new-status>
    python3 scripts/project_tracker.py deadlines
Root defaults to ./hackathon; override with --root or HACKATHON_ROOT.
"""
import argparse
import json
import os
import sys
from datetime import date, datetime
from pathlib import Path

STATUSES = ("idea", "queued", "building", "testing", "submitted", "done")


def load(root: Path, name: str):
    f = root / name
    if f.exists():
        return json.loads(f.read_text())
    return {}


def save(root: Path, name: str, data):
    root.mkdir(parents=True, exist_ok=True)
    (root / name).write_text(json.dumps(data, indent=2, sort_keys=True) + "\n")


def cmd_add(root, args):
    projects = load(root, "projects.json")
    if args.name in projects:
        print(f"exists: {args.name}", file=sys.stderr)
        return 1
    projects[args.name] = {
        "track": args.track,
        "status": "idea",
        "deadline": args.deadline,
        "created": date.today().isoformat(),
    }
    save(root, "projects.json", projects)
    pdir = root / args.name
    pdir.mkdir(parents=True, exist_ok=True)
    for fn, title in (("README.md", f"# {args.name}"),
                      ("submission.md", f"# Submission — {args.name}"),
                      ("progress.md", f"# Progress — {args.name}")):
        f = pdir / fn
        if not f.exists():
            f.write_text(title + f"\n\nTrack: {args.track}\n")
    print(f"added: {args.name} (track={args.track})")
    return 0


def cmd_list(root, _args):
    projects = load(root, "projects.json")
    if not projects:
        print("no projects tracked")
        return 0
    for name, p in sorted(projects.items()):
        print(f"{p.get('status','?'):>10}  {name}  [{p.get('track','-')}]"
              f"  deadline={p.get('deadline') or '-'}")
    return 0


def cmd_status(root, args):
    projects = load(root, "projects.json")
    if args.name not in projects:
        print(f"unknown project: {args.name}", file=sys.stderr)
        return 1
    if args.new_status not in STATUSES:
        print(f"status must be one of {STATUSES}", file=sys.stderr)
        return 1
    projects[args.name]["status"] = args.new_status
    projects[args.name]["updated"] = datetime.now().isoformat(timespec="seconds")
    save(root, "projects.json", projects)
    print(f"{args.name} -> {args.new_status}")
    return 0


def cmd_deadlines(root, _args):
    projects = load(root, "projects.json")
    today = date.today()
    rows = []
    for name, p in projects.items():
        if not p.get("deadline"):
            continue
        d = date.fromisoformat(p["deadline"])
        rows.append(((d - today).days, name, p))
    for days, name, p in sorted(rows):
        flag = "OVERDUE" if days < 0 else f"{days}d left"
        print(f"{flag:>10}  {name}  [{p.get('status','?')}]  {p['deadline']}")
    if not rows:
        print("no deadlines set")
    return 0


def main():
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--root", default=os.environ.get("HACKATHON_ROOT", "hackathon"))
    sub = ap.add_subparsers(dest="cmd", required=True)
    a = sub.add_parser("add"); a.add_argument("name"); a.add_argument("--track", required=True); a.add_argument("--deadline")
    sub.add_parser("list")
    s = sub.add_parser("status"); s.add_argument("name"); s.add_argument("new_status")
    sub.add_parser("deadlines")
    args = ap.parse_args()
    root = Path(args.root)
    return {"add": cmd_add, "list": cmd_list, "status": cmd_status,
            "deadlines": cmd_deadlines}[args.cmd](root, args)


if __name__ == "__main__":
    sys.exit(main())
