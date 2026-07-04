#!/usr/bin/env python3
"""
Gateway connectivity validator for Hemlock health checks.

Verifies gateway platform adapters can be loaded, messaging configs
are present, and the gateway can bind to its required port.
"""

import json
import os
import socket
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


def run_gateway_checks(fix: bool = False) -> List[CheckResult]:
    results: List[CheckResult] = []

    try:
        from paths import resolver
    except ImportError:
        results.append(CheckResult("gw_paths_import", "fail", "Cannot import PathResolver"))
        return results

    results.append(CheckResult("gw_paths_import", "ok", "PathResolver imported"))

    try:
        from gateway.protocol import GatewayMessage
        results.append(CheckResult("gw_protocol_import", "ok", "Gateway protocol imported"))
    except ImportError as e:
        results.append(CheckResult("gw_protocol_import", "fail", f"Cannot import GatewayMessage: {e}"))

    try:
        from gateway.config import load_gateway_config, Platform
        results.append(CheckResult("gw_config_import", "ok", "Gateway config imported"))

        try:
            cfg = load_gateway_config()
            if cfg:
                platforms = []
                if isinstance(cfg, dict):
                    platforms = list(cfg.get("platforms", {}).keys()) if "platforms" in cfg else []
                results.append(CheckResult("gw_config_loaded", "ok",
                             f"Gateway config loaded: {len(platforms)} platform(s): {platforms}"))
            else:
                results.append(CheckResult("gw_config_loaded", "warn", "No gateway config found"))
        except Exception as e:
            results.append(CheckResult("gw_config_loaded", "warn", f"Config load error: {e}"))
    except ImportError as e:
        results.append(CheckResult("gw_config_import", "warn",
                     f"Gateway config import failed: {e}"))

    try:
        from gateway.run import GatewayRunner
        results.append(CheckResult("gw_runner_import", "ok", "GatewayRunner imported"))
    except ImportError as e:
        results.append(CheckResult("gw_runner_import", "warn",
                     f"GatewayRunner import failed: {e}"))

    platform_modules = {
        "telegram": ("gateway.platforms.telegram_adapter", "TelegramAdapter"),
        "discord": ("gateway.platforms.discord_adapter", "DiscordAdapter"),
        "whatsapp": ("gateway.platforms.whatsapp_adapter", "WhatsAppAdapter"),
        "webhook": ("gateway.platforms.webhook_adapter", "WebhookAdapter"),
    }

    available_platforms = []
    for name, (module_path, class_name) in platform_modules.items():
        try:
            mod = __import__(module_path, fromlist=[class_name])
            adapter_cls = getattr(mod, class_name, None)
            available_platforms.append(name)
            results.append(CheckResult(f"gw_platform_{name}", "ok",
                         f"{class_name} available"))
        except ImportError as e:
            results.append(CheckResult(f"gw_platform_{name}", "ok",
                         f"{name} adapter not installed (optional): {e}"))
        except AttributeError:
            results.append(CheckResult(f"gw_platform_{name}", "ok",
                         f"{name} module imported but class not found (optional)"))

    port = int(os.getenv("GATEWAY_PORT", "1437"))
    try:
        test_socket = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        test_socket.settimeout(2)
        test_socket.bind(("127.0.0.1", port))
        test_socket.close()
        results.append(CheckResult("gw_port_available", "ok",
                     f"Port {port} available for gateway"))
    except OSError:
        try:
            test_socket = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
            test_socket.settimeout(2)
            test_socket.connect(("127.0.0.1", port))
            test_socket.close()
            results.append(CheckResult("gw_port_available", "warn",
                         f"Port {port} already in use (gateway may be running)"))
        except (ConnectionRefusedError, OSError):
            results.append(CheckResult("gw_port_available", "fail",
                         f"Port {port} unavailable and not connectable"))

    home = resolver.hermes_home
    pairing_path = home / "state.db"
    if pairing_path.exists():
        results.append(CheckResult("gw_state_db", "ok",
                     f"State DB: {pairing_path}"))
        try:
            import sqlite3
            conn = sqlite3.connect(str(pairing_path))
            cursor = conn.execute("SELECT COUNT(*) FROM sessions")
            count = cursor.fetchone()[0]
            conn.close()
            results.append(CheckResult("gw_sessions_count", "ok",
                         f"Sessions DB has {count} session(s)"))
        except Exception as e:
            results.append(CheckResult("gw_sessions_count", "warn",
                         f"State DB query failed: {e}"))
    else:
        results.append(CheckResult("gw_state_db", "ok",
                     "State DB not yet created (will be created on first run)"))

    env_vars = ["TELEGRAM_BOT_TOKEN", "DISCORD_BOT_TOKEN", "WHATSAPP_ENABLED"]
    for var in env_vars:
        val = os.getenv(var)
        if val:
            results.append(CheckResult(f"gw_env_{var.lower()}", "ok", f"{var}: configured"))
        else:
            results.append(CheckResult(f"gw_env_{var.lower()}", "ok",
                         f"{var}: not set (optional)"))

    return results


def main():
    fix = "--fix" in sys.argv
    results = run_gateway_checks(fix=fix)

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