# Tool Selection Rules

The guidance block injected on every model call steers agents to the right
tool for each job — misused tools are the top source of workspace damage.

## The rules

| Job | Correct tool | Never |
|---|---|---|
| Create or replace a file | `write_file` | `terminal` with heredocs/echo |
| Read a file | `read_file` | `terminal` cat |
| Edit an existing file | `patch` | rewriting via shell |
| Find content | `search_files` | `terminal` grep pipelines |
| Run Python | `execute_code` | `terminal` python3 -c |
| Git, builds, installs, package managers | `terminal` | — |

## Rationale

- Dedicated tools give the runtime structured visibility (paths, diffs,
  results) that shell one-liners hide.
- `terminal` misuse is where path violations and restrictive chmods happen;
  narrowing it to git/build/install shrinks the blast radius.
- Writes belong in workspace paths (`projects/`, `tools/`, `memory/`) —
  `/tmp/` is wiped on container restart, so anything valuable written there
  is silently lost.

## Container context

Agents run in isolated containers, so commands execute freely within the
container boundary; the enforcement concern is workspace integrity, not
host security. The guidance says so explicitly to stop agents from refusing
routine in-container operations.
