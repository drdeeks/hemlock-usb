---
name: enterprise-organization
description: "Enterprise-grade organization management for AI agent systems. Enforces modular file tree, security hardening, gitignore standards, task-list-driven validation, zero-placeholder code policy, rigorous self-validation with rollback, append-only CHANGELOG.md with decision rationale, phase-tagged workflow, semantic versioning with automated releases, and robust git control. When: setting up new agent workspaces, auditing existing projects, enforcing enterprise standards, scaling agent infrastructure, managing phased development, releasing versions, controlling git operations. Triggers: 'enterprise setup', 'workspace audit', 'security hardening', 'modular enforcement', 'CHANGELOG enforcement', 'stub removal', 'phase management', 'version release', 'git control'."
version: 0.1.1
license: MIT
metadata:
  category: infrastructure
  complexity: enterprise
  tags:
    - enterprise
    - organization
    - security
    - gitignore
    - modular
    - validation
    - changelog
    - standards
    - phase-management
    - semantic-versioning
    - git-control
    - release-management
---

# Enterprise Organization

Enterprise-grade organization management for multi-agent AI systems. Provides standardized workspace structure, security hardening, modular file tree enforcement, task-list-driven validation, rigorous self-validation with rollback capabilities, phase-tagged workflow, semantic versioning with automated releases, and robust git control.

## When to Use

- Setting up new agent workspaces with enterprise standards
- Auditing existing projects for compliance
- Enforcing security hardening and gitignore standards
- Modular file tree enforcement across agents
- Zero-placeholder code policy enforcement
- Rigorous self-validation with rollback capabilities
- Append-only CHANGELOG.md with decision rationale tracking
- Phase-tagged development workflow
- Semantic versioning with automated release management
- Robust git control with hooks, branching, and sync

## Sources

| Source | URL | Last Verified |
|--------|-----|---------------|
| Gitignore Templates | https://github.com/github/gitignore | 2026-06-09 |
| OpenSSF Scorecard | https://github.com/ossf/scorecard | 2026-06-09 |
| NIST SSDF | https://csrc.nist.gov/Projects/ssdf | 2026-06-09 |
| Semantic Versioning | https://semver.org | 2026-06-09 |
| Keep a Changelog | https://keepachangelog.com | 2026-06-09 |
| Git SCM | https://git-scm.com | 2026-06-09 |
| Conventional Commits | https://www.conventionalcommits.org | 2026-06-09 |
| Playwright Test | https://playwright.dev/docs/test-intro | 2026-06-13 |
| OpenClaw Gateway | https://docs.openclaw.ai | 2026-06-13 |
| MCP Specification | https://modelcontextprotocol.io | 2026-06-13 |
| Docker Compose | https://docs.docker.com/compose/ | 2026-06-13 |
| Tar Archiving | https://www.gnu.org/software/tar/manual/ | 2026-06-13 |
| Cron | https://man7.org/linux/man-pages/man5/crontab.5.html | 2026-06-13 |
| Git | https://git-scm.com/docs | 2026-06-13 |


## Features

### Modular File Tree Enforcement
- Standardized directory structure per agent/project
- Role-based workspace layouts (Hermes/Titan/Avery/Allman)
- Automatic validation of file tree compliance
- Auto-correction of structural deviations

### Security Hardening & Gitignore Standards
- Comprehensive .gitignore templates per project type
- Secrets detection and prevention
- Permission auditing (700/600 enforcement)
- Supply chain security checks

### Task-List-Driven Validation
- Mandatory tracked task lists for all work
- Thorough validation of task completion
- No task marked complete without verification evidence
- Automatic rollback on validation failure

### Zero-Placeholder Code Policy
- Detects `TODO`-family work markers (to-be-decided, work-in-progress, fix-me styles)
- Rejects stub implementations
- Enforces real, wholesome, valid code only
- Validates against templates and patterns

### Rigorous Self-Validation
- Modular design verification
- Rollback option verification
- Performance benchmarking
- Cross-reference validation

### Append-Only CHANGELOG.md
- Every phase/task auto-updates CHANGELOG
- Includes: datetime, author, changes, method, validation, reasoning
- Immutable history with cryptographic hash chain
- Query by phase, author, date range

### Phase-Tagged Workflow (NEW)
- Define phases with metadata and tags
- Start phases with git tags and CHANGELOG entries
- Complete phases with summary and validation
- List and show phase history
- Tag files per phase for traceability
- Phase tags: `phase-<name>-start`, `phase-<name>-complete`

