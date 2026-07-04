#!/bin/bash
set -euo pipefail

# ── Signal handling ──────────────────────────────────────────────────────────
_term_received=0
OPENCLAW_PID=0
HERMES_PID=0
MCP_PID=0
SKILLS_UPDATE_PID=0
CONTEXT_DUMP_PID=0
VOLUME_GIT_PID=0
KNOWLEDGE_WATCH_PID=0

# Crash-safe context offload: dump every agent's working context to a
# timestamped file so information is NEVER erased. Fail-soft — never aborts.
_dump_all_contexts() {
    local reason="${1:-manual}"
    local fallback="/data/agents/workspace-template/tools/context-dump.sh"
    local home tool base
    for home in /data/agents/*/; do
        [ -d "$home" ] || continue
        base="$(basename "$home")"
        case "$base" in .*|active|archive|workspace-template) continue ;; esac
        tool="${home}tools/context-dump.sh"
        [ -f "$tool" ] || tool="$fallback"
        [ -f "$tool" ] && bash "$tool" "${home%/}" "$reason" >/dev/null 2>&1 || true
    done
    # Single-home mode (e.g. HERMES_ONLY sets HERMES_HOME to one agent dir)
    if [ -n "${HERMES_HOME:-}" ] && [ -d "${HERMES_HOME:-}" ] && [ "${HERMES_HOME}" != "/runtime" ]; then
        tool="${HERMES_HOME}/tools/context-dump.sh"
        [ -f "$tool" ] || tool="$fallback"
        [ -f "$tool" ] && bash "$tool" "$HERMES_HOME" "$reason" >/dev/null 2>&1 || true
    fi
}

cleanup() {
    _term_received=1
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] === Received shutdown signal ==="
    # FIRST: offload context so nothing is lost, before tearing anything down.
    _dump_all_contexts "shutdown" || true
    [ "$CONTEXT_DUMP_PID" -ne 0 ] && kill -TERM "$CONTEXT_DUMP_PID" 2>/dev/null || true
    # Final per-volume git snapshot so the latest state is captured, then stop the daemon.
    if [ "$VOLUME_GIT_PID" -ne 0 ]; then
        /opt/hermes/docker/volume-git-daemon.sh --once >/dev/null 2>&1 || true
        /opt/hermes/docker/volume-git-daemon.sh --stop 2>/dev/null || true
        kill -TERM "$VOLUME_GIT_PID" 2>/dev/null || true
    fi
    # The skills updater is self-healing and will NOT stop on a bare TERM to a
    # child — it must be told to stop explicitly. Container shutdown is a
    # legitimate explicit stop, so raise the stop flag before signalling.
    if [ "$SKILLS_UPDATE_PID" -ne 0 ]; then
        /opt/hermes/docker/skills-auto-update.sh --stop 2>/dev/null || true
        kill -TERM "$SKILLS_UPDATE_PID" 2>/dev/null || true
    fi
    # The knowledge watcher is likewise self-healing — flag an explicit stop.
    if [ "$KNOWLEDGE_WATCH_PID" -ne 0 ]; then
        /opt/hermes/docker/knowledge-watcher.sh --stop 2>/dev/null || true
        kill -TERM "$KNOWLEDGE_WATCH_PID" 2>/dev/null || true
    fi
    [ "$MCP_PID" -ne 0 ] && kill -TERM "$MCP_PID" 2>/dev/null || true
    [ "$HERMES_PID" -ne 0 ] && kill -TERM "$HERMES_PID" 2>/dev/null || true
    [ "$OPENCLAW_PID" -ne 0 ] && kill -TERM "$OPENCLAW_PID" 2>/dev/null || true
}

trap cleanup TERM INT

# ── Helpers ──────────────────────────────────────────────────────────────────
log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"; }
warn() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] WARN: $*" >&2; }
die() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] FATAL: $*" >&2; exit 1; }

# ── Home var (de-branding forward-compat) ────────────────────────────────────
# HEMLOCK_HOME is the canonical agent-home variable going forward. HERMES_HOME
# remains a working alias so nothing breaks during the transition. Keep both
# pointed at the same directory and export both for every child process
# (brain, gateway, agent terminal tools).
export HEMLOCK_HOME="${HEMLOCK_HOME:-${HERMES_HOME:-/runtime}}"
export HERMES_HOME="${HERMES_HOME:-$HEMLOCK_HOME}"

# ── Mode — ONE toggle controls the whole topology: HEMLOCK_MODE ──────────────
#   full     (default) OpenClaw manages everything; Hermes runs MINIMAL — per-agent
#            brains launched on demand by OpenClaw via MCP (no standalone Hermes gateway).
#   hermes   All-Hermes: OpenClaw ignored entirely; Hermes gateway runs standalone.
#            Paths still resolve via $HEMLOCK_HOME — nothing has to move or change.
#   openclaw All-OpenClaw: Hermes brains ignored; OpenClaw runs its own agents, no brain MCP.
# Back-compat: legacy HERMES_ONLY=1 / OPENCLAW_ONLY=1 still honored (HEMLOCK_MODE wins).
_mode="${HEMLOCK_MODE:-}"
if [ -z "$_mode" ]; then
    if [[ "${HERMES_ONLY:-}" == "1" ]]; then _mode="hermes"
    elif [[ "${OPENCLAW_ONLY:-}" == "1" ]]; then _mode="openclaw"
    else _mode="full"; fi
fi
case "$_mode" in
    full)                    MODE="full" ;;
    hermes|hermes-only)      MODE="hermes-only" ;;
    openclaw|openclaw-only)  MODE="openclaw-only" ;;
    *) warn "Unknown HEMLOCK_MODE='$_mode' — defaulting to full"; MODE="full"; _mode="full" ;;
esac
export HEMLOCK_MODE="$_mode"

log "=== Mode: ${MODE} (HEMLOCK_MODE=${_mode}) ==="

# ── Skills seed + daily self-healing auto-update ────────────────────────────
# /skills is a docker NAMED VOLUME — empty on first start. The image bakes the
# CURATED skill set at /opt/skills_seed. On first start, rsync seeds /skills.
# Subsequent starts skip the seed rsync.
if [[ -d /opt/skills_seed && ! -f /skills/.hemlock_skills_seeded ]]; then
    log "[skills] seeding /skills from /opt/skills_seed (first start, curated set)"
    rsync -a --delete /opt/skills_seed/ /skills/ 2>>/var/log/hemlock-skills-sync.log || \
        warn "skills seed rsync failed — /skills may be incomplete"
    date -Iseconds > /skills/.hemlock_skills_seeded
    log "[skills] seeded $(ls /skills | grep -v '^\.' | wc -l) entries (curated)"

    # Install-time provider tag remap: the repo ships STANDARD tags only;
    # seeding = installing, so remap canonical tags into the provider blocks
    # this harness actually consumes (see skill-creator
    # references/provider-tag-remapping.md). Additive + idempotent; fail-soft.
    if [[ -f /skills/skill-creator/scripts/skill_enhance.py ]]; then
        python3 - <<'PYEOF' 2>>/var/log/hemlock-skills-sync.log || warn "[skills] provider tag remap failed (non-fatal)"
import sys
sys.dont_write_bytecode = True
sys.path.insert(0, "/skills/skill-creator/scripts")
from pathlib import Path
from skill_enhance import remap_provider_tags, detect_providers
providers = detect_providers() or ["hermes", "openclaw"]
n = sum(1 for d in Path("/skills").iterdir()
        if (d / "SKILL.md").is_file() and remap_provider_tags(d, providers))
print(f"[skills] provider tag remap: {n} skills -> {','.join(providers)}")
PYEOF
    fi
fi

# Daily upstream refresh (supersedes the CL-027-disabled cron). The updater
# pulls the canonical drdeeks/skills repo over the network into a container-
# internal clone and version-syncs /skills as REAL FILES (fail-soft offline).
# It runs under its own self-healing supervisor: any unexpected exit is
# restarted; it stops ONLY on an explicit stop (issued from cleanup() at
# container shutdown). Guardrail/monitor control artifacts (.git, .monitor.json,
# .monitor-state.json, .loop*.json[l], .gate.json) are excluded from the sync
# and permission-hardened to root-only after every cycle.
UPDATER="/opt/hermes/docker/skills-auto-update.sh"
if [[ "${SKILLS_UPDATE_ENABLED:-1}" == "1" && -x "$UPDATER" ]]; then
    "$UPDATER" --harden 2>/dev/null || true   # harden control artifacts up front
    log "[skills] starting self-healing daily auto-updater (supervised)"
    "$UPDATER" --supervise >>/var/log/hemlock-skills-sync.log 2>&1 &
    SKILLS_UPDATE_PID=$!
    log "[skills] auto-updater supervisor started (PID: ${SKILLS_UPDATE_PID})"
else
    log "[skills] auto-updater DISABLED (SKILLS_UPDATE_ENABLED=${SKILLS_UPDATE_ENABLED:-1})"
fi

# ── Crash-safe periodic context flush ────────────────────────────────────────
# Graceful shutdown is covered by cleanup()'s dump. Hard failures (power loss,
# OOM, kill -9) fire no signal, so we snapshot every agent's context on an
# interval to bound worst-case loss. Default 300s; set CONTEXT_DUMP_ENABLED=0
# to opt out (informative + optional — nothing is forced).
if [[ "${CONTEXT_DUMP_ENABLED:-1}" == "1" ]]; then
    (
        while true; do
            sleep "${CONTEXT_DUMP_INTERVAL:-300}"
            _dump_all_contexts "periodic" >/dev/null 2>&1 || true
        done
    ) &
    CONTEXT_DUMP_PID=$!
    log "[context] periodic crash-safe context flush started (PID: ${CONTEXT_DUMP_PID}, every ${CONTEXT_DUMP_INTERVAL:-300}s)"
else
    log "[context] periodic context flush DISABLED (CONTEXT_DUMP_ENABLED=0)"
fi

# ── Per-volume git snapshots (daily, self-healing) ───────────────────────────
# Each agent/crew volume becomes a git repo committed daily so agents can roll
# back any change in any directory (tools/rollback.sh). Set VOLUME_GIT_ENABLED=0
# to opt out; VOLUME_GIT_INTERVAL overrides the cadence.
if [[ "${VOLUME_GIT_ENABLED:-1}" == "1" ]]; then
    if command -v git >/dev/null 2>&1 && [ -x /opt/hermes/docker/volume-git-daemon.sh ]; then
        /opt/hermes/docker/volume-git-daemon.sh --supervise >>/var/log/hemlock-volume-git.log 2>&1 &
        VOLUME_GIT_PID=$!
        log "[volume-git] daily per-volume snapshot daemon started (PID: ${VOLUME_GIT_PID})"
    else
        warn "[volume-git] git or daemon unavailable — per-volume snapshots skipped"
    fi
else
    log "[volume-git] per-volume git snapshots DISABLED (VOLUME_GIT_ENABLED=0)"
fi

# ── Global knowledge store + inbox watcher (self-healing) ────────────────────
# Runtime-root, append-only knowledge/ dir shared by every agent. Links/docs a
# user sends via the gateway (any platform) are captured into knowledge/ by the
# agent_chat hook + tools/knowledge-capture.sh; this watcher indexes new inbox
# files so the store stays searchable. Set KNOWLEDGE_WATCH_ENABLED=0 to opt out;
# HEMLOCK_KNOWLEDGE_DIR / KNOWLEDGE_WATCH_INTERVAL override location / cadence.
export HEMLOCK_KNOWLEDGE_DIR="${HEMLOCK_KNOWLEDGE_DIR:-${RUNTIME_ROOT:-/data}/knowledge}"
mkdir -p "$HEMLOCK_KNOWLEDGE_DIR/inbox" 2>/dev/null || true
if [[ "${KNOWLEDGE_WATCH_ENABLED:-1}" == "1" ]]; then
    if [ -x /opt/hermes/docker/knowledge-watcher.sh ]; then
        /opt/hermes/docker/knowledge-watcher.sh --supervise >>/var/log/hemlock-knowledge-watch.log 2>&1 &
        KNOWLEDGE_WATCH_PID=$!
        log "[knowledge] global knowledge watcher started (PID: ${KNOWLEDGE_WATCH_PID}, dir: ${HEMLOCK_KNOWLEDGE_DIR})"
    else
        warn "[knowledge] watcher unavailable — inbox auto-indexing skipped"
    fi
else
    log "[knowledge] global knowledge watcher DISABLED (KNOWLEDGE_WATCH_ENABLED=0)"
fi

# ── Dynamic Agent/Crew Detection ──────────────────────────────────────────────
if [ -z "${AGENT_ID:-}" ]; then
    if [ -d "/data/agents" ] && ls /data/agents/ >/dev/null 2>&1; then
        AGENT_ID=$(ls /data/agents | head -n 1)
        log "Detected AGENT_ID from /data/agents: ${AGENT_ID}"
    elif [ -d "/data/crews" ] && ls /data/crews/ >/dev/null 2>&1; then
        AGENT_ID=$(ls /data/crews | head -n 1)
        log "Detected AGENT_ID from /data/crews: ${AGENT_ID}"
    elif [ -d "/agents" ] && ls /agents/ >/dev/null 2>&1; then
        AGENT_ID=$(ls /agents | head -n 1)
        log "Detected AGENT_ID from /agents: ${AGENT_ID}"
    else
        die "AGENT_ID not set and no agent/crew directories detected. Please set AGENT_ID or mount agent data."
    fi
fi

HERMES_HOME="/data/agents/${AGENT_ID}"
if [ -d "/data/crews/${AGENT_ID}" ]; then
    HERMES_HOME="/data/crews/${AGENT_ID}"
    log "Running as CREW: ${AGENT_ID}"
elif [ ! -d "${HERMES_HOME}" ]; then
    mkdir -p "${HERMES_HOME}"
    log "Created agent directory: ${HERMES_HOME}"
fi

log "=== Starting agent/crew: ${AGENT_ID} ==="
log "HERMES_HOME: ${HERMES_HOME}"
log "AGENT_ID: ${AGENT_ID}"
log "USER: $(whoami) (uid=$(id -u), gid=$(id -g))"

# ── Environment Setup ─────────────────────────────────────────────────────────
export HERMES_HOME
export OPENCLAW_ROOT="${OPENCLAW_ROOT:-/opt/openclaw}"
import_path="/opt/hermes"
if [ -d "/app/hermes-agent" ]; then
    import_path="${import_path}:/app/hermes-agent"
fi
if [ -d "/opt/openclaw/lib" ]; then
    import_path="${import_path}:/opt/openclaw/lib"
fi
export PYTHONPATH="${import_path}:${PYTHONPATH:-}"

# ── Fix ownership of any root-owned files ────────────────────────────────────
if [ -w "${HERMES_HOME}" ]; then
    _fixed=0
    while IFS= read -r f; do
        [ -z "$f" ] && continue
        chown "$(id -u):$(id -g)" "$f" 2>/dev/null && _fixed=$((_fixed + 1))
    done < <(find "${HERMES_HOME}" -maxdepth 3 -not -user "$(id -u)" -not -path '*/.git/*' 2>/dev/null | head -500)
    [ "$_fixed" -gt 0 ] && log "Fixed ownership on ${_fixed} file(s)"
fi

# ── Load .env from gateway config and agent/crew directory ────────────────────
if [ -f "/runtime/.env" ]; then
    log "Loading gateway config from /runtime/.env"
    set -a
    source "/runtime/.env"
    set +a
    log "TELEGRAM_BOT_TOKEN: ${TELEGRAM_BOT_TOKEN:+<set>}${TELEGRAM_BOT_TOKEN:-not set}"
else
    log "No gateway config at /runtime/.env"
fi

if [ -f "${HERMES_HOME}/.env" ]; then
    log "Loading agent config from ${HERMES_HOME}/.env (overrides gateway)"
    set -a
    source "${HERMES_HOME}/.env"
    set +a
    log "TELEGRAM_BOT_TOKEN: ${TELEGRAM_BOT_TOKEN:+<set>}${TELEGRAM_BOT_TOKEN:-not set}"
else
    warn "No agent .env file at ${HERMES_HOME}/.env — Telegram will not connect"
fi

# ── Prevent gateway from setting chmod 700/600 ──────────────────────────────
export HERMES_MANAGED=false
log "HERMES_MANAGED=${HERMES_MANAGED} (gateway chmod disabled)"

# ── Validate prerequisites ───────────────────────────────────────────────────
command -v python3 >/dev/null || die "python3 not found"
log "python3: $(python3 --version 2>&1)"

if [ "$MODE" != "openclaw-only" ]; then
    if ! python3 -c "import sys; sys.path.insert(0, '/app/hermes-agent'); from gateway.run import GatewayRunner" 2>/dev/null; then
        die "hermes gateway not importable — check PYTHONPATH and hermes-agent install"
    fi
fi

if [ "$MODE" != "hermes-only" ]; then
    command -v openclaw >/dev/null || warn "openclaw binary not found — OpenClaw features unavailable"
fi

log "All prerequisites validated"

# ── Ensure minimal structure ─────────────────────────────────────────────────
mkdir -p "${HERMES_HOME}"/{memory,sessions,skills,tools,logs,memories,cron,.secrets,projects,.archive,media/images/agents,media/images/misc,media/files} 2>/dev/null || warn "Could not create some directories"

# ── Normalize permissions — NEVER 700, NEVER 600 ─────────────────────────────
# Directories: 755, Files: 644 (except .secrets/*, .env, auth.json)
_fixed_perm=0
while IFS= read -r d; do
    [ -z "$d" ] && continue
    chmod 755 "$d" 2>/dev/null && _fixed_perm=$((_fixed_perm + 1))
done < <(find "${HERMES_HOME}" -type d -perm 700 2>/dev/null)
[ "$_fixed_perm" -gt 0 ] && log "Fixed chmod 700→755 on ${_fixed_perm} directory(ies)"

while IFS= read -r f; do
    [ -z "$f" ] && continue
    chmod 644 "$f" 2>/dev/null
done < <(find "${HERMES_HOME}" \( -type f -perm 700 -o -type f -perm 600 \) \
    -not -path '*/.secrets/*' -not -name '.env' -not -name 'auth.json' 2>/dev/null)

# ── Create identity stubs ONLY if completely missing ─────────────────────────
for f in SOUL.md USER.md AGENTS.md HEARTBEAT.md IDENTITY.md TOOLS.md; do
    [ -f "${HERMES_HOME}/${f}" ] || echo "# ${f%.md} — ${AGENT_ID}" > "${HERMES_HOME}/${f}" 2>/dev/null
done

if [ ! -f "${HERMES_HOME}/agent.json" ]; then
    echo '{"builderCode":{"code":"bc_26ulyc23","hex":"0x62635f3236756c79633233","owner":"0x12F1B38DC35AA65B50E5849d02559078953aE24b","hardwired":true,"enforced":true}}' > "${HERMES_HOME}/agent.json" 2>/dev/null
fi

if [ ! -f "${HERMES_HOME}/config.yaml" ]; then
    cat > "${HERMES_HOME}/config.yaml" << 'YAMLEOF' 2>/dev/null || true
model:
  default: ollama/qwen3
  provider: ollama
  base_url: http://localhost:11434/v1

tools:
  profile: coding

memory:
  enabled: true
  max_chars: 100000

skills:
  enabled: true

mcp:
  provider: auto
  model: ""
  base_url: ""
  api_key: ""
  timeout: 30

mcp_servers:
  hermes-brain:
    command: python3
    args:
      - /app/agent_brain_mcp.py
      - --brain
    env:
      AGENT_ID: "${AGENT_ID}"
      HERMES_HOME: "${HERMES_HOME}"
    enabled: true
YAMLEOF
    log "Created config.yaml stub with MCP brain server"
fi

log "Directory structure ready"

# ── Startup injection: SOUL, MEMORY (curated + recent 2 days), USER, TOOLS ──
_inject_file() {
    local src="$1" dst="$2" label="$3"
    if [ -f "$src" ]; then
        log "  Injecting $label: $(basename "$src")"
    fi
}

# Inject SOUL.md
if [ -f "${HERMES_HOME}/SOUL.md" ]; then
    log "  SOUL.md loaded: $(head -1 "${HERMES_HOME}/SOUL.md")"
else
    warn "  SOUL.md missing for ${AGENT_ID}"
fi

# Inject MEMORY.md (curated long-term)
if [ -f "${HERMES_HOME}/MEMORY.md" ]; then
    log "  MEMORY.md loaded ($(wc -l < "${HERMES_HOME}/MEMORY.md") lines)"
else
    warn "  MEMORY.md missing for ${AGENT_ID}"
fi

# Inject last 2 days of daily memory files
if [ -d "${HERMES_HOME}/memory" ]; then
    _today=$(date +%Y-%m-%d)
    _yesterday=$(date -d "yesterday" +%Y-%m-%d 2>/dev/null || date -v-1d +%Y-%m-%d 2>/dev/null || echo "")
    _memory_count=0
    for mf in "${HERMES_HOME}/memory/${_today}.md" "${HERMES_HOME}/memory/${_yesterday}.md"; do
        if [ -f "$mf" ]; then
            log "  Daily memory: $(basename "$mf")"
            _memory_count=$((_memory_count + 1))
        fi
    done
    [ "$_memory_count" -eq 0 ] && log "  No recent daily memory files"
fi

# Inject USER.md
if [ -f "${HERMES_HOME}/USER.md" ]; then
    log "  USER.md loaded"
else
    warn "  USER.md missing for ${AGENT_ID}"
fi

# Inject TOOLS.md
if [ -f "${HERMES_HOME}/TOOLS.md" ]; then
    log "  TOOLS.md loaded"
else
    warn "  TOOLS.md missing for ${AGENT_ID}"
fi

# ── Auto-run workspace enforcement on every startup ──────────────────────────
if [ -f "${HERMES_HOME}/tools/enforce.sh" ]; then
    log "  Running workspace enforcement..."
    bash "${HERMES_HOME}/tools/enforce.sh" "${HERMES_HOME}" 2>/dev/null || warn "  Enforcement encountered issues"
else
    warn "  enforce.sh not found — skipping workspace enforcement"
fi

# ── Log final state ──────────────────────────────────────────────────────────
log "=== Agent/Crew ${AGENT_ID} ready ==="
log " HERMES_HOME: ${HERMES_HOME}"
log " SOUL.md: $(head -1 "${HERMES_HOME}/SOUL.md" 2>/dev/null || echo 'MISSING')"
log " Model: $(grep -E '^\s*(default|primary):' "${HERMES_HOME}/config.yaml" 2>/dev/null | head -1 | sed 's/^[[:space:]]*//' || echo 'not set')"
log " Telegram: ${TELEGRAM_BOT_TOKEN:+configured}${TELEGRAM_BOT_TOKEN:-not set}"

# ── Start processes based on mode ────────────────────────────────────────────

if [ "$MODE" = "full" ]; then
    # ── FULL MODE: OpenClaw fronts → per-agent MCP brains → Hermes cognition ───
    log "=== FULL MODE: OpenClaw → per-agent MCP brains → Hermes ==="

    # Generate the OpenClaw config: ONE brain-<name> MCP per agent volume under
    # /data/agents, each with its OWN AGENT_ID + HERMES_HOME (its own volume).
    # Isolate DATA per agent, share the baked TOOLS. Never a single shared brain.
    # This is the OpenClaw-managed MCP access to Hermes (not per-agent Hermes YAML).
    OPENCLAW_CFG="${OPENCLAW_CONFIG:-/root/.openclaw/openclaw.json}"
    if [ -f /opt/hermes/docker/gen-openclaw-config.py ]; then
        OPENCLAW_CONFIG="$OPENCLAW_CFG" AGENTS_DIR="/data/agents" \
            python3 /opt/hermes/docker/gen-openclaw-config.py 2>&1 | while IFS= read -r l; do log "  $l"; done
    else
        warn "gen-openclaw-config.py not found — OpenClaw will start unconfigured"
    fi

    # OpenClaw drives: platforms + routing + spawns each agent's brain MCP on demand.
    log "Starting OpenClaw gateway..."
    openclaw gateway run --allow-unconfigured &
    OPENCLAW_PID=$!
    log "OpenClaw gateway started (PID: ${OPENCLAW_PID})"

    # Hermes gateway is OPTIONAL in full mode (OpenClaw fronts the platforms). Off
    # by default so two gateways never fight over one platform; opt in explicitly.
    if [ "${ENABLE_HERMES_GATEWAY:-false}" = "true" ]; then
        log "Starting Hermes gateway (opt-in via ENABLE_HERMES_GATEWAY=true)..."
        python3 -m hermes_cli.main gateway run &
        HERMES_PID=$!
        log "Hermes gateway started (PID: ${HERMES_PID})"
    else
        log "Hermes gateway not started (ENABLE_HERMES_GATEWAY=false; OpenClaw fronts)"
    fi

    # Wait for any process to exit
    wait "$OPENCLAW_PID" 2>/dev/null || true
    [ "${HERMES_PID:-0}" -ne 0 ] && wait "$HERMES_PID" 2>/dev/null || true

elif [ "$MODE" = "hermes-only" ]; then
    # ── HERMES-ONLY MODE: Standalone Hermes (no OpenClaw) ─────────────────────
    log "=== HERMES-ONLY MODE: Standalone Hermes (no OpenClaw) ==="

    # NOTE: the brain MCP is launched ON DEMAND (stdio) by the Hermes gateway from
    # this agent's config.yaml `mcp_servers` — with stdin attached, so it stays up.
    # The old standalone `agent_brain_mcp.py --brain &` here was launched WITHOUT
    # stdin, hit EOF, and died immediately (breaking the auto-learn socket). Removed.

    # Start Hermes gateway (owns the platform + spawns this agent's brain MCP)
    log "Starting Hermes gateway..."
    python3 -m hermes_cli.main gateway run &
    HERMES_PID=$!
    log "Hermes gateway started (PID: ${HERMES_PID})"

    wait "$HERMES_PID" 2>/dev/null || true

elif [ "$MODE" = "openclaw-only" ]; then
    # ── OPENCLAW-ONLY MODE: OpenClaw runs its own agents; Hermes brains IGNORED ─
    log "=== OPENCLAW-ONLY MODE: OpenClaw only (no Hermes brains) ==="

    # Generate the agent config WITHOUT brain MCP servers (INCLUDE_BRAINS=0).
    OPENCLAW_CFG="${OPENCLAW_CONFIG:-/root/.openclaw/openclaw.json}"
    if [ -f /opt/hermes/docker/gen-openclaw-config.py ]; then
        OPENCLAW_CONFIG="$OPENCLAW_CFG" AGENTS_DIR="/data/agents" INCLUDE_BRAINS=0 \
            python3 /opt/hermes/docker/gen-openclaw-config.py 2>&1 | while IFS= read -r l; do log "  $l"; done
    fi

    # Start OpenClaw gateway
    log "Starting OpenClaw gateway..."
    openclaw gateway run --allow-unconfigured &
    OPENCLAW_PID=$!
    log "OpenClaw gateway started (PID: ${OPENCLAW_PID})"

    wait "$OPENCLAW_PID" 2>/dev/null || true
fi

EXIT_CODE=$?

if [ "$_term_received" -eq 1 ]; then
    log "Clean shutdown after signal"
    exit 0
fi

log "Process exited with code ${EXIT_CODE}"
exit "$EXIT_CODE"
