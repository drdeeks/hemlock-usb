#!/usr/bin/env python3
"""submission_check.py — validate a hackathon project directory for submission.

Checks the documented submission requirements: README with setup/run docs,
submission metadata, working entry point, model mapping present, and that no
credential files are staged for a public repo.

Usage:
    python3 scripts/submission_check.py <project-dir> [--json]
Exit 0 = ready, 1 = gaps found.
"""
import argparse
import json
import re
import sys
from pathlib import Path

CRED_NAMES = ("credentials.json", ".synth-creds.json", ".env")


def check(project: Path):
    results = []

    def add(name, passed, detail=""):
        results.append({"check": name, "passed": bool(passed), "detail": detail})

    readme = project / "README.md"
    add("README.md exists", readme.exists())
    if readme.exists():
        body = readme.read_text(errors="replace").lower()
        add("README documents setup/run",
            bool(re.search(r"\b(setup|install|run|usage|quick start)\b", body)),
            "needs a setup/run/usage section")
        add("README documents architecture",
            "architecture" in body or "how it works" in body,
            "explain architecture per the production standard")

    sub = project / "submission.md"
    add("submission.md exists", sub.exists())
    if sub.exists():
        s = sub.read_text(errors="replace").lower()
        add("submission names a track", "track" in s, "state the target track")
        add("submission links demo video",
            bool(re.search(r"(youtu|video|\.mp4|demo link)", s)),
            "3-5 min demo video required")

    entry = [p for p in project.glob("demo.*")] + [p for p in project.glob("main.*")]
    add("entry point present (demo.*/main.*)", bool(entry))

    mm = project / "hackathon-models.json"
    root_mm = project.parent / "hackathon-models.json"
    add("model mapping reachable", mm.exists() or root_mm.exists(),
        "run scripts/model_map.py init")

    gitignore = project / ".gitignore"
    ignored = gitignore.read_text(errors="replace") if gitignore.exists() else ""
    for cred in CRED_NAMES:
        f = project / cred
        if f.exists():
            add(f"credential file {cred} is gitignored", cred in ignored,
                "public repo required — never commit credentials")

    return results


def main():
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("project")
    ap.add_argument("--json", action="store_true")
    args = ap.parse_args()
    project = Path(args.project)
    if not project.is_dir():
        print(f"not a directory: {project}", file=sys.stderr)
        return 2
    results = check(project)
    failed = [r for r in results if not r["passed"]]
    if args.json:
        print(json.dumps({"ready": not failed, "checks": results}, indent=2))
    else:
        for r in results:
            mark = "PASS" if r["passed"] else "FAIL"
            line = f"{mark}  {r['check']}"
            if r["detail"] and not r["passed"]:
                line += f"  — {r['detail']}"
            print(line)
        print("---")
        print("READY" if not failed else f"NOT READY ({len(failed)} gap(s))")
    return 0 if not failed else 1


if __name__ == "__main__":
    sys.exit(main())
