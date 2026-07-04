#!/usr/bin/env python3
"""
Agent identity validator for Hemlock health checks.

Verifies agent identity files, builder codes, and persona configuration.
"""

import json
import sys
from pathlib import Path
from dataclasses import dataclass, asdict
from typing import List, Optional


@dataclass
class CheckResult:
    name: str
    status: str  # "ok", "warn", "fail"
    detail: str = ""
    path: str = ""


_IDENTITY_FILES = [
    ("SOUL.md", True, "Agent persona/soul file"),
    ("USER.md", False, "User description file"),
    ("AGENTS.md", False, "Multi-agent context file"),
    ("IDENTITY.md", True, "Agent identity definition"),
    ("TOOLS.md", False, "Available tools manifest"),
    ("HEARTBEAT.md", False, "Agent heartbeat config"),
]

_REQUIRED_AGENT_JSON_KEYS = ["builderCode"]


def run_agent_identity_checks(
    agent_id: Optional[str] = None,
    fix: bool = False,
) -> List[CheckResult]:
    results: List[CheckResult] = []

    try:
        from paths import resolver
    except ImportError:
        results.append(CheckResult("agent_paths_import", "fail", "Cannot import PathResolver"))
        return results

    if agent_id:
        agent_dir = resolver.agents_dir / agent_id
    else:
        agent_id = os.getenv("AGENT_ID", "")
        if agent_id:
            agent_dir = resolver.agents_dir / agent_id
        else:
            agent_dir = resolver.hermes_home

    results.append(CheckResult("agent_dir", "ok" if agent_dir.exists() else "warn",
                 f"Agent directory: {agent_dir}", str(agent_dir)))

    if not agent_dir.exists():
        if fix:
            try:
                agent_dir.mkdir(parents=True, exist_ok=True)
                results.append(CheckResult("agent_dir_create", "ok",
                             f"Created: {agent_dir}", str(agent_dir)))
            except PermissionError:
                results.append(CheckResult("agent_dir_create", "fail",
                             f"Permission denied: {agent_dir}", str(agent_dir)))
                return results
        else:
            results.append(CheckResult("agent_dir_missing", "warn",
                         f"Does not exist: {agent_dir}", str(agent_dir)))
            return results

    for filename, required, desc in _IDENTITY_FILES:
        filepath = agent_dir / filename
        if filepath.exists():
            content = filepath.read_text(encoding="utf-8").strip()
            line_count = len([l for l in content.splitlines() if l.strip() and not l.strip().startswith("#")])
            results.append(CheckResult(
                f"identity_{filename.lower().replace('.', '_')}",
                "ok",
                f"{desc}: {line_count} content lines",
                str(filepath)
            ))
        else:
            if fix:
                try:
                    filepath.parent.mkdir(parents=True, exist_ok=True)
                    filepath.write_text(f"# {filename.replace('.md', '')} — {agent_id or 'agent'}\n",
                                       encoding="utf-8")
                    results.append(CheckResult(
                        f"identity_{filename.lower().replace('.', '_')}",
                        "ok",
                        f"Created stub: {filepath}",
                        str(filepath)
                    ))
                except PermissionError:
                    results.append(CheckResult(
                        f"identity_{filename.lower().replace('.', '_')}",
                        "warn" if not required else "fail",
                        f"Cannot create (permission denied): {filepath}",
                        str(filepath)
                    ))
            else:
                results.append(CheckResult(
                    f"identity_{filename.lower().replace('.', '_')}",
                    "warn" if not required else "fail",
                    f"Missing {desc}",
                    str(filepath)
                ))

    agent_json = agent_dir / "agent.json"
    if agent_json.exists():
        try:
            data = json.loads(agent_json.read_text(encoding="utf-8"))
            results.append(CheckResult("agent_json", "ok",
                         f"Agent JSON loaded ({len(data)} keys)", str(agent_json)))

            for key in _REQUIRED_AGENT_JSON_KEYS:
                if key in data:
                    results.append(CheckResult(f"agent_json_{key.lower()}", "ok",
                                 f"Key '{key}' present"))
                else:
                    results.append(CheckResult(f"agent_json_{key.lower()}", "warn",
                                 f"Key '{key}' missing from agent.json"))

            if "builderCode" in data:
                bc = data["builderCode"]
                if isinstance(bc, dict):
                    code = bc.get("code", "")
                    results.append(CheckResult("agent_builder_code", "ok",
                                 f"Builder code: {code[:20]}..." if len(code) > 20 else f"Builder code: {code}"))
                elif isinstance(bc, str):
                    results.append(CheckResult("agent_builder_code", "ok",
                                 f"Builder code: {bc[:20]}..." if len(bc) > 20 else f"Builder code: {bc}"))
        except json.JSONDecodeError as e:
            results.append(CheckResult("agent_json", "fail", f"Invalid JSON: {e}", str(agent_json)))
    else:
        if fix:
            try:
                agent_json.parent.mkdir(parents=True, exist_ok=True)
                default_data = {
                    "builderCode": {
                        "code": "bc_default",
                        "hex": "0x62635f64656661756c74",
                        "owner": "0x0000000000000000000000000000000000000000",
                        "hardwired": True,
                        "enforced": True,
                    }
                }
                agent_json.write_text(json.dumps(default_data, indent=2), encoding="utf-8")
                results.append(CheckResult("agent_json", "ok",
                             f"Created default agent.json", str(agent_json)))
            except PermissionError:
                results.append(CheckResult("agent_json", "fail",
                             f"Cannot create (permission denied)", str(agent_json)))
        else:
            results.append(CheckResult("agent_json", "warn",
                         f"No agent.json found", str(agent_json)))

    config_yaml = agent_dir / "config.yaml"
    if config_yaml.exists():
        try:
            import yaml
            cfg = yaml.safe_load(config_yaml.read_text(encoding="utf-8")) or {}
            model = cfg.get("model")
            if isinstance(model, dict):
                provider = model.get("provider", "unknown")
                default = model.get("default", "unknown")
                results.append(CheckResult("agent_config_model", "ok",
                             f"Provider: {provider}, Model: {default}", str(config_yaml)))
            elif isinstance(model, str) and model:
                results.append(CheckResult("agent_config_model", "ok",
                             f"Model: {model}", str(config_yaml)))
            else:
                results.append(CheckResult("agent_config_model", "warn",
                             "No model configured in config.yaml", str(config_yaml)))

            tools_profile = cfg.get("tools", {}).get("profile", "")
            if tools_profile:
                results.append(CheckResult("agent_config_tools", "ok",
                             f"Tools profile: {tools_profile}"))
            memory_enabled = cfg.get("memory", {}).get("enabled", True)
            results.append(CheckResult("agent_config_memory", "ok",
                         f"Memory: {'enabled' if memory_enabled else 'disabled'}"))
        except Exception as e:
            results.append(CheckResult("agent_config_parse", "warn",
                         f"Config parse error: {e}", str(config_yaml)))
    else:
        results.append(CheckResult("agent_config", "warn",
                     f"No config.yaml found", str(config_yaml)))

    return results


import os

def main():
    fix = "--fix" in sys.argv
    agent_id = None
    for i, arg in enumerate(sys.argv):
        if arg == "--agent-id" and i + 1 < len(sys.argv):
            agent_id = sys.argv[i + 1]

    results = run_agent_identity_checks(agent_id=agent_id, fix=fix)

    if "--json" in sys.argv:
        print(json.dumps([asdict(r) for r in results], indent=2))
    else:
        for r in results:
            icon = {"ok": "\u2713", "warn": "\u26a0", "fail": "\u2717"}[r.status]
            print(f"  {icon} {r.name}: {r.detail}")

    failed = sum(1 for r in results if r.status == "fail")
    sys.exit(1 if failed else 0)


if __name__ == "__main__":
    main()