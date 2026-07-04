# TOOLS-GUIDE.md — Agent Workspace Tools Reference

**Location:** `tools/` directory in each agent workspace
**Shared via:** `$HERMES_HOME/plugins/` mount (read-only)

---

## Table of Contents

1. [secret.sh — Encrypted Secret Management](#secretsh--encrypted-secret-management)
2. [auth-login.sh — Provider & Model Selection](#auth-loginsh--provider--model-selection)
3. [enforce.sh — Workspace Enforcement](#enforcesh--workspace-enforcement)
4. [Docker Exec Reference](#docker-exec-reference)
5. [Common Mistakes](#common-mistakes)
6. [Troubleshooting](#troubleshooting)

---

## secret.sh — Encrypted Secret Management

Stores secrets as encrypted `.json.enc` files in `$HERMES_HOME/.secrets/`.
AES-256-CBC encryption with PBKDF2 key derivation.

### Commands

```
bash tools/secret.sh get <name> [key]         Get a secret value
bash tools/secret.sh list                      List all secret names
bash tools/secret.sh set <name> <key> <value>  Set/update a secret
bash examples:
bash tools/secret.sh has <name> [key]          Check if a secret exists
bash tools/secret.sh delete <name>             Delete a secret entirely
bash tools/secret.sh init                      Re-generate encryption key
bash tools/secret.sh migrate                   Convert plaintext → encrypted
```

### Examples

```bash
# Read a value
bash tools/secret.sh get neynar api_key

# Set a value
bash tools/secret.sh set github token "ghp_abc123"

# Set nested values (dot notation)
bash tools/secret.sh set telegram bot.token "123456:ABC..."
bash tools/secret.sh set telegram bot.chat_id "-1001234"

# List all secrets
bash tools/secret.sh list

# Check existence
bash tools/secret.sh has neynar
bash tools/secret.sh has neynar api_key

# Delete
bash tools/secret.sh delete old_secret
```

### File Structure

```
.secrets/
  .secret-key              Encryption key (auto-generated, do NOT touch)
  .neynar.json.enc         Encrypted secret file
  .github.json.enc         Encrypted secret file
  .telegram.json.enc       Encrypted secret file
```

### Rules

- **ALWAYS** use this script to read/write secrets. NEVER read `.secrets/` files directly.
- **NEVER** use `chmod 700` on anything. Use `755` (dirs) or `644` (files).
- Secrets are stored as JSON objects. Use dot notation for nested keys.
- The `.secret-key` file is auto-generated. Back it up separately.

---

## auth-login.sh — Provider & Model Selection

### THE CORRECT COMMAND IS `hermes model` — NOT `hermes login`

```
hermes model  = Select provider + default model + OAuth login  ← USE THIS
hermes login  = OAuth only (no model selection)                ← Different thing
```

### From Host Terminal (Interactive)

You MUST use `-it` flags with `docker exec`. Without them:

```
Error: 'hermes model' requires an interactive terminal.
It cannot be run through a pipe or non-interactive subprocess.
```

**Correct:**

```bash
docker exec -it oc-titan hermes model
docker exec -it oc-aton hermes model
docker exec -it oc-allman hermes model
```

**Wrong:**

```bash
docker exec oc-titan hermes model        # Missing -it — WILL FAIL
docker exec -i oc-titan hermes model     # Missing -t — WILL FAIL
docker exec -t oc-titan hermes model     # Missing -i — WILL FAIL
```

### From Telegram or Non-Interactive Contexts

```bash
bash tools/auth-login.sh
```

This script attempts to run `hermes model --no-browser` in the background. If a TTY is required, it prints instructions for manual execution.

### What `-it` Does

- `-i` (interactive): Keeps STDIN open so you can type
- `-t` (tty): Allocates a pseudo-terminal for the interactive UI
- Both are required for any `hermes` command with an interactive menu

---

## enforce.sh — Workspace Enforcement

Deterministic workspace cleanup and structure enforcement.

### Usage

```bash
bash tools/enforce.sh                    # Enforce $HERMES_HOME
bash tools/enforce.sh /path/to/workspace # Specific workspace
```

### What It Does

1. Fixes ownership (root → agent)
2. Ensures required directories exist (memory/, sessions/, skills/, projects/, media/, tools/, logs/, .secrets/, .backups/)
3. Renames forbidden dirs: cache/ → media/, memories/ → memory/, archives/ → .archive/
4. Archives runtime artifacts (cron/, docs/, platforms/, etc.) then removes them
5. Removes bloat files (.skills_prompt_snapshot.json, __pycache__, etc.)
6. Validates required files (SOUL.md, USER.md, AGENTS.md, agent.json, config.yaml)
7. Fixes chmod 700 violations → 755/644
8. Verifies tools/ has auth-login.sh, secret.sh, TOOLS-GUIDE.md
9. Checks auth-login.sh uses `hermes model` (not `hermes login`)
10. Checks SOUL.md identity matches agent name
11. Removes empty .md stubs
12. Rotates logs (gzip after 1 day, delete after 30 days)
13. Archives old projects (>30 days)

### Heartbeat Usage

In HEARTBEAT.md:
```bash
bash tools/enforce.sh "$HERMES_HOME"
```

### Rules

- `media/` is sacred — never archive or delete
- `chmod 700` is NEVER allowed — use 755/644
- Empty dirs: `rmdir` (safe), not `rm -rf`
- Report findings loudly — silent cleanup loses data

---

## Docker Exec Reference

### Running Commands Inside Agent Containers

```bash
# Interactive (for hermes model, hermes chat, etc.)
docker exec -it <container> <command>

# Non-interactive (for scripts, one-shot commands)
docker exec <container> <command>

# Run a script from the agent workspace
docker exec -it oc-titan bash tools/auth-login.sh

# Check hermes status
docker exec oc-titan hermes status

# Read a secret
docker exec oc-aton bash tools/secret.sh get neynar api_key
```

### Container Names

| Container | Agent | Workspace |
|-----------|-------|-----------|
| `oc-titan` | Titan | `/data/agents/titan/` |
| `oc-aton` | Aton | `/data/agents/aton/` |
| `oc-allman` | Allman | `/data/agents/allman/` |

### Host Paths (bind-mounted into containers)

```
~/.openclaw/agents/<name>/  →  /data/agents/<name>/
~/.hermes/plugins/          →  /data/agents/<name>/plugins/ (shared, read-only)
```

---

## Common Mistakes

### 1. Missing `-it` on docker exec

```
WRONG: docker exec oc-titan hermes model
RIGHT: docker exec -it oc-titan hermes model
```

### 2. Using `hermes login` instead of `hermes model`

```
WRONG: hermes login --provider nous
RIGHT: hermes model
```

`hermes model` gives you an interactive menu to pick provider AND model.
`hermes login` only does OAuth for a specific provider (no model selection).

### 3. Calling `python3 -m hermes_cli.main` directly

```
WRONG: python3 -m hermes_cli.main login --provider nous --no-browser
RIGHT: hermes model --no-browser
RIGHT: hermes model  (interactive)
```

The `hermes` command is the proper entry point. The python module path is an implementation detail that may change.

### 4. Using `chmod 700` anywhere

```
WRONG: chmod 700 .secrets/
WRONG: chmod 700 .secret-key
RIGHT: chmod 644 files
RIGHT: chmod 755 directories
```

`chmod 700` locks the user out of their own files and has caused catastrophic data loss. NEVER use it.

### 5. Reading .secrets/ files directly

```
WRONG: cat .secrets/.neynar.json.enc
RIGHT: bash tools/secret.sh get neynar api_key
```

Secret files are encrypted. Use the script.

---

## Troubleshooting

### "Error: 'hermes model' requires an interactive terminal"

**Cause:** Running `hermes model` without a TTY.
**Fix:** Add `-it` to `docker exec`, or run `bash tools/auth-login.sh` from a script.

### "Error: 'hermes login' requires an interactive terminal"

**Cause:** Same TTY issue, but you probably want `hermes model` anyway.
**Fix:** Use `docker exec -it <container> hermes model` instead.

### "Secret 'X' not found"

**Cause:** Secret doesn't exist, or you're in the wrong container.
**Fix:**
```bash
bash tools/secret.sh list    # See what's available
bash tools/secret.sh has X   # Check specific secret
```

### Auth URL not appearing

**Cause:** Network issue, or the auth service is down.
**Fix:**
```bash
hermes doctor                # Check configuration
hermes status                # Check component status
```

### Container can't access secrets

**Cause:** `$HERMES_HOME` not set, or `.secrets/` directory missing.
**Fix:**
```bash
echo $HERMES_HOME            # Should be /data/agents/<name>
ls -la $HERMES_HOME/.secrets/  # Should exist
bash tools/secret.sh init    # Re-generate key if needed
```

---

## Quick Reference Card

```
SELECT PROVIDER + MODEL:    docker exec -it oc-titan hermes model
CHECK STATUS:               docker exec oc-titan hermes status
GET A SECRET:               docker exec oc-aton bash tools/secret.sh get neynar api_key
SET A SECRET:               docker exec oc-aton bash tools/secret.sh set github token "ghp_xxx"
LIST SECRETS:               docker exec oc-allman bash tools/secret.sh list
RUN AUTH SCRIPT:            bash tools/auth-login.sh
DOCTOR CHECK:               docker exec oc-titan hermes doctor
```

---

*Last updated: 2026-04-21*
*All agents must follow this guide. When in doubt, check this file first.*
