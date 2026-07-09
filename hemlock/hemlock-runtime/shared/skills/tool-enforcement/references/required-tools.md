# Required Agent Tool Kit

Every agent workspace ships a mandatory 5-piece tool kit under `tools/`.
`scripts/validate_tools.sh` verifies presence and executability; `--fix
--source <dir>` restores missing pieces from a known-good tools directory.

| Tool | Purpose | Expected perms |
|---|---|---|
| `enforce.sh` | Workspace structure enforcement — validates and repairs the directory contract | 755 |
| `secret.sh` | Encrypted secret management — secrets are encrypted JSON, never viewed or piped plain | 755 |
| `memory-log.sh` | Daily memory logging — appends to the day file | 755 |
| `memory-promote.sh` | Promotes daily memory into long-term memory | 755 |
| `TOOLS-GUIDE.md` | Usage documentation for the kit | 644 |

## Required directories

- `tools/` — the kit itself
- `skills/` — installed skills
- `memory/` — daily + long-term memory
- `.secrets/` — encrypted secrets, `700` on the directory, `600` on files
  (the ONLY place restrictive permissions belong)

## Injection

The plugin is injected automatically during agent creation/import (Tier 1
mandatory toolkit). Validation should still run after import — imports from
older workspaces may predate the kit.
