#!/usr/bin/env python3
"""
enterprise-blueprint — Generate or sync an enforcement checklist from a blueprint

Parses blueprint.md for phase markers, module registry entries, section
rollback tags, spec headers, and DELIVERABLES. Produces a deeply granular
checklist.md with pre-phase gates, implementation steps derived from actual
blueprint deliverables, validation gates, and agent sign-off blocks per phase.
--sync preserves checked items in an existing checklist while adding any new
phases or sections.

Implementation steps are AUTO-GENERATED from the blueprint's Deliverables
sections. Each deliverable becomes a checklist step with context-appropriate
examples, validation criteria, and rollback procedures based on the detected
tech stack (Docker, Bash, Python, Node.js, database, REST API, etc.).

Usage:
    python3 scripts/generate_checklist.py <path/to/blueprint.md>
    python3 scripts/generate_checklist.py <path/to/blueprint.md> --sync
    python3 scripts/generate_checklist.py <path/to/blueprint.md> --output <path/to/checklist.md>
    python3 scripts/generate_checklist.py <path/to/blueprint.md> --json
"""

import json
import re
import sys
from datetime import datetime, timezone
from pathlib import Path


# ── Helpers ────────────────────────────────────────────────────────────────────

def now_iso():
    return datetime.now(timezone.utc).isoformat()


def today():
    return datetime.now(timezone.utc).strftime("%Y-%m-%d")


def read(path):
    try:
        return Path(path).read_text(encoding="utf-8")
    except Exception:
        return None


# ── Blueprint parser ───────────────────────────────────────────────────────────

PHASE_TAG = re.compile(r"\[PHASE-(\d+)-v(\d+)\]")
FEATURE_FLAG = re.compile(r"(FEAT_[A-Z][A-Z0-9_]+)")
ANY_H2 = re.compile(r"^##\s+(.+)$", re.MULTILINE)
MODULE_ROW = re.compile(
    r"\|\s*(MOD-\d{3})\s*\|\s*([^|]+)\s*\|\s*([^|]+)\s*\|\s*(FEAT_[A-Z][A-Z0-9_]+)",
    re.IGNORECASE,
)
SCREEN_SPEC = re.compile(
    r"^##\s+Screen\s+[\d.]+\s+[—–-]\s+(.+)$", re.IGNORECASE | re.MULTILINE
)


def parse_phases(content):
    """Return list of dicts: {index, title, tag, flag, deliverables, validation_gate}.

    Scans for [PHASE-N-vN] tags, finds nearest ## heading above, extracts
    FEAT_ flag, deliverables from ### Deliverables, and validation gate from
    ### Validation Gate.
    """
    phases = []
    seen_indices = set()

    for tag_match in PHASE_TAG.finditer(content):
        idx = int(tag_match.group(1))
        if idx in seen_indices:
            continue
        seen_indices.add(idx)

        tag = tag_match.group(0)

        # Scan backwards for the nearest ## heading
        window_start = max(0, tag_match.start() - 600)
        before = content[window_start: tag_match.start()]
        headings = list(ANY_H2.finditer(before))
        title = headings[-1].group(1).strip() if headings else f"Phase {idx}"

        # Scan forward for FEAT_ flag, deliverables, validation gate
        window_end = min(len(content), tag_match.start() + 5000)
        after = content[tag_match.start(): window_end]
        flag_m = FEATURE_FLAG.search(after)
        flag = flag_m.group(1) if flag_m else f"FEAT_PHASE_{idx}"

        # Extract deliverables (lines starting with - [ ] under ### Deliverables)
        deliverables = []
        deliv_match = re.search(
            r"###\s+Deliverables\s*\n([\s\S]*?)(?=\n###|\n---|\Z)", after
        )
        if deliv_match:
            for line in deliv_match.group(1).splitlines():
                dm = re.match(r"\s*-\s*\[\s*\]\s*(.+)", line)
                if dm:
                    deliverables.append(dm.group(1).strip())

        # Extract validation gate text
        val_gate = ""
        vg_match = re.search(
            r"###\s+Validation\s+Gate\s*\n([\s\S]*?)(?=\n###|\n---|\Z)", after
        )
        if vg_match:
            val_gate = vg_match.group(1).strip()

        phases.append({
            "index": idx,
            "title": title,
            "tag": tag,
            "flag": flag,
            "deliverables": deliverables,
            "validation_gate": val_gate,
        })

    phases.sort(key=lambda p: p["index"])
    return phases


