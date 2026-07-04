#!/usr/bin/env python3
"""
Key Injection - Maps OpenClaw config to Hermes .env and secrets storage.

Reads OpenClaw configuration and injects API keys, tokens, and settings
into the Hermes agent's environment files. Keys are stored as JSON in
.secrets/ (never plaintext in .env for sensitive tokens).

Usage:
    # From OpenClaw onboarding (silent):
    python3 -m scripts.key_inject --from-openclaw

    # From a JSON config file:
    python3 -m scripts.key_inject --from-file path/to/config.json

    # As a library:
    from scripts.key_inject import inject_keys, KeyMapping
"""

import json
import os
import sys
from pathlib import Path
from dataclasses import dataclass, asdict, field
from typing import Dict, List, Optional, Tuple


@dataclass
class KeyMapping:
    openclaw_key: str
    hermes_env_var: str
    secret: bool = True
    description: str = ""


# OpenClaw → Hermes key mappings
# OpenClaw config keys → Hermes environment variables
KEY_MAPPINGS: List[KeyMapping] = [
    # Primary inference providers
    KeyMapping("openrouter.api_key", "OPENROUTER_API_KEY", True, "OpenRouter API key"),
    KeyMapping("openai.api_key", "OPENAI_API_KEY", True, "OpenAI API key"),
    KeyMapping("anthropic.api_key", "ANTHROPIC_API_KEY", True, "Anthropic API key"),
    KeyMapping("anthropic.token", "ANTHROPIC_TOKEN", True, "Anthropic OAuth token"),

    # Messaging platforms
    KeyMapping("telegram.bot_token", "TELEGRAM_BOT_TOKEN", True, "Telegram bot token"),
    KeyMapping("discord.bot_token", "DISCORD_BOT_TOKEN", True, "Discord bot token"),
    KeyMapping("discord.application_id", "DISCORD_APPLICATION_ID", False, "Discord application ID"),
    KeyMapping("whatsapp.enabled", "WHATSAPP_ENABLED", False, "WhatsApp enable flag"),
    KeyMapping("whatsapp.allowed_users", "WHATSAPP_ALLOWED_USERS", False, "WhatsApp allowed users"),

    # Web/Search tools
    KeyMapping("exa.api_key", "EXA_API_KEY", True, "Exa search API key"),
    KeyMapping("firecrawl.api_key", "FIRECRAWL_API_KEY", True, "Firecrawl API key"),
    KeyMapping("tavily.api_key", "TAVILY_API_KEY", True, "Tavily search API key"),
    KeyMapping("github.token", "GITHUB_TOKEN", True, "GitHub personal access token"),

    # AI providers (additional)
    KeyMapping("glm.api_key", "GLM_API_KEY", True, "GLM/Z.AI API key"),
    KeyMapping("kimi.api_key", "KIMI_API_KEY", True, "Kimi API key"),
    KeyMapping("minimax.api_key", "MINIMAX_API_KEY", True, "MiniMax API key"),
    KeyMapping("deepseek.api_key", "DEEPSEEK_API_KEY", True, "DeepSeek API key"),
    KeyMapping("dashscope.api_key", "DASHSCOPE_API_KEY", True, "Alibaba DashScope API key"),
    KeyMapping("huggingface.token", "HF_TOKEN", True, "Hugging Face token"),

    # Voice/TTS
    KeyMapping("elevenlabs.api_key", "ELEVENLABS_API_KEY", True, "ElevenLabs API key"),

    # Browser automation
    KeyMapping("browserbase.api_key", "BROWSERBASE_API_KEY", True, "Browserbase API key"),
    KeyMapping("browserbase.project_id", "BROWSERBASE_PROJECT_ID", False, "Browserbase project ID"),

    # Infrastructure
    KeyMapping("inference.provider", "HERMES_INFERENCE_PROVIDER", False, "Inference provider"),
    KeyMapping("inference.base_url", "OPENAI_BASE_URL", False, "Custom inference base URL"),
    KeyMapping("inference.model", "HERMES_DEFAULT_MODEL", False, "Default model name"),
]


def _resolve_hermes_home() -> Path:
    """Resolve the Hermes home directory."""
    home = os.getenv("HERMES_HOME")
    if home:
        return Path(home)

    try:
        from paths import resolver
        return resolver.hermes_home
    except ImportError:
        pass

    docker_home = Path("/runtime")
    if docker_home.exists():
        return docker_home

    return Path.home() / ".hermes"


