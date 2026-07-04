#!/usr/bin/env python3
"""
Patches hermes gateway to add:
  1. !command shell execution (type !ls, !git status, etc.)
  2. /models command (list all providers and available models)
"""

import re
from pathlib import Path

gateway_run = Path("/app/hermes-agent/gateway/run.py")
commands_file = Path("/app/hermes-agent/hermes_cli/commands.py")

# ── 1. Add !command handler ─────────────────────────────────────────────────
content = gateway_run.read_text()

marker = 'from hermes_cli.commands import GATEWAY_KNOWN_COMMANDS, resolve_command as _resolve_cmd'
if marker in content and "!command" not in content:
    bang_handler = r'''
        # --- !command: execute shell commands directly ---
        if event.text and event.text.strip().startswith("!"):
            shell_cmd = event.text.strip()[1:].strip()
            if shell_cmd:
                import subprocess
                try:
                    result = subprocess.run(
                        ["bash", "-lc", shell_cmd],
                        capture_output=True, text=True, timeout=30,
                    )
                    output = (result.stdout + result.stderr).strip()
                    if not output:
                        output = "(exit code: %d)" % result.returncode
                    if len(output) > 4000:
                        output = output[:4000] + "... (truncated)"
                    return "```\n" + output + "\n```"
                except subprocess.TimeoutExpired:
                    return "Command timed out after 30s"
                except Exception as e:
                    return "Error: %s" % e
        # --- End !command ---
'''
    content = content.replace(marker, bang_handler + "        " + marker)
    print("OK: Added !command handler")
else:
    print("SKIP: !command handler exists or marker not found")

# ── 2. Add /models command handler ──────────────────────────────────────────
if 'canonical == "models"' not in content:
    model_marker = 'if canonical == "model":'
    models_handler = r'''
        # --- /models: list all providers and available models ---
        if canonical == "models":
            import yaml

            lines = ["**Available Models**\n"]
            config_path = _hermes_home / "config.yaml"

            current_model = ""
            current_provider = ""
            providers_cfg = {}
            if config_path.exists():
                try:
                    with open(config_path) as f:
                        cfg = yaml.safe_load(f) or {}
                    model_cfg = cfg.get("model", {})
                    if isinstance(model_cfg, dict):
                        current_model = model_cfg.get("default", "")
                        current_provider = model_cfg.get("provider", "")
                    providers_cfg = cfg.get("models", {}).get("providers", {})
                    if not providers_cfg:
                        for key in ["nous", "mistral", "openai", "anthropic", "openrouter", "ollama"]:
                            if key in cfg and isinstance(cfg[key], dict):
                                providers_cfg[key] = cfg[key]
                except Exception:
                    pass

            if current_model:
                lines.append("Current: `%s/%s`\n" % (current_provider, current_model))

            if not providers_cfg:
                lines.append("No providers configured in config.yaml.")
                return "\n".join(lines)

            for prov_name, prov in providers_cfg.items():
                if not isinstance(prov, dict):
                    continue
                models = prov.get("models", [])
                base_url = prov.get("baseUrl", prov.get("base_url", ""))
                has_key = bool(prov.get("apiKey", prov.get("api_key", "")))
                status = "ok" if has_key else "no key"
                lines.append("**%s** (%s)" % (prov_name, status))
                if base_url:
                    lines.append("  `%s`" % base_url[:50])
                for m in models:
                    if isinstance(m, dict):
                        mid = m.get("id", "?")
                    else:
                        mid = str(m)
                    marker = " <--" if "%s/%s" % (prov_name, mid) == "%s/%s" % (current_provider, current_model) else ""
                    lines.append("  - `%s`%s" % (mid, marker))
                if not models:
                    lines.append("  (no models listed)")
                lines.append("")

            return "\n".join(lines)
        # --- End /models ---
'''
    if model_marker in content:
        pos = content.find(model_marker)
        next_handler = content.find('\n        if canonical =', pos + len(model_marker))
        if next_handler == -1:
            next_handler = content.find('\n        # ---', pos + len(model_marker))
        if next_handler != -1:
            content = content[:next_handler] + '\n' + models_handler + content[next_handler:]
            print("OK: Added /models handler")
        else:
            print("FAIL: Could not find end of /model handler")
    else:
        print("FAIL: /model handler not found")
else:
    print("SKIP: /models handler exists")

gateway_run.write_text(content)

# ── 3. Add /models to command registry ──────────────────────────────────────
cmd_content = commands_file.read_text()
if '"models"' not in cmd_content:
    old = 'CommandDef("yolo", "Toggle YOLO mode (skip all dangerous command approvals)",'
    new = old + '\n    CommandDef("models", "List all providers and available models", "Info"),'
    if old in cmd_content:
        cmd_content = cmd_content.replace(old, new)
        commands_file.write_text(cmd_content)
        print("OK: Added /models to command registry")
    else:
        print("FAIL: yolo command not found")
else:
    print("SKIP: /models in registry")

print("Patch complete")
