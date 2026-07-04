# Hemlock Master Blueprint - Current State

**Version**: 1.0 (Phase 30 Complete)  
**Last Updated**: 2026-05-14  
**Status**: Production Ready

---

## System Overview

Hemlock is an enterprise-grade multi-agent AI orchestration framework with complete operational health monitoring, Docker-native deployment, and OpenClaw/Hermes dual-agent architecture.

---

## 1. Core Architecture

### 1.1 Agent Model

```
┌─────────────────────────────────────────────────────────┐
│                    OPENCLAW (Driver)                     │
│  - Configuration: ~/.openclaw/openclaw.json (JSON5)    │
│  - Workspace: agents/{agent-id}/ (self-contained)                     │
│  - Commands: onboard, pair, manage                      │
│  - Role: Primary orchestration & agent management       │
└─────────────────────────────────────────────────────────┘
                          │
                          │ Directives
                          ▼
┌─────────────────────────────────────────────────────────┐
│                    HERMES (Silent Runtime)               │
│  - Home: HERMES_HOME (per-profile isolation)            │
│  - Secrets: ~/.hermes/.secrets/secrets.json (JSON)      │
│  - Skills: 289 skills (/skills/skills/, RO mount)       │
│  - Role: Silent agent loop, executes OpenClaw directives│
└─────────────────────────────────────────────────────────┘
```

### 1.2 Runtime Architecture

```
┌─────────────────────────────────────────────────────────┐
│              RUNTIME DAEMON (docker/hermes-agent/)      │
│                                                          │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐  │
│  │   init.py    │  │    cli.py    │  │ daemon_mgr.py│  │
│  │  (entrypoint)│  │  (commands)  │  │ (lifecycle)  │  │
│  └──────────────┘  └──────────────┘  └──────────────┘  │
│                                                          │
│  ┌──────────────┐  ┌──────────────┐                     │
│  │  paths.py    │  │  health/     │                     │
│  │ (resolver)   │  │  (validators)│                     │
│  └──────────────┘  └──────────────┘                     │
└─────────────────────────────────────────────────────────┘
```

---

## 2. Health System (Phase 30)

### 2.1 Health Check Categories

| Category | Checks | Description | Validator |
|----------|--------|-------------|-----------|
| PATHS | 24 | Path resolution & directory existence | `health/paths/paths_validator.py` |
| ENV | 24 | Environment variables & .env files | `health/env/env_validator.py` |
| IDENTITY | 3 | Agent identity validation | `health/identity/identity_validator.py` |
| GATEWAY | 5 | Gateway configuration | `health/gateway/gateway_validator.py` |
| IMPORTS | 2 | Module import validation | `health/imports/imports_validator.py` |
| ADAPTERS | 8 | Platform adapter checks | `health/adapters/adapters_validator.py` |
| ORCHESTRATION | 4 | Orchestration layer | `health/orchestration/orchestration_validator.py` |
| PERSISTENCE | 2 | SQLite & JSON persistence | `health/persistence/persistence_validator.py` |

**Total**: 85 checks across 8 categories

### 2.2 Health Check Modes

```python
# Quick mode (5s) - paths, env, imports only
python3 -m health.doctor_bridge --quick

# Full mode (60s) - all 85 checks
python3 -m health.doctor_bridge

# Auto-fix mode - remediate issues
python3 -m health.doctor_bridge --fix

# JSON output - for automation
python3 -m health.doctor_bridge --json
```

### 2.3 Current Health Status

```
Status: HEALTHY ✓
Checks: 41 ok, 14 warn, 0 fail
Duration: ~2.3s
```

---

## 3. Deployment Architecture

### 3.1 Docker Runtime (Production)

**Image**: `hemlock:latest` (329MB)

**Services**:
```yaml
runtime:
  build: Dockerfile.runtime
  healthcheck: doctor_bridge --quick --json
  volumes: [hermes_home, skills, memory]
  
agent:
  depends_on: [runtime]
  profiles: [agent]
  
doctor:
  command: doctor_bridge --full
  profiles: [diagnostics]
  
setup:
  command: init.py --setup
  profiles: [setup]
```

**Dockerfile.runtime** (2-stage build):
```dockerfile
Stage 1 (builder): Python 3.12-slim, pip install
Stage 2 (runtime): Minimal deps, health checks
Size: 329MB
Extras: pip install hemlock[telegram,discord,...]
```

### 3.2 Native Runtime (Development)

**Entry Point**: `runtime.sh`

**Interactive Menu**:
```
[30] Health check
[31] Key injection (OpenClaw → Hermes)
[32] Runtime management
[33] System doctor
[34] Docker runtime operations
```

