---
name: agent-workspace-enforcement
description: Enforce standardized agent workspace structure. Smart cleanup with investigation
  before deletion. Manages directories, permissions, secrets, tools, and container
  awareness. Use when asked to enforce/check/clean workspace, fix ownership, audit
  structure, or when heartbeat triggers enforcement.
version: 5.0.1
metadata:
  hermes:
    tags:
    - agents
    - workspace
    - enforcement
    - cleanup
    - archive
    - heartbeat
    - secrets
    - tools
    category: devops
    complexity: intermediate
author: openclaw
license: MIT
---
# Agent Workspace Enforcement

## Workspace Location

Your workspace is `$HERMES_HOME` — already set. Use it directly.

- Inside containers: `/data/agents/<name>/`
- On host: `~/.openclaw/agents/<name>/`

**NEVER create `agent-<name>/` directories.** Your workspace already exists.

## Quick Start

Run enforcement:
```bash
bash scripts/enforce.sh                    # Enforce $HERMES_HOME
bash scripts/enforce.sh /path/to/workspace # Specific workspace
```

Or from heartbeat in HEARTBEAT.md:
```bash
bash scripts/enforce.sh "$HERMES_HOME"
```

## What Enforcement Does

1. Fixes ownership (root → agent)
2. Ensures required directories exist
3. Renames forbidden dirs (cache→media, memories→memory, archives→.archive)
4. Archives runtime artifacts (cron, docs, platforms, etc.)
5. Removes bloat files
6. Validates required files (SOUL.md, USER.md, AGENTS.md, agent.json, config.yaml)
7. Fixes chmod 700 violations → 755/644
8. Verifies tools/ directory standard
9. Checks SOUL.md identity

Full rules: [references/enforcement-rules.md](references/enforcement-rules.md)

## Core Rules

### Permissions

```
NEVER: chmod 700 or chmod 000 anywhere
ALWAYS: chmod 755 (dirs), chmod 644 (files)
EXCEPTION: .secrets/ encryption key may be 600
```

`chmod 700` locks the user out. Has caused catastrophic data loss.

### media/ Is Sacred

`media/` contains files the user sent to agents. Never archive, compress, or delete.

### Forbidden Directories

```
memories/ → memory/     archives/ → .archive/     cache/ → media/
cron, docs, platforms, state, sandboxes, hooks, audio_cache,
image_cache, pairing, profiles, whatsapp, checkpoints → archive then remove
```

Details: [references/enforcement-rules.md](references/enforcement-rules.md)

## Secrets Management

All secret access goes through `scripts/secret.sh`. NEVER read `.secrets/` files directly.

```bash
bash scripts/secret.sh get <name> [key]         # Read
bash scripts/secret.sh set <name> <key> <value>  # Write
bash scripts/secret.sh list                      # List
bash scripts/secret.sh has <name> [key]          # Check
bash scripts/secret.sh delete <name>             # Delete
bash scripts/secret.sh migrate                   # Plaintext → encrypted
```

Secrets are JSON. Use dot notation for nested keys: `telegram.bot.token`

Full reference: [references/secrets-standard.md](references/secrets-standard.md)

## Tools Directory Standard

Every agent MUST have in `tools/`:
- `auth-login.sh` — provider & model selection
- `secret.sh` — encrypted secret management
- `TOOLS-GUIDE.md` — reference documentation

### auth-login.sh Critical Rules

```
CORRECT: hermes model          (interactive provider + model + OAuth)
WRONG:   hermes login          (OAuth only, no model selection)
WRONG:   python3 -m hermes_cli (implementation detail, don't use)
```

From host terminal: `docker exec -it <container> hermes model` (the `-it` flags are mandatory)

Full reference: [references/tools-standard.md](references/tools-standard.md)

## Container Awareness

- Containers run as `agent` (uid 1000), NOT root
- Plugin mount: `/home/agent/.hermes/plugins/` (read-only)
- `$HERMES_HOME` = `/data/agents/<name>/`
- Host: `~/.openclaw/agents/<name>/` (bind-mounted)

## Heartbeat Integration

In HEARTBEAT.md:
```bash
bash scripts/enforce.sh "$HERMES_HOME"
```

Or run all agents from host:
```bash
for agent in aton titan allman; do
    docker exec oc-$agent bash scripts/enforce.sh "$HERMES_HOME"
done
```

## Autonomy Protocol

