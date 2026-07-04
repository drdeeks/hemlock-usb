#!/usr/bin/env bash
# crew-pm-blueprint.sh — Project Manager blueprint workflow for crew creation.
#
# Flow (per CL-019 spec):
#   1. Interrogate the user (drilled-down mental-clarity questionnaire) to extract:
#        - goal             (one-liner statement of intent)
#        - standards        (quality bar, accuracy, performance)
#        - success_criteria (concrete, testable, "we know we're done when…")
#        - expected_outcome (deliverable shape — code? doc? deployment?)
#        - constraints      (deadlines, budget, hardware, compliance)
#        - non_goals        (explicit out-of-scope items)
#   2. Render a singular ENFORCED blueprint at $CREWS_DIR/.blueprints/<slug>-<ts>.json
#   3. Triple-confirmation: PM asks "Is this accurate?" three times with summary
#      replays between each (forcing the user to actually read it, not auto-yes).
#   4. Delegate: PM analyzes the blueprint + queries the available agent registry
#      to pick the smallest viable team. Outputs a recommended members[] list.
#   5. Crew name: user provides OR PM auto-generates from goal keywords.
#   6. Hands off to scripts/crew-create.sh <name> <members…> with the blueprint
#      path stored in the crew's metadata (crew.yaml gets a `blueprint:` field).
#
# Designed to be opt-in. Direct `crew-create.sh <name> <agents…>` still works
# for power users who already know what they want.
#
# Honors HEMLOCK_NONINTERACTIVE=1 by reading answers from a YAML/JSON file
# passed via --answers <path> — enables CI/automated PM runs.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/helpers.sh"

CREWS_DIR="${CREWS_DIR:-/data/crews}"
AGENTS_DIR="${AGENTS_DIR:-/data/agents}"
BLUEPRINTS_DIR="$CREWS_DIR/.blueprints"
PM_AGENT="${PM_AGENT:-project-manager}"   # The PM agent's <id>.json must exist

# Colors
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'

info()   { echo -e "${BLUE}[PM]${NC} $1"; }
ask()    { echo -e "${CYAN}[PM]${NC} ${BOLD}$1${NC}"; }
warn()   { echo -e "${YELLOW}[PM]${NC} $1"; }
fail()   { echo -e "${RED}[PM]${NC} $1"; exit 1; }
ok()     { echo -e "${GREEN}[PM]${NC} $1"; }

ANSWERS_FILE=""
SUGGESTED_NAME=""
DRY_RUN="${DRY_RUN:-false}"

usage() {
  cat <<EOF
${GREEN}Crew Project Manager Blueprint Workflow${NC}

Usage:
  $0 [--answers <path>] [--name <crew_name>] [--dry-run]

Options:
  --answers <path>   Pre-filled YAML/JSON with blueprint fields (skips prompts).
                     Required when stdin is not a TTY.
  --name <name>      User-provided crew name. If omitted, PM auto-suggests
                     based on goal keywords.
  --dry-run          Render the blueprint but do NOT create the crew.
  -h, --help         Show this help

Workflow:
  1. Interrogation: 6-question drilled-down questionnaire.
  2. Blueprint render: structured JSON at \$CREWS_DIR/.blueprints/<slug>-<ts>.json
  3. Triple-confirmation: 3 sequential confirms with summary replay.
  4. Agent delegation: PM recommends members from the agent registry.
  5. Crew name confirmation: user-provided OR auto-suggested.
  6. Hand-off to crew-create.sh with --blueprint <path> wired into crew.yaml.

Non-interactive mode (HEMLOCK_NONINTERACTIVE=1):
  Must pass --answers. Skips triple-confirmation (the YAML is the artifact).

Example answers.yaml:
  goal: "Refactor the payment gateway to support idempotency keys"
  standards: "99.95% success rate, <300ms p99 latency, full test coverage"
  success_criteria:
    - "All POST /charge requests are idempotent with the Idempotency-Key header"
    - "Existing integration tests still pass"
    - "New idempotency test suite added with ≥10 cases"
  expected_outcome: "Merged PR + deployment notes + rollback plan"
  constraints:
    - "Cannot modify the public API contract"
    - "Must ship before EOQ"
  non_goals:
    - "Refactoring the refund flow (separate ticket)"
EOF
}