### Semantic Versioning & Release Management (NEW)
- Get, set, bump (major/minor/patch) versions
- Create annotated release tags
- Generate release notes from git log and CHANGELOG
- Version persisted in VERSION file, pyproject.toml, package.json
- Prerelease support
- List all versions from git tags

### Robust Git Control (NEW)
- Status, add, commit with signing/amend
- Push/pull with rebase and tag support
- Branch management (create, delete, list, merge)
- Merge with no-ff and squash options
- Log with filtering (limit, since, author)
- Diff (staged/unstaged, per file)
- Stash management (push, pop, drop, list)
- Git hooks setup (pre-commit, commit-msg, pre-push)
- Full sync (pull + push + tags)

### Combined Release Workflow (NEW)
- One-command release: bump version, tag, generate notes, update CHANGELOG, push
- Configurable bump type (major/minor/patch)
- Automatic phase tagging for releases
- Release notes from commits and CHANGELOG

### Hemlock Agent Framework Integration (NEW)
## Hemlock Agent Framework Integration (UPDATED)
- **Agent Identity Stack**: Complete workspace template (SOUL.md, AGENTS.md, IDENTITY.md, USER.md, TOOLS.md, MEMORY.md, HEARTBEAT.md, agent.json) with builder code hardwiring
- **Agent Templates**: 8 specialized templates (ui, integration, blockchain, debugger, documentation, optimization, architecture, validation) with personality, expertise, communication style, avatar
- **Agent Manager**: Lifecycle CRUD, builder code registration, Telegram bot wizard, workspace initialization, template-based generation
- **Builder Codes (ERC-8021)**: Framework detection (Privy > Wagmi > Viem > RPC), DATA_SUFFIX generation via ox/erc8021, client-level integration, base.dev verification
- **Model Management (llama.cpp)**: Hardware-aware build (CUDA/Metal/HIPBLAS/BLAS/OpenCL/Vulkan), singleton lock, efficient handoff (pre-load → SIGUSR1 → 30s graceful → swap), MCP registration, quantize/quantize/split/convert/prune/benchmark
- **Setup Wizard**: Interactive provider/model/runtime/agents/crews/deploy with Ollama/OpenAI/Anthropic/Groq/Together/Mistral/Custom providers
- **USB Automation**: Ventoy + persistence, headless VM boot, SSH port forwarding, auto-start systemd/LaunchAgent
- **Knowledge Indexer**: Full-text search, link management, incremental updates, scheduled indexing, fuzzy search
- **UNIFIED AGENT FEDERATION**: Single MCP-based federation for plug-and-play agents that join any project, provide compute, and self-learn
- **DYNAMIC AGENT SWARM**: Runtime agent discovery, project assignment, compute sharing, and self-learning coordination
- **ENTERPRISE-SCALE**: Load balancing, fault tolerance, resource management across agent ecosystem
- **SMART CONTRACT INTEGRATION**: Built-in ERC-8021 compliance, builder code registration, automated deployment scripts
- **REAL-TIME MONITORING**: Live federation status, agent health checks, performance metrics
- **CENTRALIZED GOVERNANCE**: Single authority for agent lifecycle, resource allocation, and policy enforcement

## Quick Start

```bash
# Initialize enterprise organization for a project
python3 scripts/enterprise-org.py init --project my-agent --role hermes

# Validate existing workspace
python3 scripts/enterprise-org.py validate --workspace /path/to/workspace

# Enforce standards
python3 scripts/enterprise-org.py enforce --workspace /path/to/workspace --fix

# Phase management
python3 scripts/enterprise-org.py phase --action start --phase "feature-development" --no-commit
python3 scripts/enterprise-org.py phase --action complete --phase "feature-development" --summary "Implemented user auth"

# Full release workflow
python3 scripts/enterprise-org.py release --bump patch --release-message "Patch release with bug fixes"
```

## Advanced Usage

