#!/usr/bin/env python3
"""
Environment validator for Hemlock health checks.

Verifies required and optional environment variables, API keys,
and configuration files are properly set.
"""

import json
import os
import sys
from pathlib import Path
from dataclasses import dataclass, asdict
from typing import List


@dataclass
class CheckResult:
    name: str
    status: str  # "ok", "warn", "fail"
    detail: str = ""
    path: str = ""


_ENV_REQUIRED = [
    ("PYTHONPATH", False, "Python import path"),
    ("HERMES_HOME", False, "Hermes runtime home directory"),
]

_ENV_OPTIONAL = [
    ("HEMLOCK_DOCKER", True, "Docker environment flag"),
    ("HERMES_AGENTS", True, "Agents directory override"),
    ("HERMES_CREWS", True, "Crews directory override"),
    ("HERMES_SKILLS", True, "Skills directory override"),
    ("HERMES_LOGS", True, "Logs directory override"),
    ("HERMES_MEMORY", True, "Memory directory override"),
    ("HERMES_CONFIG", True, "Config directory override"),
    ("ENABLE_PERSISTENT_MEMORY", True, "Persistent memory flag"),
    ("ENABLE_AGENT_RESURRECTION", True, "Agent resurrection flag"),
    ("ENABLE_CONTINUOUS_RUNTIME", True, "Continuous runtime flag"),
    ("ENABLE_SKILL_LEARNING", True, "Skill learning flag"),
]

_API_KEY_VARS = [
    ("OPENROUTER_API_KEY", "OpenRouter"),
    ("OPENAI_API_KEY", "OpenAI"),
    ("ANTHROPIC_API_KEY", "Anthropic"),
    ("ANTHROPIC_TOKEN", "Anthropic OAuth"),
    ("TELEGRAM_BOT_TOKEN", "Telegram"),
    ("DISCORD_BOT_TOKEN", "Discord"),
    ("GITHUB_TOKEN", "GitHub"),
]


def run_env_checks(fix: bool = False) -> List[CheckResult]:
    results: List[CheckResult] = []

    try:
        from paths import resolver
    except ImportError:
        results.append(CheckResult("env_paths_import", "fail", "Cannot import PathResolver"))
        return results

    results.append(CheckResult("env_python_version", "ok",
                 f"Python {sys.version_info.major}.{sys.version_info.minor}.{sys.version_info.micro}"))

    for var_name, optional, desc in _ENV_REQUIRED:
        val = os.getenv(var_name)
        if val:
            display = val if len(val) < 60 else val[:57] + "..."
            results.append(CheckResult(f"env_{var_name.lower()}", "ok", f"{desc}: {display}"))
        else:
            results.append(CheckResult(f"env_{var_name.lower()}", "warn",
                         f"{desc}: not set (optional in Docker)"))

    for var_name, optional, desc in _ENV_OPTIONAL:
        val = os.getenv(var_name)
        if val:
            results.append(CheckResult(f"env_{var_name.lower()}", "ok", f"{desc}: set"))
        else:
            results.append(CheckResult(f"env_{var_name.lower()}", "ok",
                         f"{desc}: not set (using default)"))

    has_provider = False
    for var_name, provider in _API_KEY_VARS:
        val = os.getenv(var_name)
        if val:
            has_provider = True
            results.append(CheckResult(f"apikey_{var_name.lower()}", "ok",
                         f"{provider}: configured"))
        else:
            results.append(CheckResult(f"apikey_{var_name.lower()}", "ok",
                         f"{provider}: not set (optional)"))

    if not has_provider:
        results.append(CheckResult("apikey_any", "warn",
                     "No API keys configured — agent will need setup before first use"))
    else:
        results.append(CheckResult("apikey_any", "ok", "At least one API key configured"))

    config_dir = resolver.config_dir
    config_path = config_dir / "config.yaml"
    if config_path.exists():
        results.append(CheckResult("env_config_file", "ok", f"Config file: {config_path}"))
        try:
            import yaml
            with open(config_path) as f:
                cfg = yaml.safe_load(f) or {}
            model = cfg.get("model")
            if model:
                if isinstance(model, dict):
                    provider = model.get("provider", "unknown")
                    default = model.get("default", "unknown")
                    results.append(CheckResult("env_config_model", "ok",
                                 f"Provider: {provider}, Model: {default}"))
                else:
                    results.append(CheckResult("env_config_model", "ok", f"Model: {model}"))
            else:
                results.append(CheckResult("env_config_model", "warn", "No model configured"))
        except Exception as e:
            results.append(CheckResult("env_config_parse", "warn", f"Config parse error: {e}"))
    else:
        results.append(CheckResult("env_config_file", "warn", f"No config file at {config_path}"))

    home = resolver.hermes_home
    env_file = home / ".env"
    if env_file.exists():
        results.append(CheckResult("env_dot_env", "ok", f".env file: {env_file}"))
    else:
        if fix:
            try:
                env_file.parent.mkdir(parents=True, exist_ok=True)
                env_file.touch()
                results.append(CheckResult("env_dot_env", "ok", f"Created .env: {env_file}"))
            except PermissionError:
                results.append(CheckResult("env_dot_env", "fail",
                             f"Cannot create .env (permission denied): {env_file}"))
        else:
            results.append(CheckResult("env_dot_env", "warn", f"No .env file at {env_file}"))

    return results


def main():
    fix = "--fix" in sys.argv
    results = run_env_checks(fix=fix)

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