#!/usr/bin/env python3
"""
Hermes Agent Brain MCP Server

Exposes hermes agent loop, memory, skills, and auto-learning as MCP tools
for OpenClaw agents. Each container runs one instance per agent.

Tools:
  agent_chat        — Run hermes agent loop (full tool-calling brain)
  agent_memory_get  — Retrieve memories for this agent
  agent_memory_set  — Store a memory for this agent
  agent_skills_list — List available skills
  agent_insights    — Get usage/cost insights from session history
  agent_sessions    — List recent sessions
  agent_identity    — Get agent identity files

Usage:
  python3 agent_brain_mcp.py [--verbose]

MCP client config (openclaw.json):
  {
    "mcp": {
      "servers": {
        "hermes-brain": {
          "command": "python3",
          "args": ["/app/agent_brain_mcp.py"],
          "env": { "AGENT_ID": "<agent_id>" }
        }
      }
    }
  }
"""

from __future__ import annotations

import json
import logging
import os
import signal
import sys
import threading
import time
import traceback
from pathlib import Path
from typing import Any, Dict, List, Optional

# ---------------------------------------------------------------------------
# Logging — structured, always goes to stderr
# ---------------------------------------------------------------------------
logger = logging.getLogger("hermes.brain_mcp")


def _setup_logging(verbose: bool = False) -> None:
    """Configure logging with timestamps and levels."""
    level = logging.DEBUG if verbose else logging.INFO
    handler = logging.StreamHandler(sys.stderr)
    handler.setFormatter(logging.Formatter(
        "%(asctime)s [%(levelname)s] %(name)s: %(message)s",
        datefmt="%Y-%m-%d %H:%M:%S",
    ))
    root = logging.getLogger()
    root.setLevel(level)
    root.addHandler(handler)


# ---------------------------------------------------------------------------
# Path setup — find hermes-agent source
# ---------------------------------------------------------------------------
# Find hermes-agent source — check Docker path first, then local paths
_HERMES_AGENT_DIR = None
for _candidate in [
    Path("/app/hermes-agent"),                                          # Docker
    Path.home() / ".hermes" / "hermes-agent",                           # Local
    Path(os.environ.get("PYTHONPATH", "").split(":")[0] if os.environ.get("PYTHONPATH") else ""),  # From env
]:
    if _candidate and _candidate.exists() and (_candidate / "run_agent.py").exists():
        _HERMES_AGENT_DIR = _candidate
        break

if _HERMES_AGENT_DIR:
    sys.path.insert(0, str(_HERMES_AGENT_DIR))
    logger.info("hermes-agent source found at %s", _HERMES_AGENT_DIR)
else:
    logger.warning("hermes-agent source not found — agent_chat will fail")

def _get_hermes_home() -> Path:
    """Get HERMES_HOME from environment. Reads fresh each call for test isolation."""
    return Path(os.environ.get("HERMES_HOME", str(Path.home() / ".hermes")))

# Backwards compat — used by module-level code that runs once
_HERMES_HOME = _get_hermes_home()
logger.debug("HERMES_HOME=%s", _HERMES_HOME)

# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------
MAX_FILE_READ_BYTES = 5 * 1024 * 1024   # 5MB max per file read
MAX_MEMORY_CONTENT_CHARS = 5000          # Max chars returned per memory
MAX_IDENTITY_CONTENT_CHARS = 3000        # Max chars returned per identity file
MAX_AGENT_CHAT_TURNS = 30               # Hard cap on agent_chat turns
AGENT_CHAT_TIMEOUT_SECS = 300           # 5 minute timeout on agent_chat
SAFE_FILENAME_CHARS = set("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_. ")

# ---------------------------------------------------------------------------
# Lazy imports
# ---------------------------------------------------------------------------
_MCP_AVAILABLE = False
_FastMCP = None
try:
    from mcp.server.fastmcp import FastMCP
    _MCP_AVAILABLE = True
    _FastMCP = FastMCP
    logger.info("MCP SDK available")
