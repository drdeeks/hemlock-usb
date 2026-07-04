# Phase 29: Path Resolution & Portability

## Overview

Phase 29 eliminates all hardcoded `/home/drdeek/...` paths from the codebase by introducing `PathResolver`, a centralized, environment-driven path resolution system. Every filesystem path is now configurable via environment variables with context-aware defaults that adapt to Docker or local development.

## Architecture

### PathResolver (`docker/hermes-agent/paths.py`)

**Singleton pattern** with module-level `resolver` instance for easy import:

```python
from paths import resolver

agents_dir = resolver.agents_dir
skills_root = resolver.skills_root
```

**Environment variable override** for every path:

| Variable | Property | Docker Default | Local Default |
|---|---|---|---|
| `HEMLOCK_ROOT` | `root` | auto-detected | auto-detected |
| `HERMES_HOME` | `hermes_home` | `/runtime` | `{root}/docker/hermes-agent` |
| `HERMES_AGENTS` | `agents_dir` | `/agents` | `{root}/agents` |
| `HERMES_CREWS` | `crews_dir` | `/crews` | `{root}/crews` |
| `HERMES_PROJECTS` | `projects_dir` | `/projects` | `{root}/projects` |
| `HERMES_SKILLS` | `skills_root` | `/skills` | `{root}/skills/skills` |
| `HERMES_LOGS` | `logs_dir` | `/var/log/openclaw` | `{root}/logs` |
| `HERMES_MEMORY` | `memory_dir` | `/runtime/memory` | `{root}/memory` |
| `HERMES_PLUGINS` | `plugins_dir` | `/plugins` | `{root}/plugins` |
| `HERMES_BACKUPS` | `backups_dir` | `/backups` | `{root}/backups` |
| `HERMES_CONFIG` | `config_dir` | `/etc/openclaw` | `{root}/config` |
| `HERMES_SCRIPTS` | `scripts_dir` | `/scripts` | `{root}/scripts` |
| `HERMES_MODELS` | `models_dir` | `/models` | `{root}/models` |
| `HEMLOCK_DOCKER` | `is_docker` | — | — |

**Derived paths** (always computed from above):

| Property | Computation |
|---|---|
| `gateway_logs_dir` | `logs_dir / 'gateway'` |
| `killswitch_logs_dir` | `logs_dir / 'killswitch'` |
| `autonomy_memory_dir` | `memory_dir / 'autonomy'` |
| `plugin_backups_dir` | `backups_dir / 'plugins'` |
| `projects_decisions_dir` | `projects_dir / 'decisions'` |

**Docker detection** (in priority order):
1. `HEMLOCK_DOCKER=1|true|yes` → `True`
2. `HEMLOCK_DOCKER=0|false|no` → `False`
3. `/.dockerenv` exists → `True`
4. `/proc/1/cgroup` contains `docker` or `containerd` → `True`
5. Otherwise → `False`

**Root auto-detection** (walks up from `paths.py` location):
1. `HEMLOCK_ROOT` env var if set
2. Looks for `.hemlock-root`, `.git`, `hemlock.imhere` markers
3. Looks for `docker/` and `agents/` sibling directories
4. Falls back to `cwd()`

## Modules Updated

### Core Hermes-Agent Modules
- `crew/lifecycle.py` — `CrewLifecycleManager.__init__()` uses `resolver.crews_dir`, `resolver.agents_dir`, `resolver.projects_dir`
- `project/approval.py` — `CompletionApproval.__init__()` uses `resolver.projects_dir`
- `project/manager.py` — `ProjectManager.__init__()` uses `resolver.projects_dir`
- `runtime/cli.py` — CLI globals and `--root` flag use `resolver` singleton
- `runtime/init.py` — `verify_runtime_environment()` and `load_runtime_config()` use `resolver`
- `autonomy/protocol.py` — `AutonomyProtocol.__init__()` uses `resolver.autonomy_memory_dir`
- `gateway/monitor.py` — `GatewayMonitor.__init__()` uses `resolver.gateway_logs_dir`
- `gateway/killswitch.py` — `KillswitchHandler.__init__()` uses `resolver.killswitch_logs_dir`
- `volumes/volume_manager.py` — `VolumeManager.__init__()` uses `resolver.agents_dir`, `resolver.crews_dir`
- `skills/skill_registry.py` — `SkillRegistry.__init__()` uses `resolver.skills_root`, `resolver.agents_dir`
- `plugins/plugin_manager.py` — `PluginManager.__init__()` uses `resolver.agents_dir`, `resolver.plugins_dir`, `resolver.plugin_backups_dir`
- `production_bringup.py` — `ProductionRuntime.__init__()` uses `resolver`
- `identity/agent_identity.py` — `AgentIdentity.__init__()` uses `resolver.agents_dir`
- `cognition/cognitive_loop.py` — `CognitiveLoopCoordinator.__init__()` uses `resolver.agents_dir`
- `cognition/skill_sandbox.py` — `SkillRegistry` and `SkillEvolutionEngine` use `resolver`
- `cognition/skill_generation.py` — `SkillGenerationPipeline.__init__()` uses `resolver.agents_dir`
- `integration/openclaw_bridge.py` — `OpenClawHermesBridge.__init__()` uses `resolver`

