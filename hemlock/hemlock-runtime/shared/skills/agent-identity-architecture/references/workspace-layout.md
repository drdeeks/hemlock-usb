# Agent Workspace Layout — Standard Structure
# Enforcer-owned, agent-leased identity workspace

```
${WORKSPACE_ROOT}/synthesis-1/
├── .agent/                          # Agent identity (enforcer-owned, agent reads)
│   ├── constitution.yaml            # Identity constitution — Layer 1
│   ├── genesis.md                   # Origin story & founding principles
│   ├── habits/                      # Internalized habits (compiled from skills)
│   │   ├── identity-enforcement.yaml
│   │   ├── tool-enforcement.yaml
│   │   └── reflective-loop.yaml
│   ├── logs/                        # Violations, reflections, metrics
│   │   └── habit-violations.jsonl
│   ├── metrics/                     # Self-monitoring data
│   │   ├── identity-enforcement.json
│   │   ├── tool-enforcement.json
│   │   └── reflective-loop.json
│   ├── templates/                   # Auto-remediation templates
│   │   └── tool-enforcement/
│   │       ├── enforce.sh.template
│   │       ├── secret.sh.template
│   │       ├── memory-log.sh.template
│   │       ├── memory-promote.sh.template
│   │       └── TOOLS-GUIDE.md.template
│   └── constitutions/               # Archived constitutions
│
├── tools/                           # Required executable tools (agent runs)
│   ├── enforce.sh                   # Workspace structure enforcement
│   ├── secret.sh                    # Encrypted secret management
│   ├── memory-log.sh                # Daily memory logging
│   ├── memory-promote.sh            # Daily to long-term promotion
│   └── TOOLS-GUIDE.md               # Tool usage documentation
│
├── skills/                          # Agent-created skills
│   └── ...
│
├── memory/                          # Agent memory pipeline
│   ├── daily/                       # 2026-07-05.md (logged per action)
│   ├── weekly/                      # 2026-W27.md (curated weekly)
│   ├── long-term/                   # MEMORY.md (promoted patterns)
│   ├── knowledge-index.json         # Queryable wikilink index
│   └── MEMORY.md                    # Curated long-term lessons
│
├── .secrets/                        # Encrypted credentials (enforcer-owned)
│   └── .encryption_key              # AES-256 key (600 perms)
│
├── agent_runtime.py                 # Unprivileged agent process
├── enforcer_daemon.py               # Privileged enforcer process
├── memory_curator.py                # End-of-day curation
└── start-agent.sh                   # Bootstrap script
```

## Permission Reference

| Path | Owners | Agent Permissions | Enforcer Permissions |
|------|--------|-------------------|----------------------|
| `.agent/` | enforcer | r-x | rwx |
| `.agent/constitution.yaml` | enforcer | r-- | rw- |
| `.agent/habits/` | enforcer | r-x | rwx |
| `.agent/logs/` | agent | rw- | rw- |
| `.agent/templates/` | enforcer | r-- | rwx |
| `tools/` | enforcer | r-x | rwx |
| `tools/*.sh` | enforcer | r-x | rwx |
| `skills/` | agent | rwx | rwx |
| `memory/` | agent | rwx | r-x |
| `memory/daily/` | agent | rwx | r-- |
| `.secrets/` | enforcer | --- | rwx |
| `.secrets/*` | enforcer | --- | rw- |
| Agent runtime | agent | rwx | --- |
| Enforcer daemon | enforcer | --- | rwx |