1. **Scripts over descriptions** — enforcement is deterministic code
2. **State in files** — rules live in this skill, not in memory
3. **Third repetition → tool** — if cleaning manually 3x, add to the script
4. **Fail loudly** — report findings, never silent cleanup
5. **Fresh context** — spawn subagent for complex multi-agent enforcement

## Skill Distribution

### Canonical Location

**`~/.openclaw/agents/.skills/`** — this is the ONLY source of truth. NOT `~/.hermes/skills/`.

Never sync, copy, or write skills to `~/.hermes/skills/`. That directory is secondary/legacy.

### Distributing to Agents

Each agent has its own copy at `~/.openclaw/agents/<name>/skills/`. Sync from canonical:

```bash
# Full sync (all skills)
rsync -av ~/.openclaw/agents/.skills/ ~/.openclaw/agents/aton/skills/
rsync -av ~/.openclaw/agents/.skills/ ~/.openclaw/agents/titan/skills/
rsync -av ~/.openclaw/agents/.skills/ ~/.openclaw/agents/allman/skills/

# Single skill (e.g. after updating one)
for agent in aton titan allman; do
    rsync -av ~/.openclaw/agents/.skills/my-skill/ ~/.openclaw/agents/$agent/skills/my-skill/
done
```

### Installing from URL

```bash
# 1. Fetch SKILL.md
curl -fsSL "https://example.com/skill/SKILL.md" > /tmp/skill-SKILL.md

# 2. Install to canonical
mkdir -p ~/.openclaw/agents/.skills/my-skill
cp /tmp/skill-SKILL.md ~/.openclaw/agents/.skills/my-skill/SKILL.md

# 3. Distribute
for agent in aton titan allman; do
    rsync -av ~/.openclaw/agents/.skills/my-skill/ ~/.openclaw/agents/$agent/skills/my-skill/
done
```

### Verifying Distribution

```bash
# Count should match
echo ".skills/: $(ls -d ~/.openclaw/agents/.skills/*/ | wc -l)"
for agent in aton titan allman; do
    echo "$agent: $(ls -d ~/.openclaw/agents/$agent/skills/*/ | wc -l)"
done

# Or use skill-scanner
export SHARED_SKILLS_DIR="$HOME/.openclaw/agents/.skills"
bash ~/.openclaw/agents/.scripts/agent-toolkit/skill-scanner.sh --openclaw scan
```

### Pitfalls

- **NEVER write to `~/.hermes/skills/`** — canonical is `~/.openclaw/agents/.skills/` only
- Use `rsync -av` (not `cp -r`) — rsync handles deletions/renames correctly
- Use `rsync --delete` for full sync to remove skills no longer in canonical
- `chmod 755` dirs, `chmod 644` files — never 700

## enforce.sh Pitfall: rmdir vs rm -rf

`rmdir` only removes truly empty directories. Runtime artifacts like `platforms/` and `sandboxes/` often have empty subdirectories (no files, but not empty). `rmdir` fails silently under `set -e`, aborting the entire script.

**Fix:** Use `rm -rf` for known runtime artifact cleanup (cron, docs, platforms, state, sandboxes, etc.) — these are safe to recursively remove since enforcement archives non-empty ones first.

```bash
# WRONG — rmdir fails on dirs with empty subdirs, set -e aborts
rmdir "$WS/$d" 2>/dev/null

# RIGHT — safe for known runtime artifact dirs
rm -rf "$WS/$d" 2>/dev/null
```

## Pitfalls

- NEVER delete files without checking if they have content
- `cache/` → `media/` (preserve received media, don't archive)
- `media/` is sacred — files the user sent to agents
- Empty dirs: `rmdir` (safe), `rm -rf` is not
- Gateway recreates `cron/`, `memories/` at runtime — expected, handle on each run
- Gateway sets chmod 700 on startup — entrypoint MUST normalize permissions before launching
- chmod 700 on workspace root blocks all enforcement (can't traverse the directory)
- Weak models create `agent-<name>/` in `/app/` — files vanish on restart
- Check ownership: `find $HERMES_HOME -maxdepth 3 -user root`
- Cross-contamination: verify SOUL.md first line references correct agent name
- Skills canonical location is `~/.openclaw/agents/.skills/` — NOT `~/.hermes/skills/`
- enforce.sh detection: always use `grep -v '^#'` to skip comments (false positives otherwise)
- `rmdir` fails on dirs with empty subdirs (e.g. `platforms/pairing/`) — use `rm -rf` for runtime artifact cleanup; `set -e` aborts the entire script on `rmdir` failure, skipping all subsequent enforcement steps