```bash
# Full audit with report
python3 scripts/enterprise-org.py audit --workspace /path/to/workspace --report enterprise-audit.json

# Validate todo completion
python3 scripts/enterprise-org.py validate-todos --workspace /path/to/workspace --strict

# Check for placeholders
python3 scripts/enterprise-org.py scan-placeholders --workspace /path/to/workspace --fail-on-found

# Verify rollback capability
python3 scripts/enterprise-org.py verify-rollback --workspace /path/to/workspace

# Phase tagging files
python3 scripts/enterprise-org.py phase --action tag-files --phase "release-prep" --pattern "scripts/*.py" --message "Release prep scripts"

# Git hooks setup
python3 scripts/enterprise-org.py git --git-action hooks

# Branch management
python3 scripts/enterprise-org.py git --git-action branch --name feature/auth --create
python3 scripts/enterprise-org.py git --git-action merge --source feature/auth --target main --no-ff

# View version history
python3 scripts/enterprise-org.py version --action list
```

## Context Management

**Unified memory across all unified agents:**
- Agents store everything in a shared local Hermes home (~/.hermes)
- `memory` = agent-specific notes (agent_id, task_context, working_memory)
- `skills` = agent-specific reusable logic (function/schema registry)
- `profile` = organization/role boundaries (hermes-agent, agent-powerhouse, etc.)
- Shared structures: `workspace`, `profile`, `memory`, `skills`
- Memory persists across all agents
- Agent sends memory updates to all other agents
- Shared dynamics: tasks, notes, skills, problems
- All agents see the same memory visualizations

**MCP Federation Overview:**

| Path | Endpoint | Protocol | Use Case |
|------|----------|----------|---------|
| `http://localhost:18789/api/blueprints` | GET | External | List running projects for join requests |
| `http://localhost:18789/api/join` | POST | External | Agents join projects (required agentId, projectId, compute resources) |
| `http://localhost:18789/api/assign-work` | POST | External | Project assigns work via standardized JSON (agentId, task, taskId, priority) |
| `http://localhost:18789/api/projects/:id/status` | GET | External | Query project status including active agents |
| `http://localhost:18789/api/stats` | GET | External | View federation statistics |

**WebSocket Agent Communication:**
- Agents connect via `ws://localhost:18789/<agentId>`
- Each agent subscribes to a specific project and can receive real-time updates
- Standardized message format for project coordination and task assignment

**Dynamic Project Rules:**

### Project Membership Management:
1. Agents register with existing Hermes projects
2. System validates ownership and resource requirements
3. Phase-based join process ensures consistent project onboarding
4. Real-time updates on new agent connections

### Resource Sharing:
1. Compute allocation follows project quota system
2. Skills and capabilities are shared across project members
3. Dynamic priority resolution prevents conflicts
4. Resource tags enable targeted assignment

### Work Distribution:
1. Project orchestrator assigns work to appropriate agents
2. Rest API provides endpoints for task management
3. WebSocket real-time communication for instant updates
4. Flexible assignment based on agent capabilities and project needs

**Federation Design:**
- Both Hermes and Agent Powerhouse designed with multi-tenancy
- Shared infrastructure provides service, allowing customization based on per-project permissions
- Independent Agent Powerhouse platform management, reusable
- Dialogue between agents is standardized across all systems
- Feedback and interaction points provide consistency and flexibility
- Unused or new agents can be added to enhance system capabilities

**Scalability:**
- Agents join projects via registration endpoints
- Runs multiple agent systems independently within the same network
- Supports adding, removing, or deleting agents from any project
- ** DYNAMIC AGENT SWARM**: Runtime agent discovery, project assignment, compute sharing, and self-learning coordination
- ** ENTERPRISE-SCALING**: Load balancing, fault tolerance, resource management across agent ecosystem
- ** SMART CONTRACT INTEGRATION**: Built-in ERC-8021 compliance, builder code registration, automated deployment scripts
- ** REAL-TIME MONITORING**: Live federation status, agent health checks, performance metrics
- ** CENTRALIZED GOVERNANCE**: Single authority for agent lifecycle, resource allocation, and policy enforcement

## Scripts Reference

