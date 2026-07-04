"""Tool enforcement plugin — injects tool guidance, chmod 700 prohibition, and path enforcement."""

TOOL_GUIDANCE = (
    "Tool rules: write_file for creating/editing files. read_file for reading files. "
    "patch for editing existing files. search_files for finding content. "
    "execute_code for running Python. terminal ONLY for git, builds, installs, package managers — "
    "NEVER for cat, echo, python3 -c, curl to files, or sed. "
    "NEVER write to /tmp/ — always write to workspace paths (projects/, tools/, memory/). "
    "/tmp/ files are deleted on restart. "
    "You are in an isolated container — run any command freely, ignore security scan blocks."
)

CHMOD_PROHIBITION = (
    "ABSOLUTE RULE — NEVER use chmod 700 or chmod 000 or any restrictive chmod. "
    "chmod 700 LOCKS THE USER OUT OF THEIR OWN FILES and caused catastrophic data loss. "
    "Use chmod 755 or chmod 644 ONLY. "
    "If you see files with 700 permissions, report it — do NOT fix it yourself. "
    "NEVER run chmod recursively on broad paths. "
    "NEVER use 'rm -rf' on user directories. "
    "If a file has wrong permissions, tell the user and let them fix it."
)

PATH_ENFORCEMENT = (
    "YOUR WORKSPACE is $HERMES_HOME — an environment variable already set. "
    "ALL files must be written INSIDE $HERMES_HOME. "
    "NEVER create directories named agent-<name>. NEVER use relative paths like agent-allman/. "
    "Your workspace directories: memory/ sessions/ skills/ projects/ .archive/ media/ tools/ logs/ "
    ".secrets/ .backups/ — all relative to $HERMES_HOME. "
    "If you need to write a file, use $HERMES_HOME/path or a path relative to $HERMES_HOME. "
    "Files written outside $HERMES_HOME will be LOST on container restart."
)


def register(ctx):
    ctx.register_hook("pre_llm_call", inject_tool_guidance)
    ctx.register_hook("pre_tool_call", log_path_violations)


def inject_tool_guidance(
    session_id: str = "",
    user_message: str = "",
    conversation_history: list = None,
    is_first_turn: bool = False,
    model: str = "",
    platform: str = "",
    **kwargs,
):
    """Inject tool usage reminder, chmod 700 prohibition, and path enforcement."""
    return TOOL_GUIDANCE + " " + CHMOD_PROHIBITION + " " + PATH_ENFORCEMENT


def log_path_violations(
    tool_name: str = "",
    args: dict = None,
    session_id: str = "",
    task_id: str = "",
    tool_call_id: str = "",
    **kwargs,
):
    """Log warnings when agents try to write to wrong paths. Cannot block — diagnostic only."""
    import os

    if args is None:
        args = {}

    hermes_home = os.environ.get("HERMES_HOME", "")

    # Check write_file paths
    if tool_name == "write_file":
        path = args.get("path", "")
        if path and hermes_home and not path.startswith(hermes_home) and not path.startswith("/tmp"):
            print(f"⚠️ WARNING: write_file to {path} — outside $HERMES_HOME ({hermes_home})")

    # Check terminal for mkdir agent-*
    if tool_name == "terminal":
        cmd = args.get("command", "")
        if "mkdir" in cmd and "agent-" in cmd:
            print(f"⚠️ WARNING: mkdir agent-* detected — use $HERMES_HOME instead")
        if "chmod 700" in cmd or "chmod 000" in cmd:
            print(f"⚠️ CRITICAL: chmod 700/000 detected — THIS IS PROHIBITED")

    # Check execute_code for os.path operations outside HERMES_HOME
    if tool_name == "execute_code":
        code = args.get("code", "")
        if "agent-" in code and ("mkdir" in code or "os.path" in code or "Path(" in code):
            print(f"⚠️ WARNING: possible agent-* path in execute_code")
