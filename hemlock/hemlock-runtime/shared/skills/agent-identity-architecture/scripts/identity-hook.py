#!/usr/bin/env python3
"""
identity-hook.py — Universal tool execution hook for agent identity layer.

Supports: Claude Code, Cursor, Gemini CLI, Hermes, OpenCode, and generic frameworks.

Protocol:
  - Receives JSON on stdin with tool call details
  - Validates through enforcer daemon
  - Returns allow/deny/rewrite in the framework's native format

Usage:
  # Generic (default) — returns JSON to stdout
  echo '{"event":"pre_tool_use","tool":"exec","params":{...}}' | python3 identity-hook.py

  # Claude Code / Cursor / Gemini — exit code 0=allow, 2=block
  echo '{"hook_event_name":"PreToolUse","tool_name":"Bash","tool_input":{...}}' | python3 identity-hook.py --framework claude

  # Hermes — plugin hook format
  echo '{"tool_name":"terminal","args":{"command":"ls"}}' | python3 identity-hook.py --framework hermes

  # OpenCode — plugin hook format
  echo '{"tool":"bash","args":{"command":"ls"}}' | python3 identity-hook.py --framework opencode

  # Auto-detect framework from input
  echo '{"hook_event_name":"PreToolUse",...}' | python3 identity-hook.py --auto
"""

import asyncio
import json
import os
import sys
import argparse
from pathlib import Path
from datetime import datetime, timezone

# Self-resolving paths
SCRIPT_DIR = Path(__file__).parent.resolve()
WORKSPACE = SCRIPT_DIR.parent if (SCRIPT_DIR / ".agent").exists() else SCRIPT_DIR
ENFORCER_SOCKET = Path(os.environ.get("ENFORCER_SOCKET_DIR", str(Path.home() / "run" / "agent-enforcer"))) / "main.sock"
AUDIT_LOG = Path(os.environ.get("ENFORCER_LOG_DIR", str(Path.home() / "var" / "log" / "agent-enforcer"))) / "tool-audit.jsonl"


# ─── Framework Adapters ───────────────────────────────────────────────────────

def normalize_input(payload: dict, framework: str) -> dict:
    """Convert framework-specific input to unified format."""
    if framework == "claude":
        return {
            "tool": payload.get("tool_name", "unknown"),
            "params": payload.get("tool_input", {}),
            "event": payload.get("hook_event_name", "PreToolUse").lower(),
            "session_id": payload.get("session_id"),
            "cwd": payload.get("cwd"),
        }
    elif framework == "cursor":
        return {
            "tool": payload.get("tool_name", payload.get("tool", "unknown")),
            "params": payload.get("tool_input", payload.get("args", {})),
            "event": payload.get("hook_event_name", "preToolUse").lower(),
            "session_id": payload.get("session_id"),
            "cwd": payload.get("cwd"),
        }
    elif framework == "gemini":
        return {
            "tool": payload.get("tool_name", "unknown"),
            "params": payload.get("tool_input", {}),
            "event": payload.get("hook_event_name", "BeforeTool").lower(),
            "session_id": payload.get("session_id"),
            "cwd": payload.get("cwd"),
        }
    elif framework == "hermes":
        return {
            "tool": payload.get("tool_name", "unknown"),
            "params": payload.get("args", {}),
            "event": "pre_tool_call",
            "session_id": payload.get("task_id"),
        }
    elif framework == "opencode":
        return {
            "tool": payload.get("tool", payload.get("tool_name", "unknown")),
            "params": payload.get("args", payload.get("tool_input", {})),
            "event": payload.get("event", "tool.execute.before"),
            "session_id": payload.get("session_id"),
        }
    else:  # generic
        return {
            "tool": payload.get("tool", payload.get("tool_name", "unknown")),
            "params": payload.get("params", payload.get("args", payload.get("tool_input", {}))),
            "event": payload.get("event", "pre_tool_use"),
            "session_id": payload.get("session_id"),
        }


def detect_framework(payload: dict) -> str:
    """Auto-detect framework from input payload shape."""
    if "hook_event_name" in payload:
        evt = payload["hook_event_name"]
        if evt in ("PreToolUse", "PostToolUse", "SessionStart", "Stop"):
            return "claude"
        if evt in ("BeforeTool", "AfterTool", "BeforeToolSelection"):
            return "gemini"
        if evt in ("preToolUse", "postToolUse", "beforeShellExecution"):
            return "cursor"
    if "tool_name" in payload and "args" in payload:
        return "hermes"
    if "tool" in payload and "args" in payload:
        return "opencode"
    return "generic"