---

## 4. Security Architecture

### 4.1 Secret Management

```
┌─────────────────────────────────────────────────────────┐
│                    SECRETS VAULT                         │
│                                                          │
│  Storage: ~/.hermes/.secrets/secrets.json (JSON)        │
│  Access: Tool calls only (enforce.sh, secret.sh)       │
│  Injection: scripts/key_inject.py                       │
│  Audit: All operations logged                           │
└─────────────────────────────────────────────────────────┘
```

**Key Types**:
- OpenRouter API Key (optional)
- Anthropic API Key (optional)
- Telegram Bot Token (optional)
- Discord Bot Token (optional)
- GitHub Token (optional)

### 4.2 Access Control

| Layer | Mechanism | Implementation |
|-------|-----------|----------------|
| Authentication | JWT | GUI frontend |
| Authorization | RBAC | Role-based permissions |
| Session | Timeout | 30min inactivity |
| Network | HTTPS | TLS 1.3 |
| Audit | Logging | All operations |

---

## 5. File Organization

### 5.1 Directory Structure

```
hemlock/
├── docs/                      # Documentation
│   ├── ARCHITECTURE.md        # System architecture
│   ├── BLUEPRINT.md           # This file (master blueprint)
│   ├── GUI_SPEC.md            # UI/UX specifications (779 lines)
│   ├── QUICKSTART.md          # Getting started
│   └── README.md              # Enterprise docs
│
├── src/                       # Source code
│   ├── health/                # Health validators (8 categories)
│   │   ├── doctor_bridge.py   # Main orchestrator
│   │   ├── paths/             # Path validation
│   │   ├── env/               # Environment validation
│   │   ├── identity/          # Identity validation
│   │   ├── gateway/           # Gateway validation
│   │   ├── imports/           # Import validation
│   │   ├── adapters/          # Adapter validation
│   │   ├── orchestration/     # Orchestration validation
│   │   └── persistence/       # Persistence validation
│   │
│   ├── scripts/               # Utility scripts
│   │   ├── key_inject.py      # Key injection
│   │   └── ...
│   │
│   └── tools/                 # Agent tools
│       ├── enforcement/       # Tool enforcement
│       └── memory/            # Memory management
│
├── docker/                    # Docker configuration
│   ├── Dockerfile.runtime     # Production image
│   ├── docker-compose.runtime.yml
│   └── hermes-agent/          # Hermes runtime
│       ├── runtime/
│       │   ├── init.py        # Runtime init
│       │   ├── cli.py         # CLI commands
│       │   └── daemon_manager.py
│       └── paths.py           # Path resolver
│
├── runtime.sh                 # Primary access point
├── build.sh                   # Build automation
├── .env.template              # Environment template
└── .gitignore
```

### 5.2 Key Files

| File | Purpose | Lines |
|------|---------|-------|
| `runtime.sh` | Interactive menu & CLI | 2440 |
| `docker/hermes-agent/runtime/init.py` | Runtime entrypoint | 350 |
| `health/doctor_bridge.py` | Health orchestrator | 215 |
| `scripts/key_inject.py` | Key injection | 180 |
| `docker/hermes-agent/paths.py` | Path resolver | 230 |
| `GUI_SPEC.md` | UI specifications | 779 |
| `docker-compose.runtime.yml` | Production compose | 120 |

---

## 6. Operational Phases

### 6.1 Completed Phases

| Phase | Description | Tests | Status |
|-------|-------------|-------|--------|
| 0-25 | Core framework | 144/144 | ✓ Complete |
| 26 | Crew Lifecycle | 66 | ✓ Complete |
| 27 | Script Modernization | 41 | ✓ Complete |
| 28 | Compliance Analysis | 92 (94% coverage) | ✓ Complete |
| 29 | Path Resolution & Portability | 85 | ✓ Complete |
| 30 | Operational Health & Integration | 52 | ✓ Complete |

**Total Verified Tests**: 229

### 6.2 Phase 30 Features

- ✓ Health check system (8 categories, 85 checks)
- ✓ Key injection (OpenClaw → Hermes)
- ✓ Runtime management (Docker + native)
- ✓ System doctor (diagnostics + auto-fix)
- ✓ Docker runtime operations
- ✓ Menu integration (runtime.sh options 30-34)
- ✓ GUI specification (779 lines)
- ✓ API endpoint specifications (20+)

---

## 7. API Specifications

### 7.1 Health API