def parse_modules(content):
    """Return list of dicts: {id, name, description, flag}."""
    modules = []
    for m in MODULE_ROW.finditer(content):
        modules.append({
            "id": m.group(1).strip(),
            "name": m.group(2).strip(),
            "description": m.group(3).strip(),
            "flag": m.group(4).strip(),
        })
    return modules


def parse_screens(content):
    """Return list of screen titles from spec headers."""
    return [m.group(1).strip() for m in SCREEN_SPEC.finditer(content)]


def detect_tech_stack(content):
    """Detect the project's tech stack from blueprint content."""
    lower = content.lower()
    return {
        "has_database": bool(re.search(
            r"(sql\s+|database|migration|psql|sqlite|mysql|postgres)", lower
        )),
        "has_rest_api": bool(re.search(
            r"(api/v1|rest\s+api|endpoint|curl\s+-[XG]|http\s+method)", lower
        )),
        "has_docker": bool(re.search(
            r"(dockerfile|docker-compose|docker\s+compose|container)", lower
        )),
        "has_bash": bool(re.search(
            r"(\.sh\b|bash\s+|shell\s+script|#!/bin/bash)", lower
        )),
        "has_python": bool(re.search(
            r"(python\s+3|\.py\b|pip\s+|pytest|import\s+\w+)", lower
        )),
        "has_nodejs": bool(re.search(
            r"(node\.js|npm\s+|express|javascript|typescript)", lower
        )),
        "has_ci": bool(re.search(
            r"(ci/cd|ci\s+pipeline|github\s+actions|gitlab\s+ci|jenkins)", lower
        )),
        "has_feature_flags": bool(re.search(
            r"(feature\s+flag|feature\s+toggle|flag\s+dashboard)", lower
        )),
    }


def parse_existing_checked(existing_content):
    """Return set of checked item labels from an existing checklist."""
    checked = set()
    for line in existing_content.splitlines():
        m = re.match(r"\s*-\s*\[x\]\s*\*\*(.+?)\*\*", line, re.IGNORECASE)
        if m:
            checked.add(m.group(1).strip())
    return checked


# ── Context-aware step generation ──────────────────────────────────────────────