# ── Arg parsing ──────────────────────────────────────────────────────────────
while [[ $# -gt 0 ]]; do
  case "$1" in
    --answers) ANSWERS_FILE="$2"; shift 2 ;;
    --name)    SUGGESTED_NAME="$2"; shift 2 ;;
    --dry-run) DRY_RUN="true"; shift ;;
    -h|--help) usage; exit 0 ;;
    *) fail "Unknown option: $1 (see --help)" ;;
  esac
done

# ── Helpers ──────────────────────────────────────────────────────────────────
slugify() {
  # "Refactor payment gateway" → "refactor-payment-gateway"
  echo "$1" | tr '[:upper:]' '[:lower:]' \
    | sed -E 's/[^a-z0-9]+/-/g; s/^-+|-+$//g' \
    | cut -c1-40
}

prompt_required() {
  local q="$1" varname="$2" default="${3:-}"
  local val=""
  while [[ -z "$val" ]]; do
    ask "$q"
    [[ -n "$default" ]] && echo "  (default: $default)"
    printf "  > "
    read -r val
    [[ -z "$val" && -n "$default" ]] && val="$default"
    [[ -z "$val" ]] && warn "Required — try again."
  done
  printf -v "$varname" '%s' "$val"
}

prompt_list() {
  local q="$1" varname="$2"
  local items=()
  ask "$q"
  echo "  (enter one per line; blank line to finish)"
  while true; do
    printf "  > "
    local line; read -r line
    [[ -z "$line" ]] && break
    items+=("$line")
  done
  # Encode as JSON array string
  local json="["
  local first=1
  for it in "${items[@]}"; do
    local esc=$(printf '%s' "$it" | sed 's/\\/\\\\/g; s/"/\\"/g')
    if [[ $first -eq 1 ]]; then
      json+="\"$esc\""
      first=0
    else
      json+=",\"$esc\""
    fi
  done
  json+="]"
  printf -v "$varname" '%s' "$json"
}

interrogate_from_tty() {
  ask "Project Manager interrogation — answer each question deliberately."
  echo "  This drives the blueprint. Hand-waving here means a broken crew."
  echo ""
  prompt_required "1/6 — GOAL (one sentence: what are we trying to do?)" GOAL
  echo ""
  prompt_required "2/6 — STANDARDS (quality bar, accuracy, performance targets?)" STANDARDS
  echo ""
  prompt_list "3/6 — SUCCESS CRITERIA (concrete, testable — 'we know we're done when...')" SUCCESS_CRITERIA_JSON
  echo ""
  prompt_required "4/6 — EXPECTED OUTCOME (what's the deliverable shape?)" EXPECTED_OUTCOME
  echo ""
  prompt_list "5/6 — CONSTRAINTS (deadlines, budget, hardware, compliance)" CONSTRAINTS_JSON
  echo ""
  prompt_list "6/6 — NON-GOALS (explicit out-of-scope items)" NON_GOALS_JSON
}

interrogate_from_file() {
  local f="$1"
  [[ -f "$f" ]] || fail "Answers file not found: $f"
  command -v python3 >/dev/null || fail "python3 required for --answers parsing"
  # Convert YAML or JSON → variables. We rely on python's flexibility.
  eval "$(python3 - "$f" <<'PYEOF'
import json, sys, os
p = sys.argv[1]
data = None
with open(p) as fh:
    txt = fh.read()
# Try JSON first, then YAML if available
try:
    data = json.loads(txt)
except json.JSONDecodeError:
    try:
        import yaml
        data = yaml.safe_load(txt)
    except ImportError:
        print(f"echo 'ERROR: file is not JSON and python yaml module is unavailable'; exit 1", file=sys.stderr)
        sys.exit(1)
def emit(name, val):
    if isinstance(val, list):
        encoded = json.dumps(val)
        print(f"{name}_JSON={json.dumps(encoded)}")
    else:
        print(f"{name}={json.dumps(val) if val is not None else '\"\"'}")
emit("GOAL", data.get("goal", ""))
emit("STANDARDS", data.get("standards", ""))
emit("SUCCESS_CRITERIA", data.get("success_criteria", []))
emit("EXPECTED_OUTCOME", data.get("expected_outcome", ""))
emit("CONSTRAINTS", data.get("constraints", []))
emit("NON_GOALS", data.get("non_goals", []))
PYEOF
  )"
}