except ImportError as e:
    logger.warning("MCP SDK not available: %s", e)


# ---------------------------------------------------------------------------
# Graceful shutdown
# ---------------------------------------------------------------------------
_shutdown_event = threading.Event()


def _signal_handler(signum, frame):
    sig_name = signal.Signals(signum).name
    logger.info("Received %s, initiating graceful shutdown", sig_name)
    _shutdown_event.set()


signal.signal(signal.SIGTERM, _signal_handler)
signal.signal(signal.SIGINT, _signal_handler)


# ---------------------------------------------------------------------------
# Validation helpers
# ---------------------------------------------------------------------------

def _validate_filename(filename: str) -> tuple[bool, str]:
    """Validate a filename is safe and doesn't escape the memory directory.

    Returns (is_valid, error_message).
    """
    if not filename:
        return False, "Filename cannot be empty"
    if len(filename) > 255:
        return False, "Filename too long (max 255 chars)"
    if ".." in filename or filename.startswith("/"):
        return False, "Path traversal detected"
    if any(c not in SAFE_FILENAME_CHARS for c in filename):
        return False, "Filename contains unsafe characters"
    # Ensure the resolved path stays within memory dir
    resolved = (_HERMES_HOME / "memory" / filename).resolve()
    memory_dir = (_HERMES_HOME / "memory").resolve()
    if not str(resolved).startswith(str(memory_dir)):
        return False, "Resolved path escapes memory directory"
    return True, ""


def _safe_read_text(path: Path, max_bytes: int = MAX_FILE_READ_BYTES) -> str:
    """Read a text file with size limits and encoding fallback."""
    try:
        size = path.stat().st_size
        if size > max_bytes:
            logger.warning("File %s too large (%d bytes), truncating", path, size)
            with open(path, "r", encoding="utf-8", errors="replace") as f:
                return f.read(max_bytes)
        return path.read_text(encoding="utf-8", errors="replace")
    except PermissionError:
        logger.warning("Permission denied reading %s", path)
        return ""
    except OSError as e:
        logger.warning("OS error reading %s: %s", path, e)
        return ""


def _safe_write_text(path: Path, content: str) -> tuple[bool, str]:
    """Write text to file atomically with error handling.

    Returns (success, error_message).
    """
    try:
        path.parent.mkdir(parents=True, exist_ok=True)
        # Write to temp file then rename for atomicity
        tmp_path = path.with_suffix(".tmp")
        tmp_path.write_text(content, encoding="utf-8")
        tmp_path.rename(path)
        return True, ""
    except PermissionError as e:
        logger.error("Permission denied writing %s: %s", path, e)
        return False, f"Permission denied: {e}"
    except OSError as e:
        logger.error("OS error writing %s: %s", path, e)
        return False, f"OS error: {e}"
    except Exception as e:
        logger.exception("Unexpected error writing %s", path)
        return False, str(e)


def _clamp(value: int, lo: int, hi: int) -> int:
    """Clamp an integer to [lo, hi]."""
    return max(lo, min(hi, value))


# ---------------------------------------------------------------------------
# Environment helpers
# ---------------------------------------------------------------------------

def _ensure_hermes_home() -> None:
    """Create HERMES_HOME structure if missing. Never raises."""
    dirs = ["memory", "sessions", "skills", "tools", "logs", ".secrets", ".backups"]
    for d in dirs:
        try:
            (_HERMES_HOME / d).mkdir(parents=True, exist_ok=True)
        except OSError as e:
            logger.error("Cannot create directory %s: %s", _HERMES_HOME / d, e)


def _get_agent_id() -> str:
    agent_id = os.environ.get("AGENT_ID", "default")
    if not agent_id or agent_id == "":
        logger.warning("AGENT_ID not set, using 'default'")
        return "default"
    return agent_id