### Infrastructure Modules
- `runtime/openclaw_supervisor.py` — All hardcoded `/srv/framework`, `/var/log`, `/etc/openclaw` paths replaced with env-var-driven config + `resolver` fallbacks
- `srv/framework/runtime/openclaw_supervisor.py` — `Config` class uses env vars for all paths
- `health/adapters/adapters_validator.py` — Uses `HERMES_HOME` env var
- `health/orchestration/orchestration_validator.py` — Uses `HERMES_HOME` env var

### Test Files
- `production_test.py` — Uses `resolver.hermes_home`
- `cognition/phase14_test.py` — Uses `resolver.root`, `resolver.hermes_home`
- `cognition/phase16_test.py` — Uses `resolver.hermes_home`
- `identity/phase15_test.py` — Uses `resolver.agents_dir`
- `integration/phase17_test.py` — Uses `resolver.hermes_home`, `resolver.agents_dir`
- `runtime/phase13_test.py` — Uses `resolver.hermes_home`, `resolver.agents_dir`

### Shell Scripts
- `scripts/hemlock-snapshot.sh` — Uses `$HEMLOCK_DIR` and `$SNAPS_DIR` env vars with auto-detection
- `scripts/auto-sync-snaps.sh` — Uses `$HEMLOCK_DIR` and `$SNAPS_DIR` env vars with auto-detection

## .env.example Configuration

Add to your `.env` file (or set as environment variables in Docker):

```bash
# Path Resolution (defaults auto-detected)
HEMLOCK_ROOT=/home/youruser/projects/hemlock    # Auto-detected if not set
HEMLOCK_DOCKER=0                                 # Set to 1 in Docker containers
HERMES_HOME=/runtime                             # Docker default, auto-detected locally
HERMES_AGENTS=/agents                            # Docker default, {root}/agents locally
HERMES_CREWS=/crews
HERMES_PROJECTS=/projects
HERMES_SKILLS=/skills
HERMES_LOGS=/var/log/openclaw
HERMES_MEMORY=/runtime/memory
HERMES_PLUGINS=/plugins
HERMES_BACKUPS=/backups
HERMES_CONFIG=/etc/openclaw
HERMES_SCRIPTS=/scripts
HERMES_MODELS=/models
```

## Permission Error Handling

All directory creation calls use `try/except PermissionError` to gracefully handle cases where the resolved path is not writable (e.g., `/agents` on host system). This ensures tests and local development work without `sudo`.

## Test Coverage

**85 tests** in `tests/unit/test_path_resolution.py`:

| Test Class | Count | Coverage |
|---|---|---|
| `TestPathResolverInit` | 4 | Singleton, explicit root, auto-detection |
| `TestDockerDetection` | 5 | HEMLOCK_DOCKER env var (true/false/yes/no/auto) |
| `TestPathResolutionLocal` | 15 | All properties resolve correctly under local root |
| `TestPathResolutionDocker` | 10 | All properties resolve to Docker defaults |
| `TestEnvOverrides` | 13 | Every env var overrides its path |
| `TestPathMethod` | 4 | `path()` method, case-insensitivity, unknown raises, all known |
| `TestCaching` | 2 | Cached properties, different roots give different paths |
| `TestEnsureDirs` | 3 | Directory creation, full ensure, unknown name raises |
| `TestToDict` | 3 | All keys present, string values, is_docker is bool |
| `TestModuleResolver` | 2 | Singleton instance, property access |
| `TestModuleIntegration` | 8 | CrewLifecycle, Approval, Volume, Skill, Plugin, Monitor, Killswitch, Autonomy |
| `TestPathResolutionNoHardcodedPaths` | 12 | No `/home/drdeek` in any resolved path |

## Remaining Hardcoded Paths (Intentional)

These paths are intentionally hardcoded in their respective contexts:

- **Dockerfile paths** (`Dockerfile`, `Dockerfile.base`, etc.) — Container build paths, must be absolute
- **Docker entrypoint paths** (`docker/entrypoint.sh`) — Container runtime paths
- **Docker-compose volume mounts** — Must match Dockerfile paths
- **System binary paths** (`/usr/local/bin`, `/opt/homebrew/bin`) — Platform-specific binary locations
- **Sensitive path patterns** (`~/.ssh`, `~/.aws`) — Security guard patterns, not runtime paths
- **`/tmp` paths** in volume manager — Temporary mount points, OS-standard
- **Shell script relative paths** (`../lib/common.sh`) — Source-relative, not project-root paths