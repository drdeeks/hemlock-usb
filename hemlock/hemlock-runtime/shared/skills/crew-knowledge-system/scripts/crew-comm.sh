#!/usr/bin/env bash
# crew-comm.sh - Agent communication protocol
set -euo pipefail

show_help() {
    cat <<'EOF'
Crew Communication - Structured agent-to-agent messaging

Usage: bash crew-comm.sh <command> [options]

Commands:
  send                  Send message to another agent
  reply                 Reply to existing thread
  broadcast             Broadcast to all agents
  thread                View message thread
  list                  List messages/threads
  sync                  Sync communications to shared index

Options:
  --from <id>           Sender agent ID (required for send/reply/broadcast)
  --to <id>             Recipient agent ID (required for send)
  --thread <id>         Thread ID (required for reply/thread)
  --subject <text>      Message subject (required for send/broadcast)
  --body <text>         Message body (required for send/reply/broadcast)
  --type <type>         Message type: sync|question|proposal|decision|broadcast|alert (default: sync)
  --priority <prio>     Priority: low|normal|high|urgent (default: normal)
  --tags <tags>         Comma-separated tags
  --crew-id <id>        Crew ID (default: auto-detect)
  --workspace <path>    Crew workspace (default: auto-detect)
  --help                Show this help

Example:
  bash crew-comm.sh send --from ui-a1b2 --to integration-b2c3 --subject "API contract" --body "Need to align..."
  bash crew-comm.sh reply --thread comm-7f9a2b1c --from integration-b2c3 --body "Proposing..."
  bash crew-comm.sh broadcast --from lead-x1y2 --subject "Phase gate" --body "All agents confirm..."
  bash crew-comm.sh thread comm-7f9a2b1c
  bash crew-comm.sh list --agent ui-a1b2
EOF
    exit 0
}

# Auto-detect crew workspace
detect_crew_workspace() {
    local dir="$(pwd)"
    while [[ "$dir" != "/" ]]; do
        if [[ -f "$dir/crew.json" ]]; then
            echo "$dir"
            return 0
        fi
        dir="$(dirname "$dir")"
    done
    return 1
}

# Handle --help before any workspace detection
if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
    show_help
fi

CREW_WORKSPACE="${CREW_WORKSPACE:-}"
if [[ -z "$CREW_WORKSPACE" ]]; then
    CREW_WORKSPACE="$(detect_crew_workspace)" || {
        echo "ERROR: Not in a crew workspace"
        exit 1
    }
fi

CREW_ID="$(jq -r .crew_id "$CREW_WORKSPACE/crew.json" 2>/dev/null || echo "unknown")"
COMM_DIR="$CREW_WORKSPACE/shared/communications"
MESSAGES_DIR="$COMM_DIR/messages"
THREADS_DIR="$COMM_DIR/threads"
BROADCASTS_DIR="$COMM_DIR/broadcasts"

mkdir -p "$MESSAGES_DIR" "$THREADS_DIR" "$BROADCASTS_DIR"

COMMAND="${1:-}"
shift || true

# Parse common options
FROM_AGENT=""
TO_AGENT=""
THREAD_ID=""
SUBJECT=""
BODY=""
MSG_TYPE="sync"
PRIORITY="normal"
TAGS=""

while [[ $# -gt 0 ]]; do
    case $1 in
        --help|-h) show_help ;;
        --from) FROM_AGENT="$2"; shift 2 ;;
        --to) TO_AGENT="$2"; shift 2 ;;
        --thread) THREAD_ID="$2"; shift 2 ;;
        --subject) SUBJECT="$2"; shift 2 ;;
        --body) BODY="$2"; shift 2 ;;
        --type) MSG_TYPE="$2"; shift 2 ;;
        --priority) PRIORITY="$2"; shift 2 ;;
        --tags) TAGS="$2"; shift 2 ;;
        --crew-id) CREW_ID="$2"; shift 2 ;;
        --workspace) CREW_WORKSPACE="$2"; shift 2 ;;
        *) break ;;
    esac