def _get_model() -> str:
    """Resolve model from environment or config. Never raises."""
    # Check env first
    model = os.environ.get("HERMES_MODEL")
    if model:
        logger.debug("Model from HERMES_MODEL env: %s", model)
        return model

    # Try reading from config
    config_path = _HERMES_HOME / "config.yaml"
    if config_path.exists():
        try:
            import yaml
            with open(config_path) as f:
                cfg = yaml.safe_load(f) or {}
            model_cfg = cfg.get("model", {})
            if isinstance(model_cfg, dict):
                primary = model_cfg.get("primary")
                if primary:
                    logger.debug("Model from config.yaml: %s", primary)
                    return primary
            elif isinstance(model_cfg, str):
                logger.debug("Model from config.yaml (string): %s", model_cfg)
                return model_cfg
        except Exception as e:
            logger.warning("Failed to read config.yaml: %s", e)

    # Fallback to env-based provider resolution
    if os.environ.get("ANTHROPIC_API_KEY"):
        logger.debug("Model from ANTHROPIC_API_KEY: anthropic/claude-sonnet-4-20250514")
        return "anthropic/claude-sonnet-4-20250514"
    elif os.environ.get("OPENAI_API_KEY"):
        logger.debug("Model from OPENAI_API_KEY: openai/gpt-4o")
        return "openai/gpt-4o"
    elif os.environ.get("NOUS_API_KEY") or os.environ.get("NOUS_INFERENCE_API_KEY"):
        logger.debug("Model from NOUS key: nous/xiaomi/mimo-v2-pro")
        return "nous/xiaomi/mimo-v2-pro"

    logger.warning("No model configured, using default")
    return "anthropic/claude-sonnet-4-20250514"


def _get_provider_base_url() -> Optional[str]:
    """Get provider base URL from environment."""
    url = os.environ.get("OPENAI_BASE_URL") or os.environ.get("NOUS_BASE_URL")
    if url:
        logger.debug("Provider base URL: %s", url)
    return url


def _get_api_key() -> Optional[str]:
    """Get API key from environment or .env file. Never raises."""
    for key in ["ANTHROPIC_API_KEY", "OPENAI_API_KEY", "NOUS_API_KEY",
                 "NOUS_INFERENCE_API_KEY", "OPENROUTER_API_KEY"]:
        val = os.environ.get(key)
        if val:
            logger.debug("API key found in env: %s", key)
            return val

    # Try .env file
    env_file = _HERMES_HOME / ".env"
    if env_file.exists():
        try:
            content = _safe_read_text(env_file, max_bytes=64 * 1024)
            for line in content.splitlines():
                line = line.strip()
                if not line or line.startswith("#"):
                    continue
                if "=" in line:
                    k, v = line.split("=", 1)
                    k = k.strip()
                    v = v.strip()
                    if k in ("ANTHROPIC_API_KEY", "OPENAI_API_KEY",
                             "NOUS_API_KEY", "OPENROUTER_API_KEY") and v:
                        logger.debug("API key found in .env: %s", k)
                        return v
        except Exception as e:
            logger.warning("Failed to read .env: %s", e)

    logger.warning("No API key found in environment or .env")
    return None


def _diagnose_startup() -> Dict[str, Any]:
    """Run startup diagnostics and return status dict."""
    diag = {
        "agent_id": _get_agent_id(),
        "hermes_home": str(_HERMES_HOME),
        "hermes_home_exists": _HERMES_HOME.exists(),
        "mcp_available": _MCP_AVAILABLE,
        "model": None,
        "api_key_present": False,
        "hermes_agent_source": _HERMES_AGENT_DIR.exists(),
        "config_yaml_exists": (_HERMES_HOME / "config.yaml").exists(),
        "soul_md_exists": (_HERMES_HOME / "SOUL.md").exists(),
        "env_exists": (_HERMES_HOME / ".env").exists(),
        "issues": [],
    }

    # Check model
    try:
        diag["model"] = _get_model()
    except Exception as e:
        diag["issues"].append(f"Model resolution failed: {e}")

    # Check API key
    diag["api_key_present"] = _get_api_key() is not None
    if not diag["api_key_present"]:
        diag["issues"].append("No API key found — agent_chat will fail")

    # Check hermes-agent source
    if not diag["hermes_agent_source"]:
        diag["issues"].append("hermes-agent source not found — agent_chat will fail")

    # Check identity
    if not diag["soul_md_exists"]:
        diag["issues"].append("SOUL.md missing — agent will have no personality")

    return diag


