# Entrypoint Pattern — Avoiding Heredoc Nesting in Docker Run

## Problem

When using `docker run --entrypoint bash -c "..."` with embedded heredocs (`<<EOF`), the outer bash interprets the inner heredoc delimiters, causing syntax errors:

```bash
# BROKEN - nested heredocs
docker run --rm -v vol:/workspace alpine sh -c "
    cat > /workspace/file.txt <<EOF
    content
    EOF
"
```

## Solution: Temp Script Pattern

Write the inner script to a temporary file, then execute it:

```bash
# In entrypoint.sh
create_agent_workspace() {
    local agent_id="$1"
    local model="${2:-anthropic/claude-sonnet-4}"
    local name="${3:-$agent_id}"
    local vol="hemlock-agent-$agent_id"
    
    if docker volume inspect "$vol" &>/dev/null; then
        error "Agent '$agent_id' already exists (volume $vol exists)"
        return 1
    fi
    
    log "Creating agent volume: $vol"
    docker volume create "$vol" >/dev/null
    
    # Write inner script to temp file to avoid heredoc nesting issues
    local tmp_script=$(mktemp)
    cat > "$tmp_script" <<'INNER_EOF'
#!/bin/sh
set -e

mkdir -p /workspace/{memory,sessions,skills,tools,.secrets,logs,media,projects,config,cron}
# No 700 permissions anywhere - .secrets uses default permissions
ln -sfn /shared-skills /workspace/shared-skills 2>/dev/null || true

# Create agent.json
cat > /workspace/agent.json <<EOF
{"id":"$AGENT_ID","name":"$NAME","model":"$MODEL","provider":"openrouter","status":"created","created":"$(date -u +%Y-%m-%dT%H:%M:%SZ)"}
EOF

# ... rest of initialization ...

# Fix ownership
chown -R agent:agent /workspace 2>/dev/null || true
INNER_EOF

    # Execute the inner script with variable substitution
    AGENT_ID="$agent_id" NAME="$name" MODEL="$model" docker run --rm -v "$vol:/workspace" alpine sh "$tmp_script"
    rm -f "$tmp_script"
    
    log "Created agent: $agent_id (volume: hemlock-agent-$agent_id)"
}
```

## Why This Works

| Approach | Works? | Reason |
|----------|--------|--------|
| Nested heredocs in `docker run -c` | ❌ | Outer shell consumes inner `EOF` |
| Temp file with `'INNER_EOF'` | ✅ | Single-quoted heredoc doesn't expand |
| Environment variable passing | ✅ | `AGENT_ID="$agent_id" NAME="$name" docker run ...` |

## Key Principles

1. **Outer heredoc uses quoted delimiter** (`'INNER_EOF'`) — prevents expansion
2. **Inner script uses double-quoted variables** (`$AGENT_ID`) — expanded at execution time
3. **Environment variables passed explicitly** — `AGENT_ID="$agent_id" docker run ...`
4. **Temp file cleanup** — `rm -f "$tmp_script"` after execution

## When to Use This Pattern

✅ **Use when:**
- `docker run` with complex multi-line scripts
- Multiple heredocs needed in inner script
- Variable substitution needed from outer scope

❌ **Don't need when:**
- Simple one-liner commands
- No heredocs in inner command
- Can use jq/python for JSON generation instead

## Related Patterns

### Crew JSON with jq (avoid heredoc)
```bash
agents_json=$(printf '%s\n' "${agents[@]}" | jq -R . | jq -s .)
jq -n --arg name "$crew_name" --arg channel "crew-$crew_name" --arg agents "$agents_json" \
    '{name: $name, channel: $channel, agents: ($agents | fromjson), created: "'$(date -u +%Y-%m-%dT%H:%M:%SZ)'", status: "inactive"}' \
    > /workspace/crew.json
```

### Gateway Config with jq (no heredoc)
```bash
jq --arg id "$agent_id" --arg ws "$workspace" \
    '.agents.list += [{"id": $id, "workspace": $ws}] | 
     .mcp.servers[$id] = {"command": "python3", "args": ["-m", "mcp_bridge"], "env": {"AGENT_ID": $id, "HERMES_HOME": $ws}}' \
    "$GATEWAY_CONFIG" > "$tmp" && mv "$tmp" "$GATEWAY_CONFIG"
```

## Anti-Patterns to Avoid

| Anti-Pattern | Why It Fails |
|--------------|--------------|
| `docker run ... bash -c "cat <<EOF ... EOF"` | Outer bash parses inner `EOF` |
| `docker run ... bash -c "cat <<'EOF' ... EOF"` | Still parsed by outer bash |
| `docker run ... bash -c 'cat <<EOF ... EOF'` | Single quotes prevent expansion |