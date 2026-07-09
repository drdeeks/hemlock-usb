---
name: tool-enforcement
description: 'Enforces workspace structure, tool availability, and safe tool usage for
  agents. Ships a runtime plugin (pre_llm_call guidance injection + pre_tool_call
  violation logging) plus audit scripts. Use when: validating an agent workspace has
  the required tool kit, auditing file permissions, investigating path violations,
  wiring the plugin into agent creation/import, or enforcing the restrictive-chmod
  prohibition.'
version: 1.1.1
license: MIT
metadata:
  category: devops
  author: openclaw
  tags:
  - tool enforcement
  - workspace structure validation
  - required tool kit
  - permission audit
  - restrictive chmod prohibition
  - path violation logging
  - agent guidance injection
---

# Tool Enforcement

Workspace and tool-usage enforcement for agents: a runtime plugin that injects
guidance on every model call and logs violations on every tool call, plus
standalone audit scripts.

## What It Enforces

1. **Required tool kit** — every agent carries `enforce.sh`, `secret.sh`,
   `memory-log.sh`, `memory-promote.sh`, `TOOLS-GUIDE.md` under `tools/`.
   See [references/required-tools.md](references/required-tools.md).
2. **Permission rules** — `755` scripts, `644` docs, restrictive modes ONLY
   inside `.secrets/` (`700` dir, `600` files). Violations are reported to
   the owner, never auto-fixed.
   See [references/chmod-doctrine.md](references/chmod-doctrine.md).
3. **Workspace paths** — all writes inside the agent home; no `agent-<name>`
   sibling dirs; no valuable files in `/tmp/`.
   See [references/path-enforcement.md](references/path-enforcement.md).
4. **Tool selection** — the right tool for each job (`write_file` not
   heredocs, `patch` not shell rewrites, `terminal` only for git/build/install).
   See [references/tool-selection-rules.md](references/tool-selection-rules.md).

## The Plugin

`__init__.py` implements two hooks; the manifest template lives at
`references/templates/plugin.yaml`. The plugin manager injects both into
`plugins/tool-enforcement/` during agent creation/import.

| Hook | Function | Behavior |
|---|---|---|
| `pre_llm_call` | `inject_tool_guidance` | Returns the guidance string (tool rules + chmod prohibition + path rules) prepended to every model call |
| `pre_tool_call` | `log_path_violations` | Inspects `write_file`/`terminal`/`execute_code` calls, logs warnings on violations (diagnostic, non-blocking) |

Integration details: [references/plugin-hooks.md](references/plugin-hooks.md).

## Scripts

| Script | Purpose |
|---|---|
| `scripts/validate_tools.sh` | Verify required dirs + 5-tool kit in a workspace; `--fix --source <dir>` restores missing pieces |
| `scripts/check_permissions.sh` | Audit permissions against the rules — report-only by doctrine |
| `scripts/plugin_selftest.py` | Validate manifest, import the module, exercise both hooks |

```bash
# Validate an agent workspace
bash scripts/validate_tools.sh --workspace "$HEMLOCK_HOME"

# Restore missing tools from a known-good kit
bash scripts/validate_tools.sh --workspace "$HEMLOCK_HOME" --fix --source /skills/agent-identity-architecture/references

# Audit permissions (report-only)
bash scripts/check_permissions.sh --workspace "$HEMLOCK_HOME"

# Self-test the plugin after edits
python3 scripts/plugin_selftest.py
```

## Key References

- [required-tools.md](references/required-tools.md) — the mandatory 5-tool kit + directory contract
- [chmod-doctrine.md](references/chmod-doctrine.md) — restrictive-permissions prohibition and its origin
- [path-enforcement.md](references/path-enforcement.md) — workspace path contract + violation detection
- [tool-selection-rules.md](references/tool-selection-rules.md) — right-tool-for-the-job table
- [plugin-hooks.md](references/plugin-hooks.md) — manifest, registration, hook contracts
- `references/templates/plugin.yaml` — deployable plugin manifest

## Integration

- Plugin manager: Tier 1 mandatory toolkit — injected on agent creation/import
- Agent creation and import scripts call `validate_tools.sh` post-install
- Pairs with the workspace enforcement skill (`enforce.sh` in the tool kit)