| Script | Purpose | Usage |
|--------|---------|-------|
| `scripts/enterprise-org.py` | Main entry point - init, validate, enforce, audit, changelog, phase, version, git, release | `python3 scripts/enterprise-org.py --help` |
| `scripts/main.py` | Standardized entry point with skill metadata | `python3 scripts/main.py` |
| `scripts/validate.py` | Skill structure validation | `python3 scripts/validate.py` |
| `scripts/validate_structure.py` | Modular file tree validation | `python3 scripts/validate_structure.py --workspace /path` |
| `scripts/security_hardening.py` | Security & gitignore enforcement | `python3 scripts/security_hardening.py --workspace /path --fix` |
| `scripts/task_validator.py` | Task-list completion validation | `python3 scripts/task_validator.py --workspace /path --strict` |
| `scripts/stub_scanner.py` | Zero-stub enforcement | `python3 scripts/stub_scanner.py --workspace /path --fail-on-found` |
| `scripts/self_validator.py` | Rigorous self-validation with rollback | `python3 scripts/self_validator.py --workspace /path --verify-rollback` |
| `scripts/changelog_manager.py` | Append-only CHANGELOG management | `python3 scripts/changelog_manager.py --action add --phase "phase" --author "agent" --reason "..."` |
| `scripts/version_manager.py` | Semantic versioning & releases | `python3 scripts/version_manager.py --help` |
| `scripts/git_control.py` | Robust git operations | `python3 scripts/git_control.py --help` |
| `scripts/phase_tagger.py` | Phase tagging & tracking | `python3 scripts/phase_tagger.py --help` |

## Key References

- **Playwright Test Configuration & Debugging**: [references/playwright-testing.md](references/playwright-testing.md)
- **OpenClaw Gateway Authentication & Configuration**: [references/openclaw-gateway.md](references/openclaw-gateway.md)
- **Security Hardening Script Improvements**: [references/security-hardening.md](references/security-hardening.md)
- **Tar Archiving Best Practices**: [references/tar-archiving-best-practices.md](references/tar-archiving-best-practices.md)
- **Hemlock Minimal Deployment Package**: [references/hemlock-deployment-package.md](references/hemlock-deployment-package.md)
- **Session 2026-06-13: Hemlock Minimal Deployment**: [references/session-2026-06-13-hemlock-minimal-deployment.md](references/session-2026-06-13-hemlock-minimal-deployment.md)
- **Container-Internal Cron Jobs**: [references/container-internal-cron.md](references/container-internal-cron.md)
- **USB Deployment with Ventoy**: [references/ventoy-usb-deployment.md](references/ventoy-usb-deployment.md)
- **Setup Wizard TUI/Docker Integration**: [references/setup-wizard-tui-docker.md](references/setup-wizard-tui-docker.md)
- **Daily Skills Auto-Pull**: [references/daily-skills-autopull.md](references/daily-skills-autopull.md)
- **MCP Proxy Manager Self-Healing**: [references/mcp-proxy-self-healing.md](references/mcp-proxy-self-healing.md)
- **Modular File Tree Standard**: [references/modular-file-tree.md](references/modular-file-tree.md)
- **Tar Archiving Best Practices**: [references/tar-archiving-best-practices.md](references/tar-archiving-best-practices.md)
- **Hemlock Minimal Deployment Package**: [references/hemlock-deployment-package.md](references/hemlock-deployment-package.md)
- **Session 2026-06-14: Hemlock Agent Framework Integration**: [references/session-2026-06-14-hemlock-integration.md](references/session-2026-06-14-hemlock-integration.md)
- **Ventoy USB Deployment with Hemlock**: [references/ventoy-usb-deployment.md](references/ventoy-usb-deployment.md)

## Provider Compatibility

| Provider | Compatibility | Notes |
|----------|---------------|-------|
| Claude (Anthropic) | Full | MCP servers, tool use |
| OpenAI / ChatGPT | Full | Function calling, Actions |
| Mistral / Le Chat | Full | Tool calling, script execution |
| Gemini (Google) | Full | Extensions, Vertex AI |
| Hermes (Nous) | Full | Tool-use fine-tuned |
| GitHub Copilot | Partial | Code generation; use external runner for scripts |
| Any LLM + tools | Full | Scripts are plain Python, provider-independent |

## Free-First Strategy

| Tier | Cost | Stack |
|------|------|-------|
| **Tier 0** | $0/mo | Python 3.8+ (all scripts use stdlib only) |
| **Tier 1** | $0-5/mo | + CI/CD for automated validation |
| **Tier 2** | $5-20/mo | + Hosted skill registry for team distribution |

The entire core toolchain is permanently $0.

## Enforced Output Statistics

Every script produces structured output on completion:

```json
{
  "operation": "script_name",
  "timestamp": "ISO8601",
  "status": "success | failed",
  "skill_name": "the-skill-name",
  "details": {},
  "cost": {"tier": 0, "amount_usd": 0.0, "service": "local"}
}
```

## Error Handling

| Error | Response |
|-------|----------|
| Invalid input | Validate and report with guidance |
| Missing dependency | Auto-install or report requirement |
| Network failure | Retry with exponential backoff |
| Permission denied | Report and suggest alternatives |
| Resource not found | Report with available options |

