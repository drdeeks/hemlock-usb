#!/usr/bin/env bash
# =============================================================================
# inject-context.sh — Consolidated context injection for agent sessions
# Combines: identity, memory, tooling, autonomy protocol, subagent protocol
# Runs at session start or agent wake-up to build a single context.md file
# =============================================================================

set -euo pipefail

WS="${1:-${HEMLOCK_HOME:-$HERMES_HOME}}"

if [ -z "$WS" ] || [ ! -d "$WS" ]; then
    echo "ERROR: Workspace not found: $WS"
    echo "Set \$HERMES_HOME or pass path as argument."
    exit 1
fi

CONTEXT_FILE="$WS/context.md"
DATA_DIR="$WS"
TOOLS_DIR="$WS/tools"
MEMORY_DIR="$WS/memory"
SKILLS_DIR="$WS/skills"

SEPARATOR="---"

echo "# Agent Context" > "$CONTEXT_FILE"
echo "_Injected: $(date +%Y-%m-%dT%H:%M:%S)_" >> "$CONTEXT_FILE"
echo "" >> "$CONTEXT_FILE"

inject_file() {
    local label="$1"
    local filepath="$2"

    if [ -f "$filepath" ]; then
        echo "## $label" >> "$CONTEXT_FILE"
        echo "" >> "$CONTEXT_FILE"
        cat "$filepath" >> "$CONTEXT_FILE"
        echo "" >> "$CONTEXT_FILE"
        echo "$SEPARATOR" >> "$CONTEXT_FILE"
        echo "" >> "$CONTEXT_FILE"
        return 0
    else
        echo "## $label" >> "$CONTEXT_FILE"
        echo "" >> "$CONTEXT_FILE"
        echo "_Not available: $filepath_" >> "$CONTEXT_FILE"
        echo "" >> "$CONTEXT_FILE"
        echo "$SEPARATOR" >> "$CONTEXT_FILE"
        echo "" >> "$CONTEXT_FILE"
        return 1
    fi
}

HEAD_COUNT=0
MISSING=0

# ---------------------------------------------------------------------------
# 1. Identity: SOUL.md
# ---------------------------------------------------------------------------
if inject_file "Identity: SOUL.md" "$DATA_DIR/SOUL.md"; then
    HEAD_COUNT=$((HEAD_COUNT + 1))
else
    MISSING=$((MISSING + 1))
fi

# ---------------------------------------------------------------------------
# 1b. Identity constitution (t=0 layer): .agent/constitution.yaml
#     Optional — injected only when the identity layer is present.
# ---------------------------------------------------------------------------
if [ -f "$DATA_DIR/.agent/constitution.yaml" ]; then
    if inject_file "Identity Constitution (governs everything below)" "$DATA_DIR/.agent/constitution.yaml"; then
        HEAD_COUNT=$((HEAD_COUNT + 1))
    fi
fi

# ---------------------------------------------------------------------------
# 2. Long-term memory: MEMORY.md
# ---------------------------------------------------------------------------
if inject_file "Long-term Memory: MEMORY.md" "$DATA_DIR/MEMORY.md"; then
    HEAD_COUNT=$((HEAD_COUNT + 1))
else
    MISSING=$((MISSING + 1))
fi

# ---------------------------------------------------------------------------
# 3a. Operating standard: AGENTS.md (forced to-do, handoff, versioning, secrets)
# ---------------------------------------------------------------------------
if inject_file "Operating Standard: AGENTS.md" "$DATA_DIR/AGENTS.md"; then
    HEAD_COUNT=$((HEAD_COUNT + 1))
else
    MISSING=$((MISSING + 1))
fi

# ---------------------------------------------------------------------------
# 3b. Tooling reference + registry: TOOLS.md (TOOLS-GUIDE.md consolidated here)
# ---------------------------------------------------------------------------
if inject_file "Tools Reference: TOOLS.md" "$DATA_DIR/TOOLS.md"; then
    HEAD_COUNT=$((HEAD_COUNT + 1))
else
    MISSING=$((MISSING + 1))
fi

# ---------------------------------------------------------------------------
# 4. Daily memory: last 2 days
# ---------------------------------------------------------------------------
echo "## Daily Memory Files" >> "$CONTEXT_FILE"
echo "" >> "$CONTEXT_FILE"

DAILY_COUNT=0
TODAY=$(date +%Y-%m-%d)
YESTERDAY=$(date -d "yesterday" +%Y-%m-%d 2>/dev/null || date -v-1d +%Y-%m-%d 2>/dev/null || echo "")

for d in "$TODAY" "$YESTERDAY"; do
    [ -z "$d" ] && continue
    daily_file="$MEMORY_DIR/${d}.md"
    if [ -f "$daily_file" ]; then
        echo "### ${d}" >> "$CONTEXT_FILE"
        echo "" >> "$CONTEXT_FILE"
        cat "$daily_file" >> "$CONTEXT_FILE"
        echo "" >> "$CONTEXT_FILE"
        DAILY_COUNT=$((DAILY_COUNT + 1))
        HEAD_COUNT=$((HEAD_COUNT + 1))
    fi
done

if [ "$DAILY_COUNT" -eq 0 ]; then
    echo "_No daily memory files found for today or yesterday._" >> "$CONTEXT_FILE"
    echo "" >> "$CONTEXT_FILE"
fi

echo "$SEPARATOR" >> "$CONTEXT_FILE"
echo "" >> "$CONTEXT_FILE"