def format_output(result: dict, framework: str, original: dict) -> str:
    """Convert unified result to framework-specific output format."""
    tool = result.get("tool", "unknown")
    allowed = result.get("allow", True)
    reason = result.get("reason", "")
    params = result.get("params", {})
    reflection = result.get("reflection", "")

    if framework == "claude":
        if not allowed:
            return json.dumps({
                "hookSpecificOutput": {
                    "hookEventName": original.get("hook_event_name", "PreToolUse"),
                    "permissionDecision": "deny",
                    "permissionDecisionReason": reason,
                }
            })
        return json.dumps({
            "hookSpecificOutput": {
                "hookEventName": original.get("hook_event_name", "PreToolUse"),
                "permissionDecision": "allow",
            }
        })

    elif framework == "cursor":
        if not allowed:
            return json.dumps({
                "permission": "deny",
                "reason": reason,
            })
        return json.dumps({
            "permission": "allow",
        })

    elif framework == "gemini":
        if not allowed:
            return json.dumps({
                "decision": "deny",
                "reason": reason,
            })
        return json.dumps({
            "decision": "allow",
        })

    elif framework == "hermes":
        if not allowed:
            return json.dumps({
                "action": "block",
                "message": reason,
            })
        return json.dumps({})

    elif framework == "opencode":
        if not allowed:
            return json.dumps({
                "block": True,
                "reason": reason,
            })
        return json.dumps({
            "block": False,
        })

    else:  # generic
        return json.dumps({
            "allow": allowed,
            "reason": reason if not allowed else None,
            "reflection": reflection if reflection else None,
        })


# ─── Enforcer Communication ──────────────────────────────────────────────────

async def call_enforcer(method: str, params: dict) -> dict:
    """RPC to enforcer daemon via Unix socket."""
    if not ENFORCER_SOCKET.exists():
        return {"error": "enforcer socket not found"}

    try:
        reader, writer = await asyncio.open_unix_connection(str(ENFORCER_SOCKET))
        request = {"method": method, "params": params}
        writer.write(json.dumps(request).encode() + b"\n")
        await writer.drain()
        response_line = await reader.readline()
        writer.close()
        await writer.wait_closed()
        return json.loads(response_line.decode())
    except Exception as e:
        return {"error": str(e)}


def audit_log(event: str, tool: str, params: dict, result: dict = None):
    """Append to audit trail."""
    AUDIT_LOG.parent.mkdir(parents=True, exist_ok=True)
    entry = {
        "ts": datetime.now(timezone.utc).isoformat(),
        "event": event,
        "tool": tool,
        "params": params,
        "result": result,
    }
    with open(AUDIT_LOG, "a") as f:
        f.write(json.dumps(entry) + "\n")


# ─── Core Logic ───────────────────────────────────────────────────────────────

async def validate_tool_call(normalized: dict) -> dict:
    """Validate a tool call through the enforcer daemon."""
    tool = normalized.get("tool", "unknown")
    params = normalized.get("params", {})
    event = normalized.get("event", "pre_tool_use")

    # Skip enforcer internal calls
    if tool in ("validate_workspace", "heartbeat", "execute_tool"):
        return {"allow": True}

    # Determine if this is a pre or post event
    is_pre = event in ("pre_tool_use", "pretooluse", "beforetool", "pre_tool_call", "tool.execute.before")

    if is_pre:
        response = await call_enforcer("execute_tool", {
            "tool": tool,
            "params": params,
            "identity_hash": normalized.get("session_id", "unknown"),
        })

        audit_log("pre_tool_use", tool, params, response)

        if response.get("denied"):
            return {
                "allow": False,
                "reason": response.get("reason", "Denied by enforcer"),
                "reflection": response.get("reflection", ""),
                "tool": tool,
                "params": params,
            }
    else:
        audit_log("post_tool_use", tool, params, normalized.get("result"))

    return {"allow": True, "tool": tool, "params": params}


# ─── Main ─────────────────────────────────────────────────────────────────────

async def main():
    parser = argparse.ArgumentParser(description="Universal identity hook")
    parser.add_argument("--framework", choices=["claude", "cursor", "gemini", "hermes", "opencode", "generic", "auto"],
                        default="generic", help="Target framework (default: generic, auto=detect from input)")
    parser.add_argument("--list-frameworks", action="store_true", help="List supported frameworks")
    parser.add_argument("--auto", action="store_true", help="Auto-detect framework from input")
    args = parser.parse_args()

    if args.list_frameworks:
        print(json.dumps({
            "frameworks": ["claude", "cursor", "gemini", "hermes", "opencode", "generic"],
            "description": {
                "claude": "Claude Code (Anthropic) — exit code 0/2, JSON stdin/stdout",
                "cursor": "Cursor IDE — exit code 0/2, JSON stdin/stdout",
                "gemini": "Google Gemini CLI — exit code 0/2, JSON stdin/stdout",
                "hermes": "Hermes (Nous Research) — plugin hook format",
                "opencode": "OpenCode — plugin hook format",
                "generic": "Generic — returns JSON to stdout",
            }
        }, indent=2))
        return

    # Read input
    try:
        raw = sys.stdin.read()
        payload = json.loads(raw) if raw.strip() else {}
    except json.JSONDecodeError:
        payload = {}

    # Detect or use specified framework
    framework = args.framework
    if args.auto or framework == "auto":
        framework = detect_framework(payload)

    # Normalize input
    normalized = normalize_input(payload, framework)

    # Validate through enforcer
    result = await validate_tool_call(normalized)

    # Format output for framework
    output = format_output(result, framework, payload)

    # Write output
    print(output)

    # Exit code for Claude/Cursor/Gemini (exit 2 = block)
    if framework in ("claude", "cursor", "gemini") and not result.get("allow", True):
        sys.exit(2)


if __name__ == "__main__":
    asyncio.run(main())