def _step_context(deliverable, tech):
    """Generate context-appropriate example, validation, and rollback
    for a given deliverable based on the detected tech stack."""
    lower = deliverable.lower()

    # Check docker-specific keywords BEFORE generic "copy" to get better context
    if any(kw in lower for kw in ["docker", "compose", "dockerfile", "container"]):
        return (
            "docker compose config validates; docker build completes.",
            "All Dockerfiles build. Compose config validates.",
            "docker compose down; remove Dockerfiles.",
        )
    elif any(kw in lower for kw in ["copy", "create directory", "mkdir", "scaffold",
                                    "initialize", "init "]):
        return (
            "Verify: ls -la <target> shows expected files/directories.",
            "All expected files/directories exist and are non-empty.",
            "Remove created files/directories.",
        )
    elif any(kw in lower for kw in ["test", "validate", "verify", "check",
                                      "lint", "syntax"]):
        return (
            "Run the test/validation command; confirm 0 failures.",
            "All checks pass with no errors.",
            "Revert any test configuration changes.",
        )
    elif any(kw in lower for kw in ["config", "yaml", "json", "env", "template",
                                      "configuration"]):
        return (
            "cat/parse the config file; confirm valid syntax.",
            "Config file parses without error; all required keys present.",
            "Restore original config file from backup.",
        )
    elif any(kw in lower for kw in ["script", "chmod", "permission", "755"]):
        return (
            "bash -n <script> confirms valid syntax; chmod 755 applied.",
            "Script parses without error and has correct permissions.",
            "Remove script; restore original permissions.",
        )
    elif any(kw in lower for kw in ["python", "pip", "module", "import"]):
        return (
            "python3 -c 'import <module>' succeeds.",
            "Module imports without error.",
            "Remove module; uninstall dependencies.",
        )
    elif any(kw in lower for kw in ["git", "commit", "branch", "repo",
                                      ".gitignore"]):
        return (
            "git status shows clean tree; git log shows expected commits.",
            "Git history is clean; all changes committed.",
            "git reset --hard HEAD~1 (if single commit).",
        )
    elif any(kw in lower for kw in ["plugin", "extension", "addon"]):
        return (
            "List plugins; confirm new entry is loadable.",
            "Plugin loads without error; toggle works.",
            "Remove plugin directory; disable in config.",
        )
    elif any(kw in lower for kw in ["agent", "workspace", "template"]):
        return (
            "List agent workspaces; confirm required files exist.",
            "Agent workspace has config.yaml + SOUL.md + required dirs.",
            "Remove agent workspace directory.",
        )
    elif any(kw in lower for kw in ["security", "secret", "encrypt", "harden",
                                      "hardcoded"]):
        return (
            "grep -r 'hardcoded_secret' . returns nothing.",
            "No plaintext secrets in tracked files.",
            "Restore .env; revert permission changes.",
        )
    elif any(kw in lower for kw in ["health", "doctor", "check"]):
        return (
            "Run health check command; confirm all validators pass.",
            "Health system reports all checks passing.",
            "Disable health check integration.",
        )
    elif any(kw in lower for kw in ["memory", "state", "sqlite", "reflection"]):
        return (
            "Open state DB; confirm tables exist.",
            "Memory/state files present and parseable.",
            "Remove memory/state files.",
        )
    elif any(kw in lower for kw in ["gateway", "adapter", "platform",
                                      "telegram", "discord"]):
        return (
            "Gateway config validates; adapter list shows entries.",
            "All platform adapters present; config writes correctly.",
            "Remove gateway config; disable adapter.",
        )
    elif any(kw in lower for kw in ["merge", "integrate", "combine"]):
        return (
            "Diff against source; confirm all content present.",
            "Merged content matches source with no data loss.",
            "Restore from backup; re-run merge.",
        )
    elif any(kw in lower for kw in ["fix", "patch", "resolve", "correct"]):
        return (
            "Re-run the check that previously failed; confirm pass.",
            "Previously failing check now passes.",
            "Revert the fix; confirm original issue returns.",
        )
    elif any(kw in lower for kw in ["remove", "clean", "delete", "purge"]):
        return (
            "Confirm target is removed; no orphaned references.",
            "Target removed; no dangling references.",
            "Restore removed item from backup.",
        )
    elif any(kw in lower for kw in ["set", "update", "modify", "change"]):
        return (
            "cat/parse the file; confirm change is applied.",
            "Change applied correctly; no side effects.",
            "Revert to previous value.",
        )
    elif any(kw in lower for kw in ["run", "execute", "start", "stop",
                                      "restart", "launch"]):
        return (
            "Run the command; confirm it completes without error.",
            "Command runs successfully; expected output produced.",
            "Stop/revert the process.",
        )
    elif any(kw in lower for kw in ["build", "compile", "make"]):
        return (
            "make/build command completes; artifacts produced.",
            "Build succeeds; output artifacts are valid.",
            "Clean build artifacts; revert build config.",
        )
    else:
        return (
            f"Verify: confirm '{deliverable}' is complete.",
            "Deliverable is present and functional.",
            "Revert changes from this step.",
        )


# ── Checklist builders ─────────────────────────────────────────────────────────