def _resolve_openclaw_config() -> Optional[Path]:
    """Find the OpenClaw configuration file."""
    candidates = [
        Path(os.getenv("OPENCLAW_CONFIG", "")),
        Path.home() / ".openclaw" / "openclaw.json",
        Path.home() / ".openclaw" / "openclaw.jsonc",
        Path("/etc/openclaw/openclaw.json"),
    ]

    for path in candidates:
        if path.exists() and str(path) != ".":
            return path

    return None


def load_openclaw_config(config_path: Optional[Path] = None) -> Dict:
    """Load OpenClaw configuration from JSON/JSON5 file.

    Handles both standard JSON and JSON5 (with comments and trailing commas).
    """
    if config_path is None:
        config_path = _resolve_openclaw_config()

    if config_path is None or not config_path.exists():
        return {}

    content = config_path.read_text(encoding="utf-8")

    # Try parsing as standard JSON first
    try:
        return json.loads(content)
    except json.JSONDecodeError as e:
        # Fallback: JSON5 processing for comments and trailing commas
        import re
        content = re.sub(r'//.*$', '', content, flags=re.MULTILINE)
        content = re.sub(r'/\*.*?\*/', '', content, flags=re.DOTALL)
        content = re.sub(r',\s*([}\]])', r'\1', content)
        try:
            return json.loads(content)
        except json.JSONDecodeError as e2:
            return {}


def _get_nested_value(data: Dict, key_path: str, default=None):
    """Get a value from nested dict using dot-separated key path."""
    keys = key_path.split(".")
    current = data
    for key in keys:
        if isinstance(current, dict) and key in current:
            current = current[key]
        else:
            return default
    return current


def inject_keys(
    config: Dict,
    hermes_home: Optional[Path] = None,
    dry_run: bool = False,
) -> Tuple[int, int, List[str]]:
    """Inject keys from OpenClaw config into Hermes environment.

    Args:
        config: OpenClaw configuration dict (nested keys with dot notation)
        hermes_home: Target Hermes home directory (auto-detected if None)
        dry_run: If True, don't write anything, just report

    Returns:
        Tuple of (injected_count, skipped_count, messages)
    """
    if hermes_home is None:
        hermes_home = _resolve_hermes_home()

    messages = []
    injected = 0
    skipped = 0

    env_vars = {}
    secrets = {}

    for mapping in KEY_MAPPINGS:
        value = _get_nested_value(config, mapping.openclaw_key)
        if value is None:
            continue

        value_str = str(value)
        if not value_str.strip():
            continue

        if mapping.secret:
            secrets[mapping.hermes_env_var] = value_str
        else:
            env_vars[mapping.hermes_env_var] = value_str

    # Write non-secret vars to .env
    env_path = hermes_home / ".env"
    existing_env = {}
    if env_path.exists():
        for line in env_path.read_text(encoding="utf-8").splitlines():
            line = line.strip()
            if line and not line.startswith("#") and "=" in line:
                k, _, v = line.partition("=")
                existing_env[k.strip()] = v.strip().strip("'\"")

    # Merge: OpenClaw values take precedence
    merged_env = {**existing_env, **env_vars}

    if not dry_run:
        env_path.parent.mkdir(parents=True, exist_ok=True)
        lines = []
        for k, v in sorted(merged_env.items()):
            if v and not any(c in v for c in ' "\\' ):
                lines.append(f"{k}={v}")
            else:
                escaped = v.replace("\\", "\\\\").replace('"', '\\"')
                lines.append(f'{k}="{escaped}"')
        env_path.write_text("\n".join(lines) + "\n", encoding="utf-8")
        messages.append(f"Wrote {len(env_vars)} env var(s) to {env_path}")
    else:
        messages.append(f"[DRY RUN] Would write {len(env_vars)} env var(s) to {env_path}")

    injected += len(env_vars)

    # Write secrets to .secrets/ as JSON (per constraint: secrets never in .env directly)
    secrets_dir = hermes_home / ".secrets"
    if secrets:
        if not dry_run:
            secrets_dir.mkdir(parents=True, exist_ok=True)

            # Main secrets JSON — all sensitive values in one place
            secrets_file = secrets_dir / "secrets.json"
            existing_secrets = {}
            if secrets_file.exists():
                try:
                    existing_secrets = json.loads(secrets_file.read_text(encoding="utf-8"))
                except (json.JSONDecodeError, OSError):
                    pass

            merged_secrets = {**existing_secrets, **secrets}
            secrets_file.write_text(
                json.dumps(merged_secrets, indent=2, sort_keys=True),
                encoding="utf-8"
            )
            secrets_file.chmod(0o600)

            # Write individual secret files for shell source compatibility
            for key, value in secrets.items():
                secret_file = secrets_dir / key.lower()
                secret_file.write_text(value, encoding="utf-8")
                secret_file.chmod(0o600)

            messages.append(f"Wrote {len(secrets)} secret(s) to {secrets_dir}")
        else:
            messages.append(f"[DRY RUN] Would write {len(secrets)} secret(s) to {secrets_dir}")

        injected += len(secrets)
    else:
        messages.append("No secrets to inject")
        skipped += len([m for m in KEY_MAPPINGS if m.secret])

    # Inject model config into Hermes config.yaml
    model_config = {}
    provider = _get_nested_value(config, "inference.provider")
    base_url = _get_nested_value(config, "inference.base_url")
    model_name = _get_nested_value(config, "inference.model")

    if provider or base_url or model_name:
        model_config = {}
        if model_name:
            model_config["default"] = model_name
        if provider:
            model_config["provider"] = provider
        if base_url:
            model_config["base_url"] = base_url

    if model_config and not dry_run:
        config_path = hermes_home / "config.yaml"
        existing_yaml = {}
        if config_path.exists():
            try:
                import yaml
                existing_yaml = yaml.safe_load(config_path.read_text(encoding="utf-8")) or {}
            except Exception:
                pass

        existing_yaml["model"] = model_config

        if not dry_run:
            try:
                import yaml
                config_path.parent.mkdir(parents=True, exist_ok=True)
                config_path.write_text(
                    yaml.dump(existing_yaml, default_flow_style=False, sort_keys=False),
                    encoding="utf-8"
                )
                messages.append(f"Wrote model config to {config_path}")
            except ImportError:
                # Fallback: write as JSON-like YAML manually
                config_path.parent.mkdir(parents=True, exist_ok=True)
                lines = ["# Auto-configured by key_inject from OpenClaw", ""]
                lines.append("model:")
                for k, v in model_config.items():
                    lines.append(f"  {k}: {v}")
                config_path.write_text("\n".join(lines) + "\n", encoding="utf-8")
                messages.append(f"Wrote model config to {config_path} (yaml fallback)")
    elif model_config and dry_run:
        messages.append(f"[DRY RUN] Would write model config: {model_config}")

    skipped_count = sum(1 for m in KEY_MAPPINGS
                        if _get_nested_value(config, m.openclaw_key) is None)
    skipped += skipped_count - (len(KEY_MAPPINGS) - injected)

    return injected, skipped, messages