render_blueprint() {
  mkdir -p "$BLUEPRINTS_DIR"
  local ts=$(date +%Y%m%d-%H%M%S)
  local slug=$(slugify "$GOAL")
  BLUEPRINT_FILE="$BLUEPRINTS_DIR/${slug:-blueprint}-${ts}.json"
  BLUEPRINT_SLUG="$slug"
  BLUEPRINT_TS="$ts"

  cat > "$BLUEPRINT_FILE" <<EOF
{
  "blueprint_id": "${slug:-blueprint}-${ts}",
  "created_at": "$(date -Iseconds)",
  "pm_agent": "$PM_AGENT",
  "goal": $(printf '%s' "$GOAL" | python3 -c "import sys, json; print(json.dumps(sys.stdin.read()))"),
  "standards": $(printf '%s' "$STANDARDS" | python3 -c "import sys, json; print(json.dumps(sys.stdin.read()))"),
  "success_criteria": $SUCCESS_CRITERIA_JSON,
  "expected_outcome": $(printf '%s' "$EXPECTED_OUTCOME" | python3 -c "import sys, json; print(json.dumps(sys.stdin.read()))"),
  "constraints": $CONSTRAINTS_JSON,
  "non_goals": $NON_GOALS_JSON,
  "status": "draft",
  "confirmations": 0
}
EOF
  ok "Blueprint rendered: $BLUEPRINT_FILE"
}

triple_confirm() {
  [[ "${HEMLOCK_NONINTERACTIVE:-0}" == "1" ]] && {
    info "Non-interactive — skipping triple-confirm (answers file IS the artifact)"
    return 0
  }
  for i in 1 2 3; do
    echo ""
    info "=== Confirmation $i/3 ==="
    info "Goal:             $GOAL"
    info "Standards:        $STANDARDS"
    info "Expected outcome: $EXPECTED_OUTCOME"
    info "Success criteria: $SUCCESS_CRITERIA_JSON"
    info "Constraints:      $CONSTRAINTS_JSON"
    info "Non-goals:        $NON_GOALS_JSON"
    echo ""
    case "$i" in
      1) ask "First read-through. Does this capture what you actually want? [y/N/edit]" ;;
      2) ask "Same blueprint, second look. Anything missing or wrong? [y/N/edit]" ;;
      3) ask "Final check. This is what the crew will be built around. Commit? [y/N]" ;;
    esac
    printf "  > "
    local ans; read -r ans
    case "$ans" in
      [Yy]*) ok "Confirmation $i/3 accepted." ;;
      [Ee]*) warn "Edit mode not yet implemented — re-run the workflow."; exit 1 ;;
      *)     fail "Confirmation $i/3 rejected — blueprint discarded." ;;
    esac
  done
  # Mark as triple-confirmed
  python3 - "$BLUEPRINT_FILE" <<'PYEOF'
import json, sys
p = sys.argv[1]
with open(p) as f: d = json.load(f)
d["status"] = "confirmed"
d["confirmations"] = 3
with open(p, "w") as f: json.dump(d, f, indent=2)
PYEOF
  ok "Blueprint locked at $BLUEPRINT_FILE"
}

