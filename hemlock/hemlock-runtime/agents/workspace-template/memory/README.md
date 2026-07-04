# memory/ — the agent's persistent memory tree

Daily memory is UNLIMITED and never pruned. Files here are the agent's own notes,
organized by the agent (daily logs, promoted long-term facts, indexes). `MEMORY.md`
at the workspace root is the index the agent loads each session; `tools/memory-log.sh`
appends, `tools/memory-promote.sh` promotes daily notes to long-term.

Empty in the template on purpose: every agent starts with a blank memory and fills
it by living. Nothing here is ever deleted by the system.
