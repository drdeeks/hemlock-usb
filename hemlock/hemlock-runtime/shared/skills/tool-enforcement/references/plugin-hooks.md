# Plugin Hook Integration

How the tool-enforcement plugin wires into the runtime's plugin manager.

## Manifest

The manifest template ships at `references/templates/plugin.yaml`:

```yaml
name: tool-enforcement
version: 2.0.0
description: Tool guidance, restrictive-chmod prohibition, path enforcement, and violation logging
provides_hooks:
  - pre_llm_call
  - pre_tool_call
```

The plugin manager copies it (with `__init__.py`) into the runtime's
`plugins/tool-enforcement/` directory during agent creation/import.

## Registration

```python
def register(ctx):
    ctx.register_hook("pre_llm_call", inject_tool_guidance)
    ctx.register_hook("pre_tool_call", log_path_violations)
```

## Hook contracts

### `pre_llm_call` → `inject_tool_guidance(...) -> str`

Receives session/model/platform context; returns a guidance string the
runtime prepends to the call. This plugin returns three blocks concatenated:
tool-selection rules, the restrictive-chmod prohibition, and workspace path
rules. Pure function — no side effects, safe on every call.

### `pre_tool_call` → `log_path_violations(...) -> None`

Receives `tool_name`, `args`, and call identifiers. Inspects `write_file`
paths, `terminal` commands, and `execute_code` bodies for violations and
prints warnings to the runtime log. Diagnostic only — returning does not
block the call.

## Self-test

`python3 scripts/plugin_selftest.py` validates the manifest, imports the
module, exercises both hooks, and confirms the restrictive-chmod detection
fires. Run it after any edit to `__init__.py`.