done

# Validate message type
VALID_TYPES="sync question proposal decision broadcast alert"
if ! echo "$VALID_TYPES" | grep -qw "$MSG_TYPE"; then
    echo "ERROR: Invalid message type. Valid: $VALID_TYPES"
    exit 1
fi

# Validate priority
VALID_PRIOS="low normal high urgent"
if ! echo "$VALID_PRIOS" | grep -qw "$PRIORITY"; then
    echo "ERROR: Invalid priority. Valid: $VALID_PRIOS"
    exit 1
fi

case "$COMMAND" in
    send)
        [[ -z "$FROM_AGENT" ]] && { echo "ERROR: --from required"; exit 1; }
        [[ -z "$TO_AGENT" ]] && { echo "ERROR: --to required"; exit 1; }
        [[ -z "$SUBJECT" ]] && { echo "ERROR: --subject required"; exit 1; }
        [[ -z "$BODY" ]] && { echo "ERROR: --body required"; exit 1; }
        
        send_message
        ;;
        
    reply)
        [[ -z "$FROM_AGENT" ]] && { echo "ERROR: --from required"; exit 1; }
        [[ -z "$THREAD_ID" ]] && { echo "ERROR: --thread required"; exit 1; }
        [[ -z "$BODY" ]] && { echo "ERROR: --body required"; exit 1; }
        
        reply_to_thread
        ;;
        
    broadcast)
        [[ -z "$FROM_AGENT" ]] && { echo "ERROR: --from required"; exit 1; }
        [[ -z "$SUBJECT" ]] && { echo "ERROR: --subject required"; exit 1; }
        [[ -z "$BODY" ]] && { echo "ERROR: --body required"; exit 1; }
        
        broadcast_message
        ;;
        
    thread)
        [[ -z "$THREAD_ID" ]] && { echo "ERROR: --thread required"; exit 1; }
        
        view_thread
        ;;
        
    list)
        list_messages
        ;;
        
    sync)
        sync_communications
        ;;
        
    *)
        echo "ERROR: Unknown command: $COMMAND"
        show_help
        ;;
esac

# ============================================================================
# Internal Functions
# ============================================================================

send_message() {
    local msg_id="comm-$(openssl rand -hex 8 2>/dev/null || cat /dev/urandom | tr -dc 'a-f0-9' | head -c 16)"
    local thread_id="thread-$(openssl rand -hex 8 2>/dev/null || cat /dev/urandom | tr -dc 'a-f0-9' | head -c 16)"
    local timestamp="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    
    # Get sender agent type
    local from_type=$(get_agent_type "$FROM_AGENT")
    local to_type=$(get_agent_type "$TO_AGENT")
    
    # Create message file
    local msg_file="$MESSAGES_DIR/${msg_id}.md"
    cat > "$msg_file" <<MSG
---
message_id: "$msg_id"
thread_id: "$thread_id"
from_agent: "$FROM_AGENT"
from_type: "$from_type"
to_agent: "$TO_AGENT"
to_type: "$to_type"
crew_id: "$CREW_ID"
type: "$MSG_TYPE"
subject: "$SUBJECT"
priority: "$PRIORITY"
timestamp: "$timestamp"
tags: "$TAGS"
---

## Message

$BODY

## Context
- From: $FROM_AGENT ($from_type)
- To: $TO_AGENT ($to_type)
- Type: $MSG_TYPE
- Priority: $PRIORITY
MSG
    
    # Create/update thread
    local thread_file="$THREADS_DIR/${thread_id}.md"
    if [[ ! -f "$thread_file" ]]; then
        cat > "$thread_file" <<THREAD
---
thread_id: "$thread_id"
crew_id: "$CREW_ID"
created_utc: "$timestamp"
subject: "$SUBJECT"
participants: ["$FROM_AGENT", "$TO_AGENT"]
message_count: 1
last_activity: "$timestamp"
---

## Thread: $SUBJECT

### Message 1: $FROM_AGENT → $TO_AGENT ($timestamp)

$BODY

---
THREAD
    else
        # Append to existing thread
        local msg_count=$(grep -c "^### Message" "$thread_file" 2>/dev/null || echo 0)
        msg_count=$((msg_count + 1))
        
        # Update thread metadata
        sed -i "s/message_count: [0-9]*/message_count: $msg_count/" "$thread_file"
        sed -i "s/last_activity: .*/last_activity: \"$timestamp\"/" "$thread_file"
        
        # Add participant if new
        if ! grep -q "\"$FROM_AGENT\"" "$thread_file"; then
            sed -i "s/participants: \[/participants: [\"$FROM_AGENT\", /" "$thread_file"
        fi
        if ! grep -q "\"$TO_AGENT\"" "$thread_file"; then
            sed -i "s/participants: \[/participants: [\"$TO_AGENT\", /" "$thread_file"
        fi
        
        cat >> "$thread_file" <<THREAD

### Message $msg_count: $FROM_AGENT → $TO_AGENT ($timestamp)

$BODY

---
THREAD
    fi
    
    echo "✅ Message sent: $msg_id"
    echo "  Thread: $thread_id"
    echo "  From: $FROM_AGENT → To: $TO_AGENT"
    echo "  Subject: $SUBJECT"
}