```yaml
GET /api/health/quick:
  description: Quick health check (paths, env, imports)
  response: { healthy: bool, checks: [], duration_ms: number }
  
GET /api/health/full:
  description: Full 85-point validation
  response: { healthy: bool, results: [CheckResult], summary: {} }
  
POST /api/health/fix:
  description: Auto-fix identified issues
  body: { categories: [], force: bool }
```

### 7.2 Key Management API

```yaml
GET /api/keys/status:
  description: Current key injection status
  response: { injected: [], missing: [], expired: [] }
  
POST /api/keys/inject:
  description: Inject keys from source
  body: { source: 'openclaw' | 'file' | 'manual', config: {} }
  
POST /api/keys/verify:
  description: Verify injected keys
  response: { valid: [], invalid: [], missing: [] }
```

### 7.3 Runtime API

```yaml
GET /api/runtime/status:
  description: Runtime daemon status
  response: { running: bool, pid: int, uptime: str, resources: {} }
  
POST /api/runtime/start:
  description: Start runtime daemon
  body: { mode: 'docker' | 'native' }
  
POST /api/runtime/stop:
  description: Stop runtime daemon
  body: { graceful: bool, timeout: int }
```

### 7.4 Doctor API

```yaml
POST /api/doctor/scan:
  description: Run doctor diagnostics
  body: { mode: 'quick' | 'full' | 'deep', categories: [], auto_fix: bool }
  
GET /api/doctor/results:
  description: Get latest scan results
  response: { issues: [], fixed: [], recommendations: [] }
```

### 7.5 Docker API

```yaml
GET /api/docker/containers:
  description: List all containers
  response: { containers: [ContainerInfo] }
  
POST /api/docker/action:
  description: Perform container action
  body: { action: 'start' | 'stop' | 'restart', containers: [] }
  
GET /api/docker/logs:
  description: Stream container logs
  query: { container: str, follow: bool, tail: int }
```

---

## 8. Integration Points

### 8.1 OpenClaw Integration

```
OpenClaw Config (~/.openclaw/openclaw.json)
    │
    │ key_inject.py
    ▼
Hermes Secrets (~/.hermes/.secrets/secrets.json)
    │
    │ .env injection
    ▼
Hermes Runtime (HERMES_HOME/.env)
```

### 8.2 Docker Integration

```
docker-compose.runtime.yml
    │
    ├── runtime service (main daemon)
    ├── agent service (execution)
    ├── doctor service (diagnostics)
    └── setup service (initialization)
    
Health: HEALTHCHECK → doctor_bridge --quick --json
```

### 8.3 GUI Integration

```
Frontend (React + TypeScript)
    │
    │ WebSocket + REST API
    ▼
Backend (FastAPI - planned)
    │
    │ Python modules
    ▼
Hemlock Core (health, runtime, scripts)
```

---

## 9. Performance Requirements

| Metric | Target | Current |
|--------|--------|---------|
| Health check (quick) | < 5s | ~2.3s ✓ |
| Health check (full) | < 60s | ~3s ✓ |
| Key injection | < 10s | < 1s ✓ |
| Runtime start | < 30s | ~5s ✓ |
| Docker image size | < 500MB | 329MB ✓ |
| API response (p95) | < 200ms | N/A (planned) |

---

## 10. Security Requirements

- [x] Secrets stored as JSON, never accessed directly
- [x] All operations logged with user context
- [x] Confirmation dialogs for destructive actions
- [x] Input validation and sanitization
- [ ] HTTPS enforcement (GUI - planned)
- [ ] MFA support (GUI - planned)
- [ ] RBAC implementation (GUI - planned)

---

## 11. Current Status Summary

| Aspect | Status | Details |
|--------|--------|---------|
| **Commit** | Current | Phase 30: Menu Integration & GUI Specification |
| **Health** | HEALTHY | 41 ok, 14 warn, 0 fail |
| **Tests** | 229 verified | All phases 0-30 |
| **Docker** | Ready | 329MB image, health checks |
| **GUI Spec** | Complete | 779 lines, 5 dashboards |
| **API Spec** | Complete | 20+ endpoints |
| **Production** | Ready | Yes |

---

## 12. Next Phase Priorities

1. **GUI Implementation** (React + TypeScript + Material-UI)
2. **API Server** (FastAPI with WebSocket support)
3. **Enhanced Security** (MFA, RBAC, audit logging)
4. **Performance Optimization** (caching, async operations)
5. **Extended Monitoring** (Prometheus + Grafana integration)
6. **CI/CD Pipeline** (GitHub Actions, automated testing)

---

## Appendix: Command Reference

