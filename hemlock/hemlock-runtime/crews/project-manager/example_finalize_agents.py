#!/usr/bin/env python3
"""
finalize_agents.py

One-and-done maintainer that:
  - Updates ALL existing agent JSONs and .envs in ./agents/**
  - Enforces category-locked, purpose-descriptive names from the latest create_agents.py
  - Aligns primary/backup models
  - Ensures correct file paths for env/rules
  - Keeps ONLY the starter agent in ./agents/active (moves any extras to ./agents/archive)
  - Creates and wires workflows:
        ./agents/workflow/agent/<category>_workflow.json
        ./agents/workflow/crew/*.json
        ./agents/workflow/global/global_communication_standards.json
  - Adds workflow references into agent JSONs
  - Does NOT create any "model mappings" file, any "master ruleset", or any "global system prompt" file.

Run from repo root:
    python finalize_agents.py
"""

from __future__ import annotations

import argparse
import json
import re
import shutil
import sys
from pathlib import Path
from typing import Any, Dict, Iterable, List, Optional, Sequence, Tuple

# --------------------------------------------------------------------------------------
# Dynamically load canonical agent definitions from create_agents.py
# --------------------------------------------------------------------------------------
AGENT_CANON: Dict[str, Dict[str, str]] = {} # Will be populated dynamically

def _load_agent_canon() -> None:
    global AGENT_CANON
    create_agents_path = ROOT / "create_agents.py"
    if not create_agents_path.exists():
        print(f"[ERROR] create_agents.py not found at {create_agents_path}. Cannot load canonical agent data.", file=sys.stderr)
        sys.exit(1)

    # Temporarily add the directory to sys.path to import create_agents
    sys.path.insert(0, str(ROOT))
    try:
        import create_agents
        for category, agents in create_agents.AGENT_CATEGORIES.items():
            for agent_config in agents:
                AGENT_CANON[agent_config["slug"]] = {
                    "name": agent_config["name"],
                    "category": category, # Use the category from AGENT_CATEGORIES
                    "primary_model": agent_config["model"],
                    "backup_model": agent_config["backup_model"],
                }
    except ImportError as e:
        print(f"[ERROR] Could not import create_agents.py: {e}", file=sys.stderr)
        sys.exit(1)
    finally:
        # Remove the path from sys.path
        if str(ROOT) in sys.path:
            sys.path.remove(str(ROOT))

# Crew workflows we will generate and link into every agent JSON
CREW_WORKFLOWS: List[str] = [
    "campaign_orchestration.json",
    "content_delivery.json",
    "incident_response.json",
]

ROOT: Path = Path(__file__).resolve().parent
AGENTS_DIR: Path = ROOT / "agents"
ACTIVE_DIR: Path = AGENTS_DIR / "active"
ARCHIVE_DIR: Path = AGENTS_DIR / "archive"
ENVS_DIR: Path = AGENTS_DIR / "envs"
RULES_DIR: Path = AGENTS_DIR / "rules"
WORKFLOWS_DIR: Path = AGENTS_DIR / "workflow"
WF_AGENT_DIR: Path = WORKFLOWS_DIR / "agent"
WF_CREW_DIR: Path = WORKFLOWS_DIR / "crew"
WF_GLOBAL_DIR: Path = WORKFLOWS_DIR / "global"
LOGS_DIR: Path = AGENTS_DIR / "logs"

# --------------------------------------------------------------------------------------
# Utilities
# --------------------------------------------------------------------------------------
def slurp_json(path: Path) -> Dict[str, Any]:
    with path.open("r", encoding="utf-8") as f:
        return json.load(f)

