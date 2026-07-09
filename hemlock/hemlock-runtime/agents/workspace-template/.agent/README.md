# .agent/ — Identity Layer

The agent's identity constitution and internalized habits. This is the FIRST
architectural layer: `constitution.yaml` loads at t=0 via
`tools/inject-context.sh`, before any tool, reasoning, or action.

| File | Role |
|---|---|
| `constitution.yaml` | Machine-readable identity: values, standards, hard constraints. Placeholders filled at creation; customize purpose/values afterward. |
| `habits/tool-enforcement.yaml` | Validates the required tool kit before tool invocation |
| `habits/identity-enforcement.yaml` | Gates actions through identity first |
| `habits/reflective-loop.yaml` | Post-completion reflection ("what did I miss?") |
| `enforcer-config.yaml` | Config for the optional enforcer daemon (separate-privilege validator) |

The identity hash (sha256 of `constitution.yaml`) is stamped into the agent's
`<agent-id>.json` at creation — a changed hash means the constitution was
edited after provisioning.

Full architecture, enforcer daemon, and memory pipeline:
`shared/skills/agent-identity-architecture/` (scripts: `enforcer_daemon.py`,
`agent_runtime.py`, `memory_curator.py`, `start-agent.sh`).

Optional and informative by design — a workspace without this layer still
runs; a workspace with it gets identity-first behavior.
