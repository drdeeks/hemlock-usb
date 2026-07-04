#!/usr/bin/env bash
# agent-register.sh — Registrar entry point (CL-020 stub).
#
# Real flow (when chain integration ships):
#   1. agent-create.sh creates the lean workspace (CL-018)
#   2. registrar generates X402 wallet → /data/agents/<id>/.secrets/x402.key
#   3. registrar hashes IDENTITY.md + TOOLS.md + skills/ manifest
#   4. registrar emits on-chain tx with {agent_id, pubkey, identity_hash,
#      tools_hash, skills_hash, registered_at, registrar_sig}
#   5. tx_hash + block + contract written to /data/agents/<id>/<id>.json under
#      a "chain" key
#   6. signed attestation dropped at /data/agents/<id>/.secrets/registrar.attestation.json
#
# CURRENT BEHAVIOR (stub_mode=true in registrar.json):
#   Steps 1-2 happen normally. Step 3 hashes are real. Steps 4-6 write to
#   a local JSON ledger at /data/agents/registrar/.secrets/local-registry.json
#   instead of a real chain. Every downstream consumer (PM, menu, audit) works
#   the same — only difference is the tx_hash format ("local:<sha>" instead
#   of "0x<64hex>"). When real RPC lands, swap the _emit_chain_tx() function.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/helpers.sh"

AGENTS_DIR="${AGENTS_DIR:-/data/agents}"
REGISTRAR_DIR="$AGENTS_DIR/registrar"
LEDGER="$REGISTRAR_DIR/.secrets/local-registry.json"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'
info()  { echo -e "${BLUE}[registrar]${NC} $1"; }
ok()    { echo -e "${GREEN}[registrar]${NC} $1"; }
warn()  { echo -e "${YELLOW}[registrar]${NC} $1"; }
fail()  { echo -e "${RED}[registrar]${NC} $1"; exit 1; }

AGENT_ID=""; NAME=""; MODEL=""; REFRESH=false; SKIP_CREATE=false

usage() {
  cat <<EOF
Registrar — register a new agent on-chain (or refresh existing registration)

Usage:
  $0 --id <agent_id> [--name <name>] [--model <model>] [--refresh] [--skip-create]

Options:
  --id <id>        Agent ID (required)
  --name <name>    Display name (default: agent_id)
  --model <model>  Provider/model string (default: anthropic/claude-sonnet-4-5)
  --refresh        Re-register an existing agent (idempotent if hashes match)
  --skip-create    Skip agent-create.sh (agent must already exist)
  -h, --help       Show this help

Examples:
  # Create + register fresh agent
  $0 --id alice --name "Alice" --model anthropic/claude-sonnet-4-5

  # Re-register after IDENTITY.md or TOOLS.md changed
  $0 --id alice --refresh

  # Register an existing agent (skip the create step)
  $0 --id existing-agent --skip-create
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --id) AGENT_ID="$2"; shift 2 ;;
    --name) NAME="$2"; shift 2 ;;
    --model) MODEL="$2"; shift 2 ;;
    --refresh) REFRESH=true; shift ;;
    --skip-create) SKIP_CREATE=true; shift ;;
    -h|--help) usage; exit 0 ;;
    *) fail "Unknown option: $1" ;;
  esac
done
[[ -z "$AGENT_ID" ]] && { usage; fail "--id is required"; }
[[ -z "$NAME" ]] && NAME="$AGENT_ID"
[[ -z "$MODEL" ]] && MODEL="anthropic/claude-sonnet-4-5"

# ── Ensure registrar workspace exists ───────────────────────────────────────
mkdir -p "$REGISTRAR_DIR/.secrets" "$REGISTRAR_DIR/logs"
chmod 700 "$REGISTRAR_DIR/.secrets" 2>/dev/null || true
[[ -f "$LEDGER" ]] || echo '{"version":1,"entries":{}}' > "$LEDGER"