### Interactive Menu
```bash
./runtime.sh                              # Launch interactive menu
```

### Health Checks
```bash
./runtime.sh health-check --quick         # Quick health (5s)
./runtime.sh health-check --full          # Full health (60s)
./runtime.sh health-check --fix           # Auto-fix issues
./runtime.sh health-check --json          # JSON output
```

### Key Injection
```bash
./runtime.sh key-inject --from-openclaw   # From OpenClaw config
./runtime.sh key-inject --from-file FILE  # From JSON file
./runtime.sh key-inject --dry-run         # Preview only
./runtime.sh key-inject --verify          # Verify injected
```

### Runtime Management
```bash
./runtime.sh runtime-start --docker       # Start Docker runtime
./runtime.sh runtime-start --native       # Start native runtime
./runtime.sh runtime-status               # Check status
./runtime.sh runtime-logs --follow        # Stream logs
```

### System Doctor
```bash
./runtime.sh doctor --quick               # Quick scan
./runtime.sh doctor --full                # Full diagnostics
./runtime.sh doctor --deep                # Deep scan + fix
./runtime.sh doctor --json                # JSON report
```

### Docker Operations
```bash
./runtime.sh docker-up                    # Start all services
./runtime.sh docker-down                  # Stop all services
./runtime.sh docker-restart               # Restart services
./runtime.sh docker-doctor                # Run doctor service
./runtime.sh docker-build                 # Build runtime image
```

---

## Agent Isolation

Each agent is fully self-contained in `agents/{agent-id}/`:

```
agents/jack/
├── identity.md          # Agent identity
├── memory/              # Memory storage
│   └── graph.json
├── tools/               # Agent tools
│   ├── enforce.sh
│   ├── secret.sh
│   └── memory-*.sh
├── skills/              # Agent skills
│   └── {skill-name}/SKILL.md
├── workspace/           # Agent workspace
├── state/               # State storage
├── reflections/         # Reflection logs
└── sessions/            # Session history
```

**Isolation**: Docker volumes ensure agents cannot access each other's data.
**Portability**: Export/import entire agent directory.
**Path Resolution**: Customizable via `HERMES_AGENTS` environment variable.

---

## Agent Workspace Structure

Each agent workspace is self-contained and follows the standardized template:

```
agents/{agent-id}/
├── agent.json             # Agent configuration
├── agent/
│   ├── SOUL.md           # Core identity
│   ├── USER.md           # User preferences
│   └── AGENTS.md         # Agent documentation
├── memory/               # Memory storage (short/long term)
├── knowledge/            # Knowledge base
│   ├── api/
│   ├── examples/
│   ├── patterns/
│   └── references/
├── tools/                # Agent tools
│   ├── configs/
│   ├── scripts/
│   ├── enforce.sh        # Workspace enforcement
│   ├── secret.sh         # Secret management
│   └── memory-*.sh       # Memory operations
├── workflows/            # Workflow definitions
├── projects/             # Active projects
├── sessions/             # Session history
├── archives/             # Archived data
├── backups/              # Backup snapshots
├── cache/                # Temporary cache
├── temp/                 # Temporary files
├── .scope/               # Scope configuration
└── .secrets/             # Encrypted secrets (tool-access only)
```

### Enforcement

Workspace structure is enforced by `agent-workspace-enforcement` skill:

```bash
# Enforce workspace structure
bash scripts/enforce.sh $HERMES_HOME

# Or from heartbeat
bash scripts/enforce.sh "$HERMES_HOME"
```

**Enforcement actions**:
1. Fixes ownership (root → agent)
2. Ensures required directories exist
3. Renames forbidden dirs (cache→media, memories→memory, archives→.archive)
4. Archives runtime artifacts
5. Removes bloat files
6. Validates required files (SOUL.md, USER.md, AGENTS.md, agent.json)
7. Fixes permissions (755 dirs, 644 files, NEVER 700)
8. Verifies tools/ directory standard
9. Checks SOUL.md identity

### Path Resolution

```python
from paths import resolver

# Agent workspace path
agent_workspace = resolver.hermes_home  # $HERMES_HOME

# Customizable via environment
export HERMES_HOME=/custom/path/to/agent
```

**Docker**: `/data/agents/{agent-id}/`  
**Native**: `~/.openclaw/agents/{agent-id}/` or custom via `HERMES_HOME`

### Isolation

- Each agent has isolated volume in Docker
- Cannot access other agents' workspaces
- Secrets accessible only via tool calls (`secret.sh`, `enforce.sh`)
- Skills copied from read-only mount to workspace