## Enhancement Hooks

| Skill | Enhancement | When to Add |
|-------|-------------|-------------|
| `skill-creator` | Basic skill creation | When creating simple skills |
| `skill-creator-pro` | Enterprise upgrade | When upgrading to enterprise |
| `html-report` | Visual validation dashboard | When auditing many skills |
| `xlsx` | Export validation results | When tracking skill quality metrics |
| `agent-bootstrap-manager` | Agent workspace creation | When bootstrapping new agents |

## Enforcement Rules

1. **No work begins without a tracked task list** - Every task requires one
2. **No task marked complete without validation evidence** - Verification artifacts required
3. **No stubs or unfinished-work markers in production code** - Zero tolerance
4. **Create real, complete, wholesome files - never stubs or placeholders** - Complete Files Principle
5. **Every change logged to CHANGELOG.md** - Immutable, append-only with rationale
6. **Modular file tree enforced at all times** - Auto-correction on deviation
7. **Security standards non-negotiable** - .gitignore, permissions, secrets
8. **Rollback capability verified before deployment** - Test rollback pre-commit
9. **Self-validation runs on every operation** - Continuous compliance
10. **Phases tagged in git** - Every phase start/complete creates git tag
11. **Versions follow semver** - Automated bumping and tagging
12. **Git hooks enforce standards** - Pre-commit validation, commit-msg format, pre-push checks

## Phase Management Details

### Phase Lifecycle
```
define → start → (work) → complete → tag files
```

### Phase Tags in Git
- Start: `phase-<name>-<timestamp>` (annotated)
- Complete: `phase-<name>-complete-<timestamp>` (annotated)
- Files: `phase-<name>-files-<timestamp>` (annotated)

### Phase Storage
- Definitions: `.phases.json` (machine-readable)
- CHANGELOG: Human-readable entries per phase
- `TODO.md`: Phase-based task tracking

## Version Management Details

### Version Sources (priority order)
1. Git tags (`v*`)
2. VERSION file
3. pyproject.toml
4. package.json
5. setup.py

### Release Tags
- Format: `v<major>.<minor>.<patch>` (e.g., `v1.2.3`)
- Annotated with message
- Pushed with `--tags` option

### Release Notes
Generated from:
- Commits since last tag
- CHANGELOG entries for version
- Formatted as Markdown

## Git Control Details

### Pre-commit Hook
Runs:
- Placeholder scanner (fail on found)
- Security hardening check

### Commit-msg Hook
Validates conventional commit format:
```
type(scope): description
e.g., feat(auth): add OAuth2 login
```

### Pre-push Hook
Runs full validation:
- `enterprise-org.py validate`

### Branch Strategy
- Main branch: `main` (protected)
- Feature branches: `feature/*`
- Release branches: `release/*`
- Hotfix branches: `hotfix/*`

### Merge Options
- `--no-ff`: Preserve branch history
- `--squash`: Single commit for feature

## Verification

```bash
# Full diagnostic scan
python3 scripts/enterprise-org.py audit --workspace .

# Test phase workflow
python3 scripts/enterprise-org.py phase --action start --phase test-phase
python3 scripts/enterprise-org.py phase --action complete --phase test-phase --summary "Test done"

# Test version workflow
python3 scripts/enterprise-org.py version --action bump --bump-type patch
python3 scripts/enterprise-org.py version --action release --version-arg 1.0.1

# Test git hooks
python3 scripts/enterprise-org.py git --git-action hooks

# Verify rollback
python3 scripts/self_validator.py --workspace . --verify-rollback
```

## Dry-Run Pattern (Reusable)

For any bash script with mutating operations:

```bash
# Parse flag before main logic
DRY_RUN=false
for arg in "$@"; do
    case "$arg" in
        --dry-run|-n) DRY_RUN=true; shift ;;
    esac
done

# Wrapper function
run() {
    if [ "$DRY_RUN" = true ]; then
        echo "[dry-run] $*"
        return 0
    fi
    "$@"
}

# Wrap all mutating commands
run mkdir -p "$dir"
run rm -f "$file"
run ln -sf "$src" "$dst"
run chmod 600 "$file"
run git -C "$dir" init

# For heredoc file writes, guard with if-block
if [ "$DRY_RUN" = false ]; then
    { echo "content"; } > "$file"
else
    echo "[dry-run] Write → $file"
fi
```