# ── 1. Create agent (lean CL-018 workspace) unless --skip-create ───────────
agent_dir="$AGENTS_DIR/$AGENT_ID"
if [[ "$SKIP_CREATE" != true ]] && [[ ! -d "$agent_dir" ]]; then
  info "Creating agent workspace via agent-create.sh"
  HEMLOCK_NONINTERACTIVE=1 SKIP_PROMPTS=true bash "$SCRIPT_DIR/agent-create.sh" \
    --id "$AGENT_ID" --name "$NAME" --model "$MODEL" \
    || fail "agent-create.sh failed"
elif [[ ! -d "$agent_dir" ]]; then
  fail "Agent dir missing and --skip-create set: $agent_dir"
fi

# ── 2. Provision X402 wallet (stub) ─────────────────────────────────────────
wallet_file="$agent_dir/.secrets/x402.key"
if [[ ! -f "$wallet_file" ]]; then
  info "Provisioning X402 wallet (stub — local pseudo-key)"
  # Real impl: thirdweb-sdk or ethers.js generates a real keypair.
  # Stub: 32-byte random hex (correct format, fake derivation).
  mkdir -p "$(dirname "$wallet_file")"
  head -c 32 /dev/urandom | xxd -p -c 64 > "$wallet_file"
  chmod 600 "$wallet_file" 2>/dev/null || true
  ok "Wallet provisioned: $wallet_file"
fi
WALLET_PUB="0xstub_$(sha256sum "$wallet_file" | awk '{print substr($1,1,40)}')"

# ── 3. Hash identity + tools + skills manifests ─────────────────────────────
hash_file() {
  [[ -f "$1" ]] && sha256sum "$1" | awk '{print $1}' || echo "missing"
}
hash_dir_manifest() {
  if [[ -d "$1" ]]; then
    (cd "$1" && find . -type f -print0 2>/dev/null | sort -z | xargs -0 sha256sum 2>/dev/null | sha256sum | awk '{print $1}')
  else
    echo "missing"
  fi
}

ID_JSON="$agent_dir/${AGENT_ID}.json"
[[ -f "$ID_JSON" ]] || ID_JSON="$agent_dir/agent.json"  # legacy fallback

IDENTITY_HASH=$(hash_file "$agent_dir/IDENTITY.md")
TOOLS_HASH=$(hash_file "$agent_dir/TOOLS.md")
SOUL_HASH=$(hash_file "$agent_dir/SOUL.md")
SKILLS_HASH=$(hash_dir_manifest "$agent_dir/skills")
# Hash <id>.json with the mutable "chain" block stripped so idempotency
# survives our own writes. Falls back to raw file hash if python3 absent.
if command -v python3 >/dev/null 2>&1 && [[ -f "$ID_JSON" ]]; then
  JSON_HASH=$(python3 - "$ID_JSON" <<'PYEOF'
import json, hashlib, sys
with open(sys.argv[1]) as f: d = json.load(f)
d.pop("chain", None)
print(hashlib.sha256(json.dumps(d, sort_keys=True).encode()).hexdigest())
PYEOF
)
else
  JSON_HASH=$(hash_file "$ID_JSON")
fi
COMBINED_HASH=$(printf '%s%s%s%s%s' "$IDENTITY_HASH" "$TOOLS_HASH" "$SOUL_HASH" "$JSON_HASH" "$SKILLS_HASH" | sha256sum | awk '{print $1}')

# ── 4. Idempotency check (--refresh path) ───────────────────────────────────
existing_tx=""
if command -v python3 >/dev/null 2>&1; then
  existing_tx=$(python3 - "$LEDGER" "$AGENT_ID" <<'PYEOF'
import json, sys
with open(sys.argv[1]) as f: d = json.load(f)
print(d.get("entries", {}).get(sys.argv[2], {}).get("tx_hash", ""))
PYEOF
)
fi
existing_hash=""
if command -v python3 >/dev/null 2>&1 && [[ -n "$existing_tx" ]]; then
  existing_hash=$(python3 - "$LEDGER" "$AGENT_ID" <<'PYEOF'
import json, sys
with open(sys.argv[1]) as f: d = json.load(f)
print(d.get("entries", {}).get(sys.argv[2], {}).get("combined_hash", ""))
PYEOF
)
fi
if [[ -n "$existing_tx" ]] && [[ "$existing_hash" == "$COMBINED_HASH" ]] && [[ "$REFRESH" != true ]]; then
  ok "Already registered with current hashes — no-op (tx=$existing_tx)"
  exit 0