def main():
    """CLI entry point for key injection."""
    import argparse

    parser = argparse.ArgumentParser(description="Inject keys from OpenClaw config to Hermes")
    parser.add_argument("--from-openclaw", action="store_true",
                       help="Load config from OpenClaw configuration file")
    parser.add_argument("--from-file", type=Path,
                       help="Load config from a JSON file")
    parser.add_argument("--hermes-home", type=Path,
                       help="Target Hermes home directory (auto-detected if not specified)")
    parser.add_argument("--dry-run", action="store_true",
                       help="Show what would be done without writing anything")
    parser.add_argument("--json", action="store_true",
                       help="Output results as JSON")
    args = parser.parse_args()

    config: Dict = {}

    if args.from_file:
        if not args.from_file.exists():
            print(f"Error: Config file not found: {args.from_file}", file=sys.stderr)
            sys.exit(1)
        config = load_openclaw_config(args.from_file)
    elif args.from_openclaw:
        config_path = _resolve_openclaw_config()
        if config_path is None:
            print("Error: No OpenClaw configuration found", file=sys.stderr)
            print("  Looked in: ~/.openclaw/openclaw.json, /etc/openclaw/openclaw.json",
                  file=sys.stderr)
            sys.exit(1)
        config = load_openclaw_config(config_path)
    else:
        # Try OpenClaw config as default
        config_path = _resolve_openclaw_config()
        if config_path:
            config = load_openclaw_config(config_path)

    if not config:
        print("No configuration found. Use --from-openclaw or --from-file.", file=sys.stderr)
        sys.exit(1)

    hermes_home = args.hermes_home or _resolve_hermes_home()
    injected, skipped, messages = inject_keys(config, hermes_home, dry_run=args.dry_run)

    if args.json:
        result = {
            "injected": injected,
            "skipped": skipped,
            "messages": messages,
            "hermes_home": str(hermes_home),
        }
        print(json.dumps(result, indent=2))
    else:
        for msg in messages:
            print(f"  {msg}")
        print(f"\n  Injected: {injected} key(s), Skipped: {skipped}")

    sys.exit(0)


if __name__ == "__main__":
    main()