# ---------------------------------------------------------------------------
# MCP Server
# ---------------------------------------------------------------------------

def create_brain_server() -> "FastMCP":
    """Create the Hermes Brain MCP server with all tools.

    Raises:
        ImportError: If MCP SDK not available.
    """
    if not _MCP_AVAILABLE or _FastMCP is None:
        raise ImportError("mcp package required: pip install 'hermes-agent[mcp]'")

    _ensure_hermes_home()

    agent_id = _get_agent_id()
    logger.info("Creating brain server for agent=%s", agent_id)

    mcp = _FastMCP(
        f"hermes-brain-{agent_id}",
        instructions=(
            "Hermes Agent Brain — provides AI agent loop, memory, skills, "
            "and auto-learning capabilities. Use agent_chat to run the full "
            "hermes agent loop with tool calling."
        ),
    )

    # -- agent_chat --------------------------------------------------------

    @mcp.tool()
    def agent_chat(
        message: str,
        max_turns: int = 15,
        system_prompt: Optional[str] = None,
    ) -> str:
        """Run the hermes agent loop — full tool-calling brain.

        Sends a message through the hermes agent which will:
        1. Build a system prompt with identity, memory, and skills context
        2. Call the LLM with available tools
        3. Execute tool calls (terminal, file ops, web search, etc.)
        4. Loop until the agent produces a final response

        This is the core agent brain — use it when you need the agent to
        think, plan, and execute multi-step tasks.

        Args:
            message: The user message/task to process
            max_turns: Max LLM turns (default 15, max 30)
            system_prompt: Optional system prompt override
        """
        tool_start = time.monotonic()
        logger.info("agent_chat: message_len=%d max_turns=%d", len(message), max_turns)

        # Input validation
        if not message or not message.strip():
            logger.warning("agent_chat: empty message received")
            return json.dumps({"error": "Message cannot be empty"})

        if len(message) > 100_000:
            logger.warning("agent_chat: message truncated from %d chars", len(message))
            message = message[:100_000]

        max_turns = _clamp(max_turns, 1, MAX_AGENT_CHAT_TURNS)

        try:
            from run_agent import AIAgent
        except ImportError as e:
            logger.error("agent_chat: run_agent import failed: %s", e)
            return json.dumps({
                "error": f"Hermes agent not available: {e}",
                "hint": "Ensure hermes-agent is installed in the container",
            })

        # Run in a thread with hard timeout so we never hang the MCP server
        import concurrent.futures
        _agent_executor = concurrent.futures.ThreadPoolExecutor(max_workers=4)

        def _run_agent():
            model = _get_model()
            base_url = _get_provider_base_url()

            agent_kwargs: Dict[str, Any] = {
                "model": model,
                "max_iterations": max_turns,
                "quiet_mode": True,
                "skip_context_files": True,
            }
            if base_url:
                agent_kwargs["base_url"] = base_url

            logger.debug("agent_chat: creating AIAgent with model=%s", model)
            agent = AIAgent(**agent_kwargs)

            logger.debug("agent_chat: starting run_conversation")
            return agent.run_conversation(
                user_message=message,
                system_message=system_prompt,
            )

        try:
            future = _agent_executor.submit(_run_agent)
            result = future.result(timeout=AGENT_CHAT_TIMEOUT_SECS)

            elapsed = time.monotonic() - tool_start
            response_text = result.get("final_response", "")
            turns = len([m for m in result.get("messages", []) if m.get("role") == "assistant"])

            logger.info(
                "agent_chat: completed in %.1fs, %d turns, response_len=%d",
                elapsed, turns, len(response_text),
            )

            return json.dumps({
                "response": response_text,
                "turns": turns,
                "model": _get_model(),
                "elapsed_secs": round(elapsed, 1),
            }, indent=2)

        except concurrent.futures.TimeoutError:
            elapsed = time.monotonic() - tool_start
            logger.error(
                "agent_chat: HARD TIMEOUT after %.1fs (limit=%ds). "
                "The agent loop did not complete. This may indicate a stuck LLM call "
                "or infinite tool loop.",
                elapsed, AGENT_CHAT_TIMEOUT_SECS,
            )
            future.cancel()
            return json.dumps({
                "error": f"Agent chat timed out after {elapsed:.0f}s (limit: {AGENT_CHAT_TIMEOUT_SECS}s)",
                "hint": "Try reducing max_turns, simplifying the request, or checking API connectivity",
            })
        except KeyboardInterrupt:
            logger.warning("agent_chat: interrupted by signal")
            return json.dumps({"error": "Agent chat was interrupted"})
        except MemoryError:
            logger.error("agent_chat: out of memory during agent loop")
            return json.dumps({
                "error": "Out of memory during agent chat",
                "hint": "Try reducing max_turns or message size",
            })
        except Exception as e:
            elapsed = time.monotonic() - tool_start
            logger.exception("agent_chat: failed after %.1fs — %s: %s", elapsed, type(e).__name__, e)
            return json.dumps({
                "error": str(e),
                "type": type(e).__name__,
                "elapsed_secs": round(elapsed, 1),
                "traceback": traceback.format_exc()[-2000:],
            })
        finally:
            _agent_executor.shutdown(wait=False)

    # -- agent_memory_get --------------------------------------------------

    @mcp.tool()
    def agent_memory_get(
        query: Optional[str] = None,
        limit: int = 10,
    ) -> str:
        """Retrieve agent memories.

        Searches the agent's persistent memory files for relevant information.
        If no query given, returns the main MEMORY.md file contents.

        Args:
            query: Optional search term to filter memories
            limit: Max results (default 10)
        """
        tool_start = time.monotonic()
        limit = _clamp(limit, 1, 50)
        logger.debug("agent_memory_get: query=%r limit=%d", query, limit)

        try:
            memory_dir = _HERMES_HOME / "memory"
            memory_md = _HERMES_HOME / "MEMORY.md"
            results: List[Dict[str, str]] = []

            # Main memory file
            if memory_md.exists():
                content = _safe_read_text(memory_md, max_bytes=MAX_FILE_READ_BYTES)
                if not query or (query.lower() in content.lower()):
                    results.append({
                        "source": "MEMORY.md",
                        "content": content[:MAX_MEMORY_CONTENT_CHARS],
                    })

            # Memory directory files
            if memory_dir.exists():
                try:
                    md_files = sorted(f for f in memory_dir.glob("*.md") if f.is_file())
                except OSError as e:
                    logger.warning("agent_memory_get: glob failed: %s", e)
                    md_files = []

                for f in md_files[:limit]:
                    content = _safe_read_text(f, max_bytes=MAX_FILE_READ_BYTES)
                    if not query or (query.lower() in content.lower()):
                        results.append({
                            "source": f"memory/{f.name}",
                            "content": content[:MAX_MEMORY_CONTENT_CHARS],
                        })

                # Also check notes subdirectory
                notes_dir = memory_dir / "notes"
                if notes_dir.exists() and notes_dir.is_dir():
                    try:
                        note_files = sorted(f for f in notes_dir.glob("*.md") if f.is_file())
                    except OSError:
                        note_files = []
                    for f in note_files[:limit]:
                        content = _safe_read_text(f, max_bytes=MAX_FILE_READ_BYTES)
                        if not query or (query.lower() in content.lower()):
                            results.append({
                                "source": f"memory/notes/{f.name}",
                                "content": content[:MAX_MEMORY_CONTENT_CHARS],
                            })

            elapsed = time.monotonic() - tool_start
            logger.info("agent_memory_get: found %d results in %.3fs", len(results), elapsed)

            return json.dumps({
                "count": len(results),
                "memories": results[:limit],
            }, indent=2)

        except Exception as e:
            logger.exception("agent_memory_get failed")
            return json.dumps({"error": str(e), "type": type(e).__name__})

    # -- agent_memory_set --------------------------------------------------

    @mcp.tool()
    def agent_memory_set(
        content: str,
        filename: Optional[str] = None,
    ) -> str:
        """Store information in agent memory.

        Writes to the agent's persistent memory. Use this to save facts,
        preferences, or context that should persist across sessions.

        Args:
            content: The memory content to store
            filename: Optional filename (default: appends to MEMORY.md)
        """
        logger.debug("agent_memory_set: filename=%r content_len=%d", filename, len(content))

        # Input validation
        if not content or not content.strip():
            logger.warning("agent_memory_set: empty content")
            return json.dumps({"error": "Content cannot be empty"})

        if len(content) > 10 * 1024 * 1024:  # 10MB
            logger.warning("agent_memory_set: content too large (%d bytes)", len(content))
            return json.dumps({"error": "Content too large (max 10MB)"})

        try:
            if filename:
                # Validate filename
                is_valid, err = _validate_filename(filename)
                if not is_valid:
                    logger.warning("agent_memory_set: invalid filename %r: %s", filename, err)
                    return json.dumps({"error": err})

                memory_dir = _HERMES_HOME / "memory"
                path = memory_dir / filename
                if not path.suffix:
                    path = path.with_suffix(".md")

                ok, err = _safe_write_text(path, content)
                if not ok:
                    return json.dumps({"error": f"Write failed: {err}"})
            else:
                path = _HERMES_HOME / "MEMORY.md"
                existing = ""
                if path.exists():
                    existing = _safe_read_text(path, max_bytes=MAX_FILE_READ_BYTES)
                    if existing and not existing.endswith("\n"):
                        existing += "\n"

                ok, err = _safe_write_text(path, existing + content + "\n")
                if not ok:
                    return json.dumps({"error": f"Write failed: {err}"})

            logger.info("agent_memory_set: wrote %d bytes to %s", len(content), path)
            return json.dumps({
                "ok": True,
                "path": str(path),
                "bytes": len(content),
            })

        except Exception as e:
            logger.exception("agent_memory_set failed")
            return json.dumps({"error": str(e), "type": type(e).__name__})

    # -- agent_skills_list -------------------------------------------------

    @mcp.tool()
    def agent_skills_list() -> str:
        """List available skills for this agent.

        Returns skill names, categories, and descriptions from the agent's
        skills directory and any symlinked core skills.
        """
        logger.debug("agent_skills_list")
        skills_dir = _HERMES_HOME / "skills"
        skills: List[Dict[str, str]] = []

        try:
            if not skills_dir.exists():
                logger.info("agent_skills_list: skills dir does not exist")
                return json.dumps({"count": 0, "skills": []})

            for item in sorted(skills_dir.iterdir()):
                if item.name.startswith("."):
                    continue

                try:
                    is_symlink = item.is_symlink()
                    is_dir = item.is_dir()

                    # Handle broken symlinks
                    if is_symlink and not item.exists():
                        logger.debug("agent_skills_list: broken symlink %s", item.name)
                        skills.append({
                            "name": item.name,
                            "type": "broken_symlink",
                        })
                        continue

                    skill_info: Dict[str, str] = {
                        "name": item.name,
                        "type": "symlink" if is_symlink else "directory",
                    }

                    # Try to read SKILL.md
                    skill_md = item / "SKILL.md"
                    if skill_md.exists() and skill_md.is_file():
                        content = _safe_read_text(skill_md, max_bytes=64 * 1024)
                        if content:
                            lines = content.split("\n")
                            for line in lines:
                                if line.startswith("# "):
                                    skill_info["title"] = line[2:].strip()
                                    break
                            desc_lines: List[str] = []
                            found_heading = False
                            for line in lines:
                                if line.startswith("# "):
                                    found_heading = True
                                    continue
                                if found_heading and line.strip():
                                    if line.startswith("---"):
                                        continue
                                    desc_lines.append(line.strip())
                                    if len(desc_lines) >= 3:
                                        break
                            if desc_lines:
                                skill_info["description"] = " ".join(desc_lines)

                    skills.append(skill_info)

                except OSError as e:
                    logger.warning("agent_skills_list: error processing %s: %s", item.name, e)
                    skills.append({"name": item.name, "type": "error", "error": str(e)})

            logger.info("agent_skills_list: found %d skills", len(skills))
            return json.dumps({"count": len(skills), "skills": skills}, indent=2)

        except Exception as e:
            logger.exception("agent_skills_list failed")
            return json.dumps({"error": str(e), "type": type(e).__name__})

    # -- agent_insights ----------------------------------------------------

    @mcp.tool()
    def agent_insights(days: int = 7) -> str:
        """Get usage insights from agent session history.

        Returns token usage, cost estimates, tool usage patterns,
        and activity trends from recent sessions.

        Args:
            days: Number of days to look back (default 7)
        """
        days = _clamp(days, 1, 365)
        logger.debug("agent_insights: days=%d", days)

        try:
            from hermes_state import SessionDB
        except ImportError as e:
            logger.error("agent_insights: hermes_state import failed: %s", e)
            return json.dumps({
                "error": f"SessionDB unavailable: {e}",
                "hint": "Session database not initialized yet",
            })

        try:
            db = SessionDB()
            from agent.insights import InsightsEngine

            engine = InsightsEngine(db)
            report = engine.generate(days=days)

            logger.info("agent_insights: generated report for %d days", days)
            return json.dumps({
                "period_days": days,
                "total_sessions": report.get("total_sessions", 0),
                "total_input_tokens": report.get("total_input_tokens", 0),
                "total_output_tokens": report.get("total_output_tokens", 0),
                "estimated_cost_usd": report.get("estimated_cost_usd", 0),
                "models_used": report.get("models_used", []),
                "tools_used": report.get("tools_used", {}),
                "daily_breakdown": report.get("daily_breakdown", []),
            }, indent=2)

        except Exception as e:
            logger.exception("agent_insights failed")
            return json.dumps({"error": str(e), "type": type(e).__name__})

    # -- agent_sessions ----------------------------------------------------

    @mcp.tool()
    def agent_sessions(limit: int = 10) -> str:
        """List recent agent sessions.

        Returns session keys, timestamps, and message counts from
        the agent's session database.

        Args:
            limit: Max sessions to return (default 10)
        """
        limit = _clamp(limit, 1, 100)
        logger.debug("agent_sessions: limit=%d", limit)

        try:
            sessions_dir = _HERMES_HOME / "sessions"
            sessions: List[Dict[str, Any]] = []

            if not sessions_dir.exists():
                logger.info("agent_sessions: sessions dir does not exist")
                return json.dumps({"count": 0, "sessions": []})

            # Check for sessions.json index
            index_file = sessions_dir / "sessions.json"
            if index_file.exists():
                try:
                    content = _safe_read_text(index_file, max_bytes=MAX_FILE_READ_BYTES)
                    index = json.loads(content)
                    for key, entry in list(index.items())[:limit]:
                        sessions.append({
                            "key": key,
                            "platform": entry.get("platform", ""),
                            "display_name": entry.get("display_name", ""),
                            "updated_at": entry.get("updated_at", ""),
                        })
                except (json.JSONDecodeError, Exception) as e:
                    logger.warning("agent_sessions: failed to parse sessions.json: %s", e)

            # Fallback to listing .jsonl files
            if not sessions:
                try:
                    jsonl_files = sorted(
                        (f for f in sessions_dir.glob("*.jsonl") if f.is_file()),
                        key=lambda x: x.stat().st_mtime,
                        reverse=True,
                    )[:limit]
                    for f in jsonl_files:
                        try:
                            stat = f.stat()
                            sessions.append({
                                "file": f.name,
                                "size_bytes": stat.st_size,
                                "modified": stat.st_mtime,
                            })
                        except OSError as e:
                            logger.warning("agent_sessions: stat failed for %s: %s", f.name, e)
                except OSError as e:
                    logger.warning("agent_sessions: glob failed: %s", e)

            logger.info("agent_sessions: found %d sessions", len(sessions))
            return json.dumps({"count": len(sessions), "sessions": sessions}, indent=2)

        except Exception as e:
            logger.exception("agent_sessions failed")
            return json.dumps({"error": str(e), "type": type(e).__name__})

    # -- agent_identity ----------------------------------------------------

    @mcp.tool()
    def agent_identity() -> str:
        """Get this agent's identity — SOUL.md, USER.md, and config.

        Returns the agent's personality, user info, and configuration
        that shapes how it behaves.
        """
        logger.debug("agent_identity")

        try:
            identity: Dict[str, Any] = {
                "agent_id": _get_agent_id(),
                "hermes_home": str(_HERMES_HOME),
                "model": _get_model(),
            }

            # Read identity files
            for fname in ["SOUL.md", "USER.md", "IDENTITY.md", "AGENTS.md", "TOOLS.md"]:
                path = _HERMES_HOME / fname
                if path.exists() and path.is_file():
                    try:
                        content = _safe_read_text(path, max_bytes=MAX_FILE_READ_BYTES)
                        identity_key = fname.lower().replace(".md", "")
                        identity[identity_key] = content[:MAX_IDENTITY_CONTENT_CHARS]
                    except Exception as e:
                        logger.warning("agent_identity: failed to read %s: %s", fname, e)

            # Read config summary
            config_path = _HERMES_HOME / "config.yaml"
            if config_path.exists():
                try:
                    import yaml
                    with open(config_path) as f:
                        cfg = yaml.safe_load(f) or {}
                    identity["config_model"] = cfg.get("model", {})
                    identity["config_tools"] = cfg.get("tools", {})
                except Exception as e:
                    logger.warning("agent_identity: failed to parse config.yaml: %s", e)

            logger.info("agent_identity: returning identity with %d fields", len(identity))
            return json.dumps(identity, indent=2)

        except Exception as e:
            logger.exception("agent_identity failed")
            return json.dumps({"error": str(e), "type": type(e).__name__})

    return mcp