def global_prerequisites_block(tech):
    """Generate global prerequisites based on detected tech stack."""
    lines = [
        "## GLOBAL PREREQUISITES",
        "",
        "Complete before starting Phase 0:",
        "",
        "- [ ] Project directory structure created at target location.",
        "- [ ] `CHANGELOG.md` created in project root (append-only).",
    ]

    if tech["has_docker"]:
        lines.append("- [ ] Docker installed and running (dockerd active).")

    if tech["has_bash"]:
        lines.append("- [ ] Bash 5.0+ available; all scripts have execute permissions.")

    if tech["has_python"]:
        lines.append("- [ ] Python 3.12+ available; pip dependencies documented.")

    if tech["has_ci"]:
        lines.append("- [ ] CI/CD pipeline configured: test -> lint -> build -> deploy.")

    if tech["has_feature_flags"]:
        lines.append(
            "- [ ] Feature flags system initialized; every flag defaults to `disabled`."
        )

    lines.append(
        "- [ ] `assignments.json` initialized with Phase 0 agent assignments."
    )
    lines += ["", "---", ""]
    return "\n".join(lines)


def module_checklist_block(modules):
    if not modules:
        return ""
    lines = [
        "## MODULE REGISTRY VERIFICATION",
        "",
        "Confirm each module is defined before implementation begins:",
        "",
    ]
    for mod in modules:
        lines.append(
            f"- [ ] **{mod['id']} — {mod['name']}**: "
            f"Feature flag `{mod['flag']}` created and set to `disabled`. "
            f"Description confirmed: _{mod['description']}_"
        )
    lines += ["", "---", ""]
    return "\n".join(lines)


def phase_block(phase, modules, screens, tech, existing_checked):
    i = phase["index"]
    title = phase["title"]
    tag = phase["tag"]
    flag = phase["flag"]
    deliverables = phase.get("deliverables", [])
    val_gate = phase.get("validation_gate", "")
    prior = f"Phase {i - 1}" if i > 0 else "N/A"

    def item(label, detail="", example="", validation="", rollback="",
              checked=False):
        state = "x" if (checked or label in existing_checked) else " "
        parts = [f"- [{state}] **{label}**"]
        if detail:
            parts.append(f"  _{detail}_")
        if example:
            parts.append(f"  - _Example:_ {example}")
        if validation:
            parts.append(f"  - _Validation:_ {validation}")
        if rollback:
            parts.append(f"  - _Rollback:_ {rollback}")
        return "\n".join(parts)

    lines = [
        f"## {title}",
        "",
        f"**Section Tag:** `{tag}` | **Feature Flag:** `{flag}`",
        "**Status:** `NOT STARTED` | **Assigned Agent:** _unassigned_",
        f"**Prerequisite:** {prior} must be `COMPLETE` with change log entry written.",
        "",
        "### Pre-Phase Gate",
        "",
        "Confirm all of the following before any work begins on this phase:",
        "",
        item(
            "Prior phase change log entry written",
            "The CL entry for the preceding phase is appended to CHANGELOG.md.",
            "grep 'PHASE-" + str(i - 1) + "' CHANGELOG.md returns at least one entry." if i > 0 else "N/A — first phase, no prior entry required.",
            "Entry is present and contains all required fields." if i > 0 else "N/A — first phase.",
            "N/A — this is a gate check, not a code change.",
        ),
    ]

    if tech["has_ci"]:
        lines.append(item(
            "Prior phase CI tests passing",
            "All tests introduced in the prior phase are green in CI.",
            "CI pipeline shows 0 failing tests on main branch.",
            "CI badge shows passing status.",
            "Fix failing tests before proceeding; do not bypass.",
        ))

    lines.append(item(
        f"Feature flag `{flag}` created and disabled",
        "The flag must exist before any Phase code ships.",
        f"Flag `{flag}` = false in production.",
        "Verify via flag config or admin panel.",
        "Set flag to false immediately; redeploy if necessary.",
    ))

    if tech["has_database"]:
        lines.append(item(
            "Database migration rollback files prepared",
            "Every forward migration has a corresponding rollback file.",
            "For each `YYYYMMDD_NNN_description.sql`, a `_ROLLBACK.sql` exists.",
            "Execute rollback on staging; confirm clean revert.",
            "Execute the rollback SQL file; verify schema returns to prior state.",
        ))

    lines.append(item(
        "Agent assignment confirmed in assignments.json",
        "The responsible agent for this phase is recorded before work begins.",
        f'assign_agents.py --assign "AgentName:{tag}" ./project',
        "assignments.json shows this phase with a non-null agent field.",
        "Re-run assign_agents.py --assign to correct the assignment.",
    ))

    # Implementation steps — generated from deliverables
    lines += [
        "",
        "### Implementation Steps",
        "",
        "> Every step must be completed, tested, and individually logged "
        "before proceeding to the next.",
        "",
    ]

    if deliverables:
        for idx, deliverable in enumerate(deliverables, 1):
            step_label = f"Step {idx} — {deliverable}"
            example, validation, rollback_text = _step_context(deliverable, tech)
            lines.append(item(
                step_label,
                "",
                example,
                validation,
                rollback_text,
            ))
    else:
        # Fallback when no deliverables found in blueprint
        lines.append(item(
            "Step 1 — Foundation Setup",
            "Create project structure and core files.",
            "ls -la shows expected directories and files.",
            "All created files exist and are non-empty.",
            "Remove created files and directories.",
        ))
        lines.append(item(
            "Step 2 — Core Implementation",
            "Build the primary feature logic for this phase.",
            "Core functionality works as specified.",
            "No regressions on existing features.",
            "Revert changed files; disable feature flag.",
        ))
        lines.append(item(
            "Step 3 — Validation & Testing",
            "Verify the implementation works correctly.",
            "All tests pass; no errors.",
            "No regressions.",
            "Revert test changes if they break existing tests.",
        ))

    # Validation gate — use blueprint's if available, else generic
    lines += [
        "",
        "### Phase Validation Gate",
        "",
        "All of the following must be true before this phase is marked `COMPLETE`:",
        "",
        "- [ ] All implementation steps above are checked.",
    ]

    if val_gate:
        for vline in val_gate.splitlines():
            vm = re.match(r">\s*(.+)", vline)
            if vm:
                lines.append(f"- [ ] {vm.group(1).strip()}")
    else:
        if tech["has_ci"]:
            lines.append(
                "- [ ] All tests introduced in this phase are passing in CI."
            )

    lines += [
        f"- [ ] `{flag}` is confirmed enabled.",
        "- [ ] Change log entry for this phase is written and appended.",
        "- [ ] Blueprint updated to reflect any deviations from the specification.",
        "- [ ] Assigned agent has signed off (name + date in block below).",
        "",
        "### Agent Sign-Off",
        "",
        "```",
        f"Phase {i} — {title}",
        "  Agent     : _________________",
        "  Date      : _________________",
        "  Commit    : _________________",
        "  Notes     : _________________",
        "```",
        "",
        "---",
        "",
    ]
    return "\n".join(lines)


