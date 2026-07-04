---
doc: TOOLS.md
version: 2.4.0
updated: 2026-07-03
changelog:
  - 2.4.0 (2026-07-03): Registered knowledge.sh (capture links/docs into the GLOBAL,
    append-only, runtime-root knowledge base, classified by use/function/scope).
  - 2.3.0 (2026-07-03): Registered rollback.sh (roll back via daily per-volume git snapshots).
  - 2.2.0 (2026-07-03): Switched home references to $HEMLOCK_HOME (HERMES_HOME still works
    as a legacy alias).
  - 2.1.0 (2026-07-03): Registered context-dump.sh (crash-safe context offload).
  - 2.0.0 (2026-07-03): Consolidated TOOLS-GUIDE.md into this file; added the
    tool-creation doctrine; made fully path/location-agnostic (no host paths or
    container names); documented secret.sh show (owner view).
  - 1.0.0: Initial per-agent tool table.
---

# TOOLS.md — Agent Tool Reference & Registry

**This is your living registry of every tool you have.** It starts with the standard
helpers below and **grows as you build your own** (see "Creating new tools"). When you
add a tool, add a row here so future-you can find it in seconds.

All tools live in `tools/` inside your workspace (`$HEMLOCK_HOME`). Invoke them with
relative paths (`bash tools/<name>`), never hardcoded host paths — this workspace must
stay portable across machines and containers.

## Core rules
1. **Write to files** — never overwrite memory files; daily notes are append-only.
2. **Secrets** — encrypted JSON via `secret.sh` only; never plaintext, never verbatim.
3. **Check first** — consult this file and your knowledge base before asking for help.
4. **Credentials** — check `.secrets/` before asking your owner for a key you may have.

## Standard tools

| Tool | Description |
|------|-------------|
| `enforce.sh` | Workspace structure validation, repair, and tool/doc enforcement |
| `inject-context.sh` | Consolidated context injection (identity, memory, autonomy + subagent protocol) |
| `secret.sh` | Encrypted secret management (AES-256-CBC / PBKDF2) |
| `memory-log.sh` | Append an entry to today's daily memory file |
| `memory-promote.sh` | Review daily notes and promote lessons to `MEMORY.md` |
| `context-dump.sh` | Crash-safe context offload → timestamped `sessions/dumps/` snapshot |
| `rollback.sh` | Roll back any file/dir using the daily per-volume git snapshots |
| `knowledge.sh` | Capture a link/doc into the GLOBAL append-only knowledge base (classified by use/function/scope); search it |
| `auth-login.sh` | Interactive model/provider login helper |
| `jsonfmt.py` | JSON formatting and validation utility |

## Usage

```bash
# Workspace enforcement (also runs on boot + heartbeat)
bash tools/enforce.sh "$HEMLOCK_HOME"

# Secrets — encrypted JSON, dot-notation for nested keys
bash tools/secret.sh set telegram bot.token "123456:ABC..."
bash tools/secret.sh get telegram bot.token     # one value
bash tools/secret.sh list                        # names only (agent-facing)
bash tools/secret.sh has telegram bot.token      # existence check (exit code)
bash tools/secret.sh show [name]                 # OWNER: full decrypted view/audit

# Memory — append-only daily log, weekly promotion
bash tools/memory-log.sh "Completed X"           # add -t LESSON / -t TODO to tag
bash tools/memory-promote.sh --week              # review + promote to MEMORY.md

# Knowledge — capture anything referenceable into the GLOBAL append-only store
bash tools/knowledge.sh url "https://x.dev/llms.txt" --use llm-context   # a link
bash tools/knowledge.sh file ./report.pdf --scope project:acme           # a document
bash tools/knowledge.sh text --title "notes" < notes.md                  # pasted text
bash tools/knowledge.sh search "kubernetes autoscaling"                  # find it later
bash tools/knowledge.sh status                                           # store stats
```
> Captures are stored **globally** (shared by every agent) and **append-only** — nothing
> is ever overwritten or deleted. Classify with `--use` (what it's for), `--function`
> (what it does), `--scope` (`global` | `agent:<id>` | `project:<name>`). Links your owner
> sends you through the gateway are also captured **automatically** — but tagging one by
> hand with the right classification makes it far more findable.

## Creating new tools — the doctrine
Follow the autonomy spectrum: push work as far toward deterministic code as it will go.

> **If you find yourself doing the same operation more than twice, stop and build a tool.**

1. **First time** — just do it manually.
2. **Second time** — notice the pattern.
3. **Third time (more than twice)** — package it:
   - Write a **deterministic** script (bash or python) that does the one job.
   - **Test it** on real inputs, including an edge case and a failure case.
   - **Validate it** (`bash -n script.sh` for syntax; run it; confirm it *fails loudly*,
     never silently).
   - Place it in `tools/` — it is now *your* specific helper.
   - **Register it**: add a row to the table above and a usage line here.

**Docs vs. scripts — the path rule:** informational/doc files you write (notes, `USER.md`,
references) MAY hardcode a path to explain *where something lives* — that's helpful. But any
**script or actionable deterministic tool** must stay **path-resolving**: resolve locations
from `$HEMLOCK_HOME` and relative paths, never a hardcoded `/home/...`, `/root/...`, or a
specific `/data/agents/<name>/...`. That way the tool keeps working if the workspace is moved
or dropped into another agent. `enforce.sh` warns (informative) if a tool script hardcodes a
path.

## Security rules
- **Secrets**: only ever through `secret.sh`. Never `cat` a `.secrets/*.enc` file. Never
  copy a decrypted secret into memory, logs, or daily notes — record only that you hold it.
- **Owner access**: your owner may view/manage their own secrets with `secret.sh show`;
  exports carry `.secrets/` + `.secret-key` so an exported agent stays decryptable for them.
- **Permissions**: NEVER `chmod 700`/`600` except on `.secrets/` material. Use `755`
  (directories) / `644` (files).
- **Containment**: everything you create stays inside `$HEMLOCK_HOME`.

## Troubleshooting
- Interactive commands (model/provider login) need a TTY — run them attached, or configure
  the model in `config.yaml` instead.
- `Secret 'X' not found` → `bash tools/secret.sh list` to see what exists; `has` to probe.
- Missing `.secrets/` or key → `bash tools/secret.sh init` regenerates the encryption key
  (back it up separately — without it, secrets cannot be decrypted).