reply_to_thread() {
    local timestamp="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    local from_type=$(get_agent_type "$FROM_AGENT")
    
    local thread_file="$THREADS_DIR/${THREAD_ID}.md"
    [[ -f "$thread_file" ]] || { echo "ERROR: Thread not found: $THREAD_ID"; exit 1; }
    
    local msg_id="comm-$(openssl rand -hex 8 2>/dev/null || cat /dev/urandom | tr -dc 'a-f0-9' | head -c 16)"
    local msg_file="$MESSAGES_DIR/${msg_id}.md"
    
    # Get thread subject and participants
    local thread_subject=$(grep "^subject:" "$thread_file" | cut -d'"' -f2)
    local participants=$(grep "participants:" "$thread_file" | sed 's/.*\[\(.*\)\].*/\1/')
    
    # Determine recipient (first participant that isn't sender)
    local to_agent=""
    for p in $(echo "$participants" | tr ',' ' '); do
        p=$(echo "$p" | tr -d '"' | xargs)
        if [[ "$p" != "$FROM_AGENT" ]]; then
            to_agent="$p"
            break
        fi
    done
    
    local to_type=$(get_agent_type "$to_agent")
    
    # Create reply message
    cat > "$msg_file" <<MSG
---
message_id: "$msg_id"
thread_id: "$THREAD_ID"
from_agent: "$FROM_AGENT"
from_type: "$from_type"
to_agent: "$to_agent"
to_type: "$to_type"
crew_id: "$CREW_ID"
type: "reply"
subject: "Re: $thread_subject"
priority: "$PRIORITY"
timestamp: "$timestamp"
tags: "$TAGS"
---

## Reply

$BODY

## Context
- Thread: $THREAD_ID
- In reply to: $thread_subject
- From: $FROM_AGENT ($from_type)
- To: $to_agent ($to_type)
MSG
    
    # Append to thread
    local msg_count=$(grep -c "^### Message" "$thread_file" 2>/dev/null || echo 0)
    msg_count=$((msg_count + 1))
    
    sed -i "s/message_count: [0-9]*/message_count: $msg_count/" "$thread_file"
    sed -i "s/last_activity: .*/last_activity: \"$timestamp\"/" "$thread_file"
    
    cat >> "$thread_file" <<THREAD

### Message $msg_count: $FROM_AGENT → $to_agent ($timestamp)

$BODY

---
THREAD
    
    echo "✅ Reply sent: $msg_id"
    echo "  Thread: $THREAD_ID"
    echo "  From: $FROM_AGENT → To: $to_agent"
}