def global_completion_block(tech):
    """Generate global completion criteria based on tech stack."""
    lines = [
        "## GLOBAL COMPLETION CRITERIA",
        "",
        "The project is production-complete when all of the following are true:",
        "",
        "- [ ] All phase statuses are `COMPLETE` with agent sign-offs recorded.",
        "- [ ] All feature flags are enabled.",
    ]

    if tech["has_docker"]:
        lines.append(
            "- [ ] All Docker images build; containers start and are healthy."
        )

    if tech["has_ci"]:
        lines.append(
            "- [ ] CI/CD pipeline green on main branch; all tests passing."
        )

    if tech["has_bash"]:
        lines.append(
            "- [ ] All shell scripts have correct permissions (755) and pass syntax check."
        )

    if tech["has_python"]:
        lines.append(
            "- [ ] Python modules import cleanly; pytest suite passes."
        )

    lines += [
        "- [ ] Performance budgets verified; results documented in change log.",
        "- [ ] Security audit completed; no plaintext secrets in tracked files.",
        "- [ ] Final change log entry written documenting the production launch.",
        "- [ ] Blueprint marked as FINAL in document header.",
    ]
    return "\n".join(lines)


def build_checklist(project_name, phases, modules, screens, tech,
                    existing_checked, blueprint_path):
    d = today()
    bp_name = Path(blueprint_path).name

    header = [
        f"# {project_name} — ENTERPRISE CHECKLIST",
        f"## Coexists with: {bp_name}",
        f"### Generated: {d}",
        "",
        "> **CHECKLIST AUTHORITY**",
        "> This checklist enforces blueprint.md. It must not diverge — every",
        "> blueprint amendment requires a corresponding checklist update in the",
        "> same commit. Checked items are immutable; corrections require a new",
        "> line with explanation, never erasure of a checked item.",
        ">",
        "> **Status values:** `NOT STARTED` | `IN PROGRESS` | `BLOCKED` | `COMPLETE`",
        "> **Blocking rule:** No phase may begin until the prior phase is `COMPLETE`.",
        "",
        "---",
        "",
    ]

    body = []
    body.append(global_prerequisites_block(tech))
    if modules:
        body.append(module_checklist_block(modules))
    for phase in phases:
        body.append(phase_block(phase, modules, screens, tech, existing_checked))
    body.append(global_completion_block(tech))

    return "\n".join(header) + "\n".join(body) + "\n"


