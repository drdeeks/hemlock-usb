# Free-First Cost Strategy

## Philosophy
Build systems that run entirely on local infrastructure first. Cloud is an enhancement, not a requirement.

## Cost Tiers

| Tier | Cost/Month | Stack | Use Case |
|------|------------|-------|----------|
| **Tier 0** | $0/mo | Python 3.8+ (stdlib only) | Local development, single agents, USB deployments |
| **Tier 1** | $0-5/mo | + CI/CD for automated validation | Team development, automated testing, skill registry |
| **Tier 2** | $5-20/mo | + Hosted skill registry for team distribution | Multi-agent crews, shared knowledge base, semantic search |

## What's Free (Tier 0)
- All Python scripts: `enforcer_daemon.py`, `agent_runtime.py`, `memory_curator.py`
- All Bash scripts: `install-agent.sh`, `start-agent.sh`, `verify-identity.sh`
- Constitution, habits, genesis — plain YAML/Markdown
- Memory pipeline: daily → weekly → long-term → knowledge index
- Enforcer daemon: Unix socket RPC, workspace validation, auto-remediation
- Tool enforcement: `enforce.sh`, `secret.sh`, `memory-log.sh`, `memory-promote.sh`
- Identity verification and agent creation

## What Costs Money (Optional)
| Feature | Why Optional | Typical Cost |
|---------|--------------|--------------|
| Turbopuffer semantic vectors | Semantic search enhancement | $10-50/mo |
| OpenAI embeddings | Vector generation | $0.0001/1K tokens |
| GitHub Actions / CI | Automated validation | Free for public, $0-5/mo private |
| Skill registry hosting | Team distribution | $5-20/mo |
| Ventoy USB hardware | Persistent portable deployments | $0 (reuse existing) |
| OpenClaw gateway | Multi-agent orchestration | Self-hosted free |

## Deployment Targets (All Free)
- Local machine (Linux/macOS/WSL)
- USB drive (Ventoy, persistent)
- Docker containers
- Any VM/VPS you already pay for
- CI/CD runners

## Principle
> If it requires a credit card to start, it's not Tier 0. Build the core so it runs on a $5 Raspberry Pi.