# ---------------------------------------------------------------------------
# 5. Autonomy Protocol: 5-Layer Decision Framework
# ---------------------------------------------------------------------------
echo "## Autonomy Protocol: 5-Layer Decision Framework" >> "$CONTEXT_FILE"
echo "" >> "$CONTEXT_FILE"
cat >> "$CONTEXT_FILE" <<'AUTONOMY'
When facing a task, ask in order:

1. **Script** — Has this been done before? Is it deterministic? → Write/update a script.
2. **Tool** — Does a tool already do this? → Use it. Don't reinvent.
3. **Skill** — Is there a methodology or workflow? → Follow the skill's procedure.
4. **Subagent** — Is this a discrete, well-scoped subtask? → Dispatch a fresh subagent.
5. **Main Agent** — Does this require LLM judgment, creativity, or ad-hoc reasoning? → Do it yourself.

### Nine Axioms
1. **Deterministic-first** — If it can be a script, make it a script.
2. **State-in-files** — All persistent state lives in files, not in context.
3. **Use-existing-tools** — Never rewrite what a tool already does.
4. **Build-on-third-repetition** — If you've done it 3 times, automate it.
5. **Fail-loudly** — Errors are visible, never silently swallowed.
6. **Skills-constrain-emergence** — Skills provide guardrails for LLM freedom.
7. **Skills-are-bridges** — Skills connect deterministic scripts to emergent agent behavior.
8. **Fresh-context-beats-exhausted** — Prefer a new subagent over a long context.
9. **Subagents-get-full-SOUL** — Every subagent receives the full identity context.
AUTONOMY
echo "" >> "$CONTEXT_FILE"
echo "$SEPARATOR" >> "$CONTEXT_FILE"
echo "" >> "$CONTEXT_FILE"
HEAD_COUNT=$((HEAD_COUNT + 1))

# ---------------------------------------------------------------------------
# 6. Subagent-Driven Development Protocol
# ---------------------------------------------------------------------------
echo "## Subagent-Driven Development Protocol" >> "$CONTEXT_FILE"
echo "" >> "$CONTEXT_FILE"
cat >> "$CONTEXT_FILE" <<'SUBAGENT'
**Core principle:** Fresh subagent per task + two-stage review.

### Process
1. Read and parse the plan, create a todo list.
2. Per task: dispatch implementer → spec reviewer → code quality reviewer → mark complete.
3. Final integration review after all tasks done.
4. Verify and commit.

### Task Granularity
- Each task: 2-5 minutes of work
- One clear deliverable per task
- Tasks must be independently verifiable

### Review Stages
1. **Spec compliance** — Does the implementation match the specification?
2. **Code quality** — Is the code clean, idiomatic, well-tested?

### Red Flags
- Never skip reviews
- Never self-review (use a different subagent)
- Spec review before quality review
SUBAGENT
echo "" >> "$CONTEXT_FILE"
echo "$SEPARATOR" >> "$CONTEXT_FILE"
echo "" >> "$CONTEXT_FILE"
HEAD_COUNT=$((HEAD_COUNT + 1))

# ---------------------------------------------------------------------------
# 7. Core Skills Context (if available)
# ---------------------------------------------------------------------------
if [ -d "$SKILLS_DIR" ]; then
    echo "## Available Skills" >> "$CONTEXT_FILE"
    echo "" >> "$CONTEXT_FILE"

    SKILL_COUNT=0
    for skill_dir in "$SKILLS_DIR"/*/; do
        [ -d "$skill_dir" ] || continue
        skill_name=$(basename "$skill_dir")
        skill_md="$skill_dir/SKILL.md"
        if [ -f "$skill_md" ]; then
            description=$(sed -n '/^---$/,/^---$/p' "$skill_md" 2>/dev/null | grep -A1 '^description:' | tail -1 | sed 's/^  *//')
            echo "- **$skill_name**: $description" >> "$CONTEXT_FILE"
            SKILL_COUNT=$((SKILL_COUNT + 1))
        fi
    done

    if [ "$SKILL_COUNT" -eq 0 ]; then
        echo "_No skills with SKILL.md found._" >> "$CONTEXT_FILE"
    fi

    echo "" >> "$CONTEXT_FILE"
    echo "$SEPARATOR" >> "$CONTEXT_FILE"
    echo "" >> "$CONTEXT_FILE"
fi

# ---------------------------------------------------------------------------
# 8. Tool Enforcement Rules
# ---------------------------------------------------------------------------
echo "## Tool Enforcement Rules" >> "$CONTEXT_FILE"
echo "" >> "$CONTEXT_FILE"
cat >> "$CONTEXT_FILE" <<'ENFORCEMENT'
- Use `write_file`/`read_file`/`patch`/`search_files`/`execute_code` properly
- Terminal only for git operations and build/restart commands
- Never write to `/tmp` for persistent data
- **NEVER** `chmod 700` or `chmod 000` — use 755 for dirs, 644 for files
- All files must be inside `$HERMES_HOME` — never create `agent-*` directories
- Write to files, never overwrite memory — append only
- Check `.secrets/` before asking user for credentials
- Check TOOLS.md before asking for assistance
- For any task needing more than two edits/steps, create a to-do list first (todo tool)
ENFORCEMENT
echo "" >> "$CONTEXT_FILE"
echo "$SEPARATOR" >> "$CONTEXT_FILE"
echo "" >> "$CONTEXT_FILE"
HEAD_COUNT=$((HEAD_COUNT + 1))

# ---------------------------------------------------------------------------
# Footer
# ---------------------------------------------------------------------------
echo "_Context injection complete: $HEAD_COUNT sections injected, $MISSING missing._" >> "$CONTEXT_FILE"

chmod 644 "$CONTEXT_FILE"

echo "=== Context injected: $CONTEXT_FILE ($HEAD_COUNT sections, $MISSING missing) ==="