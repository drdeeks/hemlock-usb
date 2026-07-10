#!/usr/bin/env python3
"""Generate /root/.openclaw/openclaw.json for the Hemlock multi-agent system.

The Hemlock Gateway is the CONTROL PLANE: it runs the agent loop (runEmbeddedAgent),
injects each agent's workspace files (AGENTS.md, SOUL.md, TOOLS.md, IDENTITY.md, USER.md,
HEARTBEAT.md, MEMORY.md) into the system prompt, and LAZY-loads skills (compact index
in-prompt; SKILL.md read on demand). Identity/context = the Gateway's job (from each
agent's `workspace`); the Gateway reaches each agent's brain over its per-agent
Hemlock-loop MCP — COGNITION + DATA ops only, isolated by its OWN AGENT_ID +
HEMLOCK_HOME (its volume). NEVER a single shared brain.

(Naming: "Hemlock Gateway" = the vendored openclaw engine, exposed as hemlock-gateway;
"Hemlock-loop" = the brain MCP server, implemented by hermes internally. The file/env
names below — .openclaw config path, OPENCLAW_* vars — are the engine's own schema and
stay as-is.)

Schema per the vendored engine's docs (see memory hemlock-openclaw-config). Idempotent;
validates before atomic write.
"""
import json, os, sys

AGENTS_DIR = os.environ.get("AGENTS_DIR", "/data/agents")
OUT        = os.environ.get("OPENCLAW_CONFIG", "/root/.openclaw/openclaw.json")
BRAIN      = os.environ.get("BRAIN_SCRIPT", "/opt/hermes/agent_brain_mcp.py")
PY         = os.environ.get("BRAIN_PYTHON", "/usr/local/bin/python3")
PORT       = int(os.environ.get("OPENCLAW_GATEWAY_PORT", "1437"))
# Keep the lazy skills index compact (skills load their SKILL.md on demand).
SKILLS_MAX_CHARS = int(os.environ.get("OPENCLAW_SKILLS_PROMPT_CHARS", "8000"))
# INCLUDE_BRAINS=0 (gateway-only mode) → the Hemlock Gateway runs its agents with NO
# Hemlock-loop MCP servers attached. Default 1 (full mode): each agent gets its
# per-agent Hemlock-loop brain.
INCLUDE_BRAINS = os.environ.get("INCLUDE_BRAINS", "1") != "0"

SKIP = {"active", "archive", "workspace-template"}


def discover(agents_dir):
    out = []
    if not os.path.isdir(agents_dir):
        return out
    for name in sorted(os.listdir(agents_dir)):
        if name.startswith(".") or name in SKIP:
            continue
        if os.path.isdir(os.path.join(agents_dir, name)):
            out.append(name)
    return out


def agent_meta(home, agent_id):
    """Read display name + model from the agent's own <id>.json (fail-soft)."""
    meta = {"name": agent_id.capitalize(), "model": None}
    path = os.path.join(home, f"{agent_id}.json")
    try:
        with open(path) as f:
            data = json.load(f)
        meta["name"] = data.get("display_name") or data.get("name") or meta["name"]
        meta["model"] = data.get("model") or None
    except Exception:
        pass
    return meta


def build(agents):
    cfg = {
        "gateway": {"port": PORT, "mode": "local"},
        # Context/skills discipline: bootstrap files injected + capped; skills stay LAZY.
        "agents": {
            "defaults": {
                "bootstrapMaxChars": 20000,
                "bootstrapTotalMaxChars": 60000,
                "bootstrapPromptTruncationWarning": "once",
                "heartbeat": {"includeSystemPromptSection": True},
                # CL-041: subagents.delegationMode and messages.groupChat.requireMention/
                # visibleReplies are NOT in the vendored gateway's config schema — it
                # fail-closes on unrecognized keys and the daemon never starts. Re-add
                # them only after the vendored engine is updated to a schema that
                # accepts them (verify with: openclaw doctor).
            },
            "list": [],
        },
        # Lazy-skills cap: only the compact name+description index goes in the prompt.
        "skills": {"limits": {"maxSkillsPromptChars": SKILLS_MAX_CHARS}},
        # Channel routing: deployment-specific (real account/peer IDs). Operators/agents add
        # { match:{channel,accountId,peer:{kind,id},...}, agentId } entries here. Until then
        # the agent flagged default:true is the fallback for all inbound messages.
        "bindings": [],
        "mcp": {"servers": {}},
    }
    for i, a in enumerate(agents):
        home = os.path.join(AGENTS_DIR, a)
        meta = agent_meta(home, a)
        entry = {
            "id": a,
            "name": meta["name"],
            "workspace": home,          # the Gateway injects AGENTS.md/SOUL.md/TOOLS.md/… from here
            "identity": {"name": meta["name"]},
            "default": (i == 0),        # first discovered agent = routing fallback
            # NOTE: no per-agent `tools` allow/deny → every tool is available by default (T11).
            "skillsLimits": {"maxSkillsPromptChars": SKILLS_MAX_CHARS},
        }
        if meta["model"]:
            entry["model"] = meta["model"]
        cfg["agents"]["list"].append(entry)
        # Per-agent Hemlock-loop MCP — cognition + DATA ops, isolated to this agent's
        # volume. Omitted entirely in gateway-only mode (INCLUDE_BRAINS=0).
        if INCLUDE_BRAINS:
            cfg["mcp"]["servers"][f"brain-{a}"] = {
                "command": PY, "args": [BRAIN],
                "env": {"AGENT_ID": a, "HEMLOCK_HOME": home, "HERMES_HOME": home},
            }
    return cfg


def main():
    agents = discover(AGENTS_DIR)
    cfg = build(agents)
    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    tmp = OUT + ".tmp"
    with open(tmp, "w") as f:
        json.dump(cfg, f, indent=2)
    json.load(open(tmp))            # validate parses
    os.replace(tmp, OUT)            # atomic
    dflt = agents[0] if agents else "(none)"
    print(f"[gateway-config] {len(agents)} agent(s): {', '.join(agents) or '(none)'}; default={dflt}")
    brains = ", ".join("brain-" + a for a in agents) if (INCLUDE_BRAINS and agents) else "(none — Hemlock-loop disabled)"
    print(f"[gateway-config] skills LAZY (index cap {SKILLS_MAX_CHARS} chars); Hemlock-loop brains: {brains}")
    print(f"[gateway-config] wrote {OUT}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