# ---------------------------------------------------------------------------
# Entry point
# ---------------------------------------------------------------------------

def main() -> None:
    """Main entry point. Never exits with unhandled exceptions."""
    verbose = "--verbose" in sys.argv
    _setup_logging(verbose)

    logger.info("=" * 60)
    logger.info("Hermes Brain MCP Server starting")
    logger.info("=" * 60)

    # Startup diagnostics
    diag = _diagnose_startup()
    logger.info("Startup diagnostics:")
    for key, value in diag.items():
        if key == "issues":
            continue
        logger.info("  %s: %s", key, value)

    if diag["issues"]:
        logger.warning("Startup issues detected:")
        for issue in diag["issues"]:
            logger.warning("  - %s", issue)

    # Check MCP availability
    if not _MCP_AVAILABLE:
        logger.critical(
            "MCP SDK not installed. Install with: pip install 'hermes-agent[mcp]'"
        )
        print(
            "Error: MCP server requires the 'mcp' package.\n"
            "Install with: pip install 'hermes-agent[mcp]'",
            file=sys.stderr,
        )
        sys.exit(1)

    # Create and run server
    try:
        server = create_brain_server()
        logger.info("Brain server created, starting MCP stdio loop")
        logger.info("Server will run until stdin closes or SIGTERM/SIGINT received")

        server.run()

    except KeyboardInterrupt:
        logger.info("Interrupted by user")
    except BrokenPipeError:
        logger.info("Client disconnected (broken pipe)")
    except EOFError:
        logger.info("Client disconnected (EOF)")
    except Exception as e:
        logger.critical("Fatal error: %s\n%s", e, traceback.format_exc())
        sys.exit(1)
    finally:
        logger.info("Hermes Brain MCP Server shutting down")


if __name__ == "__main__":
    main()
