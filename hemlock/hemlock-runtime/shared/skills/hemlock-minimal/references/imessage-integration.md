# iMessage Integration for Non-Mac Hosts

## Overview

Hemlock Minimal supports iMessage on Linux containers via SSH tunnel to a Mac host running `imsg` (OpenClaw's native iMessage CLI). This is the **only supported iMessage method** — BlueBubbles is deprecated/removed.

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                    HEMLOCK CONTAINER (Linux)                    │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │                    OPENCLAW GATEWAY                      │   │
│  │  channels.imessage.cliPath = "/workspace/scripts/imsg-ssh"│   │
│  │  channels.imessage.remoteHost = "user@mac-host"         │   │
│  └──────────────────────────────┬──────────────────────────┘   │
│                                 │ stdio (JSON-RPC)              │
└─────────────────────────────────┼────────────────────────────────┘
                                  │
                    ┌─────────────┘
                    ▼
           ┌─────────────────┐
           │     Mac Host    │
           │  (Messages.app) │
           │   imsg rpc      │
           └─────────────────┘
```

## Mac Host Setup (Required)

```bash
# On Mac host:
brew install steipete/tap/imsg
imsg launch
imsg rpc --help  # Verify working
```

## Mac Permissions (CRITICAL - must be granted)

| Permission | How to Grant |
|---|---|
| **Full Disk Access** | System Settings → Privacy → Full Disk Access → add Terminal/SSH |
| **Automation** | System Settings → Privacy → Automation → allow Messages.app control |

**Without these, imsg will fail silently or with permission errors.**

## Container → Mac SSH Configuration

```bash
# In container entrypoint/gateway config:
mkdir -p /workspace/scripts
cat > /workspace/scripts/imsg-ssh <<'EOF'
#!/usr/bin/env bash
# CRITICAL: Transparent stdio pipe - NO BUFFERING!
# Must forward args, preserve newlines, no grep/buffer/cat
exec ssh -T "$IMRSG_REMOTE_HOST" imsg "$@"
EOF
chmod +x /workspace/scripts/imsg-ssh
```

## Gateway Config (`openclaw.json`)

```json
{
  "channels": {
    "imessage": {
      "enabled": true,
      "cliPath": "/workspace/scripts/imsg-ssh",
      "remoteHost": "user@mac-host.local",
      "includeAttachments": true,
      "attachmentRoots": ["/Users/*/Library/Messages/Attachments"],
      "remoteAttachmentRoots": ["/Users/*/Library/Messages/Attachments"]
    }
  }
}
```

## Environment

```bash
export IMRSG_REMOTE_HOST="user@mac-host.local"
```

## Critical: Stdio Transparency Requirements

The SSH wrapper **MUST** be a transparent stdio pipe for long-lived JSON-RPC:

| ✅ Correct | ❌ Wrong |
|---|---|
| `exec ssh -T host imsg "$@"` | `ssh host imsg \| grep -v DEBUG` |
| `exec ssh -T host imsg "$@"` | `ssh host cat \| buffer` |
| | `ssh host read(4096)` |

**If using filtering, MUST use `stdbuf -oL -eL` on every stage.**

## Pairing

```bash
# DM policy defaults to pairing
docker exec hemlock-runtime openclaw pairing list imessage
docker exec hemlock-runtime openclaw pairing approve imessage <CODE>
# Pairing codes expire after 1 hour
```

## Binding

```json
{
  "bindings": [{
    "match": { "channel": "imessage", "accountId": "default" },
    "agentId": "your-agent-id"
  }]
}
```

## Troubleshooting

| Issue | Solution |
|---|---|
| `docker: command not found` | Install `docker.io` in Dockerfile |
| `ssh: connection refused` | Verify SSH keys, `ssh -T user@mac imsg rpc --help` |
| `imsg not found` | Verify `brew install steipete/tap/imsg` on Mac |
| `permission denied` | Grant Full Disk Access + Automation on Mac |
| `Config invalid: gateway.token` | Use `mode: "local"`, token in file |
| `gateway.bind legacy` | Remove `bind` key from config |

## SSH Keys

```bash
# On container host
ssh-keygen -t ed25519
ssh-copy-id user@mac-host.local

# In container
mkdir -p /home/agent/.ssh
touch /home/agent/.ssh/known_hosts
ssh-keyscan mac-host.local >> /home/agent/.ssh/known_hosts
chown -R agent:agent /home/agent/.ssh
```

## Entrypoint Integration

The gateway startup creates the wrapper automatically:

```bash
start_gateway() {
    # ...
    if [[ -n "${IMRSG_REMOTE_HOST:-}" ]]; then
        mkdir -p /workspace/scripts
        cat > /workspace/scripts/imsg-ssh <<'EOF'
#!/usr/bin/env bash
exec ssh -T "$IMRSG_REMOTE_HOST" imsg "$@"
EOF
        chmod +x /workspace/scripts/imsg-ssh
        # SSH known_hosts
        mkdir -p /home/agent/.ssh
        touch /home/agent/.ssh/known_hosts
        chown -R agent:agent /home/agent/.ssh
    fi
    # ...
}
```