fi

# ── 5. Emit chain tx (stub: write to local ledger) ──────────────────────────
TIMESTAMP=$(date -Iseconds)
TX_HASH="local:$(printf '%s%s%s' "$AGENT_ID" "$COMBINED_HASH" "$TIMESTAMP" | sha256sum | awk '{print $1}')"

# Append to local ledger
python3 - "$LEDGER" "$AGENT_ID" "$NAME" "$MODEL" "$WALLET_PUB" \
  "$IDENTITY_HASH" "$TOOLS_HASH" "$SKILLS_HASH" "$JSON_HASH" \
  "$COMBINED_HASH" "$TX_HASH" "$TIMESTAMP" <<'PYEOF'
import json, sys
p = sys.argv[1]
with open(p) as f: d = json.load(f)
d.setdefault("entries", {})
d["entries"][sys.argv[2]] = {
    "agent_id": sys.argv[2],
    "name": sys.argv[3],
    "model": sys.argv[4],
    "wallet_pub": sys.argv[5],
    "identity_hash": sys.argv[6],
    "tools_hash": sys.argv[7],
    "skills_hash": sys.argv[8],
    "json_hash": sys.argv[9],
    "combined_hash": sys.argv[10],
    "tx_hash": sys.argv[11],
    "registered_at": sys.argv[12],
    "status": "active",
    "registrar_version": "1.0.0-stub",
}
with open(p, "w") as f: json.dump(d, f, indent=2)
PYEOF
ok "Chain tx emitted (stub): $TX_HASH"

# ── 6. Write chain block into agent's <id>.json + attestation ───────────────
if [[ -f "$ID_JSON" ]] && command -v python3 >/dev/null 2>&1; then
  python3 - "$ID_JSON" "$WALLET_PUB" "$TX_HASH" "$COMBINED_HASH" "$TIMESTAMP" <<'PYEOF'
import json, sys
p = sys.argv[1]
with open(p) as f: d = json.load(f)
d["chain"] = {
    "wallet_pub": sys.argv[2],
    "tx_hash": sys.argv[3],
    "combined_hash": sys.argv[4],
    "registered_at": sys.argv[5],
    "registrar": "registrar",
    "stub": True,
}
with open(p, "w") as f: json.dump(d, f, indent=2)
PYEOF
  ok "Updated $ID_JSON with chain block"
fi

attestation="$agent_dir/.secrets/registrar.attestation.json"
cat > "$attestation" <<EOF
{
  "agent_id": "$AGENT_ID",
  "tx_hash": "$TX_HASH",
  "combined_hash": "$COMBINED_HASH",
  "wallet_pub": "$WALLET_PUB",
  "registered_at": "$TIMESTAMP",
  "registrar_sig": "stub-$(printf '%s' "$COMBINED_HASH$TX_HASH" | sha256sum | awk '{print substr($1,1,32)}')",
  "stub_mode": true
}
EOF
chmod 600 "$attestation" 2>/dev/null || true
ok "Attestation written: $attestation"

# Audit log
echo "[$TIMESTAMP] register $AGENT_ID tx=$TX_HASH combined=$COMBINED_HASH" >> "$REGISTRAR_DIR/logs/registry.log"

ok "Registration complete for agent: $AGENT_ID"
echo "  Wallet pub:    $WALLET_PUB"
echo "  Tx hash:       $TX_HASH"
echo "  Combined hash: $COMBINED_HASH"
echo "  Ledger:        $LEDGER"
echo "  Attestation:   $attestation"
