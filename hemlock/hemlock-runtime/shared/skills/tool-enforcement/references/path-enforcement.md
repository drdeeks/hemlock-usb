# Workspace Path Enforcement

Agents must write inside their own workspace — files created elsewhere are
lost on container restart.

## The contract

- The workspace root is the agent-home environment variable
  (`$HEMLOCK_HOME`, with `$HERMES_HOME` as the working legacy alias).
- All writes go under it: `memory/ sessions/ skills/ projects/ .archive/
  media/ tools/ logs/ .secrets/ .backups/`.
- Never create sibling directories named `agent-<name>` — that pattern means
  the agent is writing OUTSIDE its home with a relative path.
- Scratch belongs in workspace paths (`projects/`, `tools/`, `memory/`) —
  not `/tmp/`, which is wiped on restart.

## How the hook detects violations

`log_path_violations` (pre_tool_call) inspects tool calls:

| Tool | Signal | Response |
|---|---|---|
| `write_file` | path outside the agent home | warning logged |
| `terminal` | `mkdir` combined with `agent-` | warning logged |
| `terminal` | restrictive chmod | critical warning (see chmod doctrine) |
| `execute_code` | `agent-` path patterns with file operations | warning logged |

The hook is diagnostic — it logs and cannot block. Blocking enforcement
belongs to the gateway's tool policy layer; this plugin provides the audit
trail and the in-context guidance that prevents most violations up front.

## Why injection happens every call

Guidance injected only at session start is lost when context is compacted.
`inject_tool_guidance` runs `pre_llm_call`, so the rules ride along on every
model invocation.