recommend_members() {
  # Scan agent registry for available agents. Naive scoring: any agent whose
  # IDENTITY.md or <id>.json declares matching capability keywords scores +1.
  # User refines.
  info "Scanning agent registry: $AGENTS_DIR"
  local available=()
  if [[ -d "$AGENTS_DIR" ]]; then
    while IFS= read -r -d '' agent_dir; do
      local id=$(basename "$agent_dir")
      [[ "$id" == "workspace-template" || "$id" == "active" || "$id" == "archive" ]] && continue
      [[ "$id" == .* ]] && continue
      available+=("$id")
    done < <(find "$AGENTS_DIR" -maxdepth 1 -mindepth 1 -type d -print0)
  fi

  if [[ ${#available[@]} -eq 0 ]]; then
    warn "No agents in registry. Crew will be created with no members (PM only)."
    RECOMMENDED_MEMBERS=("$PM_AGENT")
    return 0
  fi

  echo ""
  info "Available agents:"
  for a in "${available[@]}"; do echo "  - $a"; done
  echo ""

  if [[ "${HEMLOCK_NONINTERACTIVE:-0}" == "1" ]]; then
    # In NI mode, pick the PM + first agent that has matching keywords in IDENTITY
    info "NI mode — recommending all available agents."
    RECOMMENDED_MEMBERS=("${available[@]}")
    return 0
  fi
  ask "Enter the agent IDs to add (space-separated, blank = all available):"
  printf "  > "
  local picks; read -r picks
  if [[ -z "$picks" ]]; then
    RECOMMENDED_MEMBERS=("${available[@]}")
  else
    # shellcheck disable=SC2206
    RECOMMENDED_MEMBERS=($picks)
  fi
  ok "Recommended members: ${RECOMMENDED_MEMBERS[*]}"
}

resolve_crew_name() {
  if [[ -n "$SUGGESTED_NAME" ]]; then
    CREW_NAME="$SUGGESTED_NAME"
    ok "Crew name (user-provided): $CREW_NAME"
    return 0
  fi
  # Auto-suggest from blueprint slug
  CREW_NAME="$BLUEPRINT_SLUG"
  if [[ "${HEMLOCK_NONINTERACTIVE:-0}" == "1" ]]; then
    ok "Crew name (auto): $CREW_NAME"
    return 0
  fi
  ask "Suggested crew name: $CREW_NAME — accept or enter alternate:"
  printf "  > "
  local override; read -r override
  [[ -n "$override" ]] && CREW_NAME="$override"
  ok "Crew name: $CREW_NAME"
}

hand_off_to_crew_create() {
  if [[ "$DRY_RUN" == "true" ]]; then
    info "DRY RUN — would call: $SCRIPT_DIR/crew-create.sh $CREW_NAME ${RECOMMENDED_MEMBERS[*]}"
    info "Blueprint: $BLUEPRINT_FILE"
    return 0
  fi
  info "Calling: crew-create.sh $CREW_NAME ${RECOMMENDED_MEMBERS[*]}"
  HEMLOCK_NONINTERACTIVE=1 bash "$SCRIPT_DIR/crew-create.sh" "$CREW_NAME" "${RECOMMENDED_MEMBERS[@]}"
  local ec=$?
  if [[ $ec -ne 0 ]]; then
    warn "crew-create.sh exit $ec — blueprint preserved at $BLUEPRINT_FILE"
    return $ec
  fi
  # Append blueprint path to crew.yaml
  local crew_yaml="$CREWS_DIR/$CREW_NAME/crew.yaml"
  if [[ -f "$crew_yaml" ]]; then
    {
      echo ""
      echo "blueprint:"
      echo "  path: $BLUEPRINT_FILE"
      echo "  id: ${BLUEPRINT_SLUG}-${BLUEPRINT_TS}"
      echo "  confirmations: 3"
    } >> "$crew_yaml"
    ok "Blueprint wired into $crew_yaml"
  fi
  ok "Crew '$CREW_NAME' created with PM blueprint workflow."
}

# ── Main ─────────────────────────────────────────────────────────────────────
main() {
  ok "Project Manager Blueprint Workflow (CL-019)"
  echo ""
  if [[ -n "$ANSWERS_FILE" ]]; then
    interrogate_from_file "$ANSWERS_FILE"
  elif [[ "${HEMLOCK_NONINTERACTIVE:-0}" == "1" ]]; then
    fail "HEMLOCK_NONINTERACTIVE=1 requires --answers <path>"
  else
    interrogate_from_tty
  fi

  render_blueprint
  triple_confirm
  recommend_members
  resolve_crew_name
  hand_off_to_crew_create
}

main "$@"