broadcast_message() {
    local msg_id="broadcast-$(openssl rand -hex 8 2>/dev/null || cat /dev/urandom | tr -dc 'a-f0-9' | head -c 16)"
    local timestamp="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    local from_type=$(get_agent_type "$FROM_AGENT")
    
    # Create broadcast file
    local broadcast_file="$BROADCASTS_DIR/${msg_id}.md"
    cat > "$broadcast_file" <<BROADCAST
---
broadcast_id: "$msg_id"
from_agent: "$FROM_AGENT"
from_type: "$from_type"
crew_id: "$CREW_ID"
subject: "$SUBJECT"
priority: "$PRIORITY"
timestamp: "$timestamp"
tags: "$TAGS"
---

## Broadcast

$BODY

## Context
- From: $FROM_AGENT ($from_type)
- Type: broadcast
- Priority: $PRIORITY
- Audience: All crew agents
BROADCAST
    
    # Also create individual messages for each agent (for tracking)
    for agent_dir in "$CREW_WORKSPACE/agents"/*/; do
        [[ -d "$agent_dir" ]] || continue
        local agent_id=$(basename "$agent_dir")
        if [[ "$agent_id" != "$FROM_AGENT" ]]; then
            local individual_id="comm-$(openssl rand -hex 8 2>/dev/null || cat /dev/urandom | tr -dc 'a-f0-9' | head -c 16)"
            local individual_file="$MESSAGES_DIR/${individual_id}.md"
            
            {
                echo "---"
                echo "message_id: \"$individual_id\""
                echo "thread_id: \"$msg_id\""
                echo "from_agent: \"$FROM_AGENT\""
                echo "from_type: \"$from_type\""
                echo "to_agent: \"$agent_id\""
                echo "to_type: \"$(get_agent_type \"$agent_id\")\""
                echo "crew_id: \"$CREW_ID\""
                echo "type: \"broadcast\""
                echo "subject: \"$SUBJECT\""
                echo "priority: \"$PRIORITY\""
                echo "timestamp: \"$timestamp\""
                echo "tags: \"$TAGS\""
                echo "---"
                echo ""
                echo "## Broadcast Message"
                echo ""
                echo "$BODY"
                echo ""
                echo "## Context"
                echo "- From: $FROM_AGENT ($from_type)"
                echo "- To: $agent_id"
                echo "- Type: broadcast"
                echo "- Priority: $PRIORITY"
            } > "$individual_file"
        fi
    done
    
    echo "✅ Broadcast sent: $msg_id"
    echo "  From: $FROM_AGENT"
    echo "  Subject: $SUBJECT"
    echo "  Delivered to $(ls "$CREW_WORKSPACE/agents" | wc -l) agents"
}

view_thread() {
    local thread_file="$THREADS_DIR/${THREAD_ID}.md"
    [[ -f "$thread_file" ]] || { echo "ERROR: Thread not found: $THREAD_ID"; exit 1; }
    
    cat "$thread_file"
}

list_messages() {
    echo "=== Messages for Crew: $CREW_ID ==="
    echo ""
    echo "--- Direct Messages ---"
    for msg in "$MESSAGES_DIR"/*.md; do
        [[ -f "$msg" ]] || continue
        local from=$(grep "from_agent:" "$msg" | head -1 | cut -d'"' -f2)
        local to=$(grep "to_agent:" "$msg" | head -1 | cut -d'"' -f2)
        local subj=$(grep "subject:" "$msg" | head -1 | cut -d'"' -f2)
        local ts=$(grep "timestamp:" "$msg" | head -1 | cut -d'"' -f2)
        local type=$(grep "type:" "$msg" | head -1 | cut -d'"' -f2)
        echo "  $ts | $type | $from → $to | $subj"
    done | sort -r
    
    echo ""
    echo "--- Broadcasts ---"
    for bc in "$BROADCASTS_DIR"/*.md; do
        [[ -f "$bc" ]] || continue
        local from=$(grep "from_agent:" "$bc" | head -1 | cut -d'"' -f2)
        local subj=$(grep "subject:" "$bc" | head -1 | cut -d'"' -f2)
        local ts=$(grep "timestamp:" "$bc" | head -1 | cut -d'"' -f2)
        echo "  $ts | broadcast | $from | $subj"
    done | sort -r
    
    echo ""
    echo "--- Threads ---"
    for thread in "$THREADS_DIR"/*.md; do
        [[ -f "$thread" ]] || continue
        local tid=$(grep "thread_id:" "$thread" | head -1 | cut -d'"' -f2)
        local subj=$(grep "subject:" "$thread" | head -1 | cut -d'"' -f2)
        local count=$(grep "message_count:" "$thread" | head -1 | cut -d' ' -f2)
        local last=$(grep "last_activity:" "$thread" | head -1 | cut -d'"' -f2)
        echo "  $tid | $count msgs | $last | $subj"
    done | sort -r
}

sync_communications() {
    echo "=== Syncing Communications to Shared Index ==="
    
    # Index all messages into crew knowledge base
    local synced=0
    for msg in "$MESSAGES_DIR"/*.md; do
        [[ -f "$msg" ]] || continue
        local agent=$(grep "from_agent:" "$msg" | head -1 | cut -d'"' -f2)
        local timestamp=$(grep "timestamp:" "$msg" | head -1 | cut -d'"' -f2)
        local subject=$(grep "subject:" "$msg" | head -1 | cut -d'"' -f2)
        local type=$(grep "type:" "$msg" | head -1 | cut -d'"' -f2)
        local msg_id=$(grep "message_id:" "$msg" | head -1 | cut -d'"' -f2)
        
        # Create communication document in shared/documents/communications
        local comm_file="$CREW_WORKSPACE/shared/documents/communications/${msg_id}.md"
        cat > "$comm_file" <<COMM
---
agent_id: "$agent"
crew_id: "$CREW_ID"
doc_type: "communication"
category: "process"
timestamp: "$timestamp"
tags: "communication,$type"
---

# Communication: $subject

**Type:** $type
**From:** $agent
**Timestamp:** $timestamp
**Message ID:** $msg_id

---

$(sed -n '/^## Message$/,/^## Context$/p' "$msg" | head -n -1)
COMM
        ((synced++))
    done
    
    # Index broadcasts
    for bc in "$BROADCASTS_DIR"/*.md; do
        [[ -f "$bc" ]] || continue
        local agent=$(grep "from_agent:" "$bc" | head -1 | cut -d'"' -f2)
        local timestamp=$(grep "timestamp:" "$bc" | head -1 | cut -d'"' -f2)
        local subject=$(grep "subject:" "$bc" | head -1 | cut -d'"' -f2)
        local bc_id=$(grep "broadcast_id:" "$bc" | head -1 | cut -d'"' -f2)
        
        local comm_file="$CREW_WORKSPACE/shared/documents/communications/${bc_id}.md"
        cat > "$comm_file" <<COMM
---
agent_id: "$agent"
crew_id: "$CREW_ID"
doc_type: "communication"
category: "process"
timestamp: "$timestamp"
tags: "communication,broadcast"
---

# Broadcast: $subject

**From:** $agent
**Timestamp:** $timestamp
**Broadcast ID:** $bc_id

---

$(sed -n '/^## Broadcast$/,/^## Context$/p' "$bc" | head -n -1)
COMM
        ((synced++))
    done
    
    echo "  ✅ Synced $synced communications to shared knowledge"
    echo "  Run: bash scripts/crew-indexer.sh index to update search index"
}

get_agent_type() {
    local agent_id="$1"
    local agent_dir="$CREW_WORKSPACE/agents/$agent_id"
    
    if [[ -f "$agent_dir/agent.json" ]]; then
        jq -r .type "$agent_dir/agent.json" 2>/dev/null || echo "unknown"
    else
        # Try to infer from crew.json
        jq -r --arg aid "$agent_id" '.agent_types[] | select(. | contains($aid))' "$CREW_WORKSPACE/crew.json" 2>/dev/null | head -1 || echo "unknown"
    fi
}