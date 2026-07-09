# Restrictive-Permissions Doctrine

The single most important rule this plugin enforces, born from real data loss.

## The rule

- NEVER `chmod 700`, `chmod 000`, or any restrictive mode outside `.secrets/`.
- `chmod 755` (executables) and `chmod 644` (docs/data) are the only modes
  agents may apply.
- `.secrets/` is the sole exception: `700` on the directory, `600` on files.

## Why it exists

A recursive restrictive chmod locked the owner out of their own files and
caused catastrophic data loss. Recovery cost far exceeded any security
benefit. The failure mode is silent: the agent "hardens" permissions, the
owner discovers it days later when nothing opens.

## Enforcement behavior

- `pre_llm_call` hook injects the prohibition into every model call, so the
  guidance survives context compaction.
- `pre_tool_call` hook flags `chmod 700`/`chmod 000` in terminal commands —
  diagnostic logging; it cannot block.
- `scripts/check_permissions.sh` audits a workspace and REPORTS findings.
  It never auto-fixes: if a file has wrong permissions, tell the owner and
  let them decide. An agent "fixing" permissions is how the incident
  happened in the first place.

## Related prohibitions carried by the same guidance block

- Never `rm -rf` user directories.
- Never run chmod recursively on broad paths.