def spit_json(path: Path, data: Dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", encoding="utf-8") as f:
        json.dump(data, f, indent=2, ensure_ascii=False)
        f.write("\n")

def is_starter_name(name: str) -> bool:
    return bool(re.search(r"\bstarter\b", name, flags=re.I))

def guess_slug(path: Path) -> str:
    return path.stem

def ensure_dirs() -> None:
    for d in (AGENTS_DIR, ACTIVE_DIR, ARCHIVE_DIR, ENVS_DIR, RULES_DIR, WORKFLOWS_DIR, WF_AGENT_DIR, WF_CREW_DIR, WF_GLOBAL_DIR, LOGS_DIR):
        d.mkdir(parents=True, exist_ok=True)

def read_text(path: Path) -> str:
    with path.open("r", encoding="utf-8") as f:
        return f.read()

def write_text(path: Path, text: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", encoding="utf-8") as f:
        f.write(text)

def find_jsons() -> List[Path]:
    out: List[Path] = []
    for base in (ACTIVE_DIR, ARCHIVE_DIR):
        if base.exists():
            out.extend(sorted([p for p in base.glob("*.json") if p.is_file()]))
    return out

def env_update_preserve_order(env_path: Path, updates: Dict[str, str]) -> bool:
    """
    Update only selected keys in a .env while preserving:
      - original ordering
      - comments / blank lines
      - exact formatting of untouched lines

    Returns True if file content changed.
    """
    if not env_path.exists():
        return False

    with env_path.open("r", encoding="utf-8") as f:
        lines: List[str] = f.read().splitlines()

    key_re = re.compile(r"^([A-Z0-9_]+)\s*=\s*(.*)$")
    present_keys: Dict[str, int] = {}
    changed: bool = False

    for i, line in enumerate(lines):
        m = key_re.match(line)
        if not m:
            continue
        key, val = m.group(1), m.group(2)
        present_keys[key] = i
        if key in updates:
            new_val = updates[key]
            if val.strip() != new_val:
                lines[i] = f"{key}={new_val}"
                changed = True

    # Append any missing keys at the end (in the specified order)
    for k in ("AGENT_ID","AGENT_NAME","AGENT_CATEGORY","PRIMARY_MODEL","BACKUP_MODEL","WORKFLOW_FILE"):
        if k in updates and k not in present_keys:
            # ensure there's a blank line before appends if file doesn't end with one
            if lines and lines[-1].strip() != "":
                lines.append("")
            lines.append(f"{k}={updates[k]}")
            changed = True

    if changed:
        with env_path.open("w", encoding="utf-8") as f:
            f.write("\n".join(lines) + "\n")
    return changed

def ensure_workflows(category_keys: Iterable[str]) -> None:
    """
    Create:
      - workflow/agent/<category>_workflow.json for every category in use
      - crew workflows (3 files)
      - global communication standards json
    """
    # Category workflows
    for cat in sorted(set(category_keys)):
        wf = WF_AGENT_DIR / f"{cat}_workflow.json"
        if not wf.exists():
            data: Dict[str, Any] = {
                "version": "1.0",
                "category": cat,
                "phases": [
                    {"id": "ingest", "description": "Ingest inputs, validate schema, normalize."},
                    {"id": "plan", "description": "Construct step plan with explicit I/O contracts."},
                    {"id": "execute", "description": "Perform steps, capture artifacts, stream status."},
                    {"id": "validate", "description": "Validate outputs, run quality gates and policies."},
                    {"id": "handoff", "description": "Emit final payloads and crew notifications."},
                ],
                "artifacts": [
                    "plan.md", "runlog.ndjson", "metrics.json"
                ],
                "error_policy": {
                    "retries": 2,
                    "backoff": "exponential",
                    "on_fail": "emit_incident"
                }
            }
            spit_json(wf, data)

    # Crew workflows
    crew_defs: Dict[str, Dict[str, Any]] = {
        "campaign_orchestration.json": {
            "name": "Campaign Orchestration",
            "stages": ["brief","produce","review","publish","retro"],
            "handoffs": ["content_delivery.json"]
        },
        "content_delivery.json": {
            "name": "Content Delivery",
            "stages": ["package","optimize","distribute","monitor"],
            "handoffs": []
        },
        "incident_response.json": {
            "name": "Incident Response",
            "stages": ["detect","triage","mitigate","postmortem"],
            "handoffs": []
        }
    }
    for fname, data in crew_defs.items():
        path = WF_CREW_DIR / fname
        if not path.exists():
            spit_json(path, {"version": "1.0", **data})

    # Global communication standards
    gstd = WF_GLOBAL_DIR / "global_communication_standards.json"
    if not gstd.exists():
        spit_json(gstd, {
            "version": "1.0",
            "naming": {
                "agents": "category-locked, purpose-descriptive; kebab-case slugs.",
                "files": "lowercase with dashes; no spaces."
            },
            "json_protocols": {
                "status": ["ok","warn","error"],
                "fields_required": ["agent_name","agent_id","category","llm_mapping","workflow_file"]
            },
            "error_handling": {
                "on_validation_failure": "emit incident to crew/incident_response.json",
                "retry_policy": {"retries": 2, "backoff": "exponential"}
            }
        })

def sanitize_agent_json(data: Dict[str, Any], slug: str) -> Dict[str, Any]:
    """
    Bring an agent JSON up to spec. Non-destructive: preserves unknown fields.
    """
    canon = AGENT_CANON.get(slug)
    if canon:
        data["display_name"] = canon["name"] # Use display_name as per create_agents.py
        data["category"] = canon["category"]
        # LLM mapping
        data.setdefault("llm_mapping", {})
        data["llm_mapping"]["primary"] = canon["primary_model"]
        data["llm_mapping"]["backup"] = canon["backup_model"]
        # Back-compat for earlier fields if present
        if "default_ggfu" in data: # Only update if it exists
            data["default_ggfu"] = canon["primary_model"]
        if "backup_ggfu" in data: # Only update if it exists
            data["backup_ggfu"] = canon["backup_model"]

    # Normalize required path fields
    data["environment_file"] = f"./agents/envs/{slug}.env"
    data["rules_file"] = f"./agents/rules/{slug}-rules.md"

    # Workflows
    category = data.get("category", "integration_points")
    data["workflow_file"] = f"./agents/workflow/agent/{category}_workflow.json"
    data["crew_workflows"] = [f"./agents/workflow/crew/{c}" for c in CREW_WORKFLOWS]
    data["global_standards_file"] = "./agents/workflow/global/global_communication_standards.json"

    # Remove any embedded giant prompt/master fields if they exist (user asked to keep these standalone)
    for k in ("global_system_prompt", "master_ruleset", "global_ruleset"):
        if k in data:
            del data[k]

    # Ensure we have a stable agent_id
    if "agent_id" not in data or not str(data["agent_id"]).strip():
        # Deterministic but stable ID based on slug; avoids churn.
        import uuid
        data["agent_id"] = str(uuid.uuid5(uuid.NAMESPACE_DNS, f"agents.{slug}"))

    return data

def update_env_for_slug(slug: str, agent_json: Dict[str, Any]) -> bool:
    env_path = ENVS_DIR / f"{slug}.env"
    if not env_path.exists():
        return False

    agent_id = str(agent_json.get("agent_id", "")).strip()
    agent_name = str(agent_json.get("agent_name", "")).strip()
    category = str(agent_json.get("category", "")).strip()
    llm = agent_json.get("llm_mapping", {})
    primary = str(llm.get("primary", "")).strip()
    backup = str(llm.get("backup", "")).strip()
    workflow_file = str(agent_json.get("workflow_file", "")).strip()

    updates = {
        "AGENT_ID": agent_id,
        "AGENT_NAME": agent_name,
        "AGENT_CATEGORY": category,
        "PRIMARY_MODEL": primary,
        "BACKUP_MODEL": backup,
        "WORKFLOW_FILE": workflow_file,
    }
    return env_update_preserve_order(env_path, updates)

def enforce_active_archive() -> Tuple[int, int]:
    """
    Keep only ONE agent json in ./agents/active. Prefer the one that looks like a starter.
    Move any extras to ./agents/archive. Returns (#kept, #moved)
    """
    ACTIVE_DIR.mkdir(parents=True, exist_ok=True)
    ARCHIVE_DIR.mkdir(parents=True, exist_ok=True)

    active_jsons = sorted([p for p in ACTIVE_DIR.glob("*.json") if p.is_file()])
    if len(active_jsons) <= 1:
        return (len(active_jsons), 0)

    # choose starter by name/slug heuristics
    def score(p: Path) -> int:
        try:
            data = slurp_json(p)
            name = str(data.get("agent_name",""))
        except Exception:
            name = p.stem
        # higher score = more likely starter
        s = 0
        if is_starter_name(name) or "starter" in p.stem.lower():
            s += 10
        # prefer smallest file as a tie-breaker (likely a template)
        s -= p.stat().st_size // 1024
        return s

    active_jsons.sort(key=score, reverse=True)
    # The first element is implicitly kept, so we don't need a 'keep' variable.
    moved = 0
    for extra in active_jsons[1:]:
        dest = ARCHIVE_DIR / extra.name
        shutil.move(str(extra), str(dest))
        moved += 1
    return (1, moved)

def process_agents() -> Dict[str, Any]:
    ensure_dirs()
    _load_agent_canon() # Load canonical agent data

    # Enforce active/archive rule first
    kept, moved = enforce_active_archive()

    json_paths = find_jsons()

    categories_in_use: List[str] = []
    updated_json_files = 0
    updated_env_files = 0
    untouched_envs: List[str] = []

    for path in json_paths:
        slug = guess_slug(path)
        try:
            data = slurp_json(path)
        except Exception as e:
            print(f"[WARN] Skipping unreadable JSON: {path} ({e})")
            continue

        before = json.dumps(data, sort_keys=True)
        data = sanitize_agent_json(data, slug)
        after = json.dumps(data, sort_keys=True)
        if before != after:
            spit_json(path, data)
            updated_json_files += 1

        if data.get("category"):
            categories_in_use.append(str(data["category"]))

        if update_env_for_slug(slug, data):
            updated_env_files += 1
        else:
            untouched_envs.append(slug)

    # Build workflows for all categories encountered (or at least from CANON if none found)
    if categories_in_use:
        ensure_workflows(categories_in_use)
    else:
        ensure_workflows([v["category"] for v in AGENT_CANON.values()])

    return {
        "active_kept": kept,
        "active_moved": moved,
        "jsons_seen": len(json_paths),
        "jsons_updated": updated_json_files,
        "envs_updated": updated_env_files,
        "envs_missing_or_untouched": untouched_envs,
    }

def main(argv: Optional[Sequence[str]] = None) -> int:
    parser = argparse.ArgumentParser(description="Finalize agents (update JSONs & .envs, add workflows).")
    _ = parser.parse_args(argv)
    result = process_agents()

    print("Finalize summary:")
    print(f"  - active kept:   {result['active_kept']}")
    print(f"  - active moved:  {result['active_moved']}")
    print(f"  - jsons seen:    {result['jsons_seen']}")
    print(f"  - jsons updated: {result['jsons_updated']}")
    print(f"  - envs updated:  {result['envs_updated']}")
    if result["envs_missing_or_untouched"]:
        print(f"  - envs untouched (missing or no changes): {', '.join(result['envs_missing_or_untouched'])}")
    else:
        print("  - envs untouched: none")
    print("")
    print("Workflows are in ./agents/workflow (agent/ crew/ global/).")
    return 0

if __name__ == "__main__":
    raise SystemExit(main())