# ── Main ───────────────────────────────────────────────────────────────────────

def main():
    if len(sys.argv) < 2 or sys.argv[1] in ("--help", "-h"):
        print(__doc__)
        sys.exit(0)

    bp_path = Path(sys.argv[1])
    sync_mode = "--sync" in sys.argv
    as_json = "--json" in sys.argv

    output_arg = None
    if "--output" in sys.argv:
        idx = sys.argv.index("--output")
        if idx + 1 < len(sys.argv):
            output_arg = Path(sys.argv[idx + 1])

    if not bp_path.exists():
        print(f"[ERROR] Blueprint not found: {bp_path}")
        print("        Run init_blueprint.py first, or check the path.")
        sys.exit(1)

    content = read(bp_path)
    if not content:
        print(f"[ERROR] Could not read: {bp_path}")
        sys.exit(1)

    # Parse project name from first heading
    title_m = re.search(r"^#\s+(.+?)\s+[—–-]", content, re.MULTILINE)
    project_name = title_m.group(1).strip() if title_m else bp_path.stem

    phases = parse_phases(content)
    modules = parse_modules(content)
    screens = parse_screens(content)
    tech = detect_tech_stack(content)

    # Determine output path
    checklist_path = output_arg or (bp_path.parent / "checklist.md")

    # Preserve checked items in sync mode
    existing_checked = set()
    if sync_mode and checklist_path.exists():
        existing = read(checklist_path)
        if existing:
            existing_checked = parse_existing_checked(existing)

    started = now_iso()
    error = None
    status = "success"

    try:
        checklist_content = build_checklist(
            project_name, phases, modules, screens, tech,
            existing_checked, bp_path
        )
        checklist_path.write_text(checklist_content, encoding="utf-8")
    except Exception as exc:
        status = "failed"
        error = str(exc)

    result = {
        "operation": "generate_checklist",
        "timestamp": now_iso(),
        "status": status,
        "project": project_name,
        "details": {
            "blueprint": str(bp_path),
            "checklist": str(checklist_path),
            "phases_found": len(phases),
            "modules_found": len(modules),
            "screens_found": len(screens),
            "tech_stack": tech,
            "sync_mode": sync_mode,
            "preserved_checked_items": len(existing_checked),
        },
        "cost": {"tier": 0, "amount_usd": 0.0, "service": "local"},
    }
    if error:
        result["error"] = error

    if as_json:
        print(json.dumps(result, indent=2))
    else:
        if status == "success":
            print(f"[OK] Checklist written: {checklist_path}")
            print(f"  Phases   : {len(phases)}")
            print(f"  Modules  : {len(modules)}")
            print(f"  Screens  : {len(screens)}")
            print(f"  Tech     : {', '.join(k for k, v in tech.items() if v)}")
            if sync_mode:
                print(f"  Preserved: {len(existing_checked)} checked items")
        else:
            print(f"[ERROR] {error}")
            sys.exit(1)
        print()
        print(json.dumps(result, indent=2))


if __name__ == "__main__":
    main()
