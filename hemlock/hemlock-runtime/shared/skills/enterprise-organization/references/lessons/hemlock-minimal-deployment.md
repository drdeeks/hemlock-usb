## Hemlock Minimal Deployment Package

### Package Structure
```
hemlock-minimal/
├── docker-compose.yml          # Container orchestration
├── Dockerfile.runtime          # Base runtime image
├── entrypoint.sh               # Container PID 1
├── mcp_bridge.py               # Hermes MCP bridge server
├── .gitignore                  # Enterprise exclusions
├── README.md                   # Documentation
├── CHANGELOG.md                # Append-only history
├── TODO.md                     # Phase-based tasks
├── scripts/                    # 20+ management scripts
│   ├── hemlock                 # Main CLI
│   ├── hemlock-tui             # Interactive TUI
│   ├── mcp_proxy_manager.py    # Self-healing proxy
│   ├── pull-drdeeks-daily.sh   # Daily skills pull
│   ├── container-init.sh       # Container startup
│   └── ...
├── docker/                     # Build contexts
│   ├── Dockerfile.runtime
│   └── Dockerfile (symlink)
├── skills/                     # 180+ skills
│   ├── drdeeks/                # 131 skills from GitHub
│   ├── enterprise-blueprint/   # Enterprise standards
│   └── openclaw/               # OpenClaw built-in
├── blueprint/                  # Project blueprints
├── tests/                      # Playwright test suite
│   ├── *.spec.ts               # 12 test files
│   └── playwright.config.js
└── docker/                     # Runtime volumes
```

### Key Scripts
| Script | Purpose |
|--------|---------|
| `hemlock` | Main CLI: agent/crew lifecycle, gateway, doctor |
| `hemlock-tui` | Interactive TUI for agent/skill management |
| `mcp_proxy_manager.py` | Self-healing MCP proxy (systemd) |
| `pull-drdeeks-daily.sh` | Daily `git pull` of drdeeks skills |
| `container-init.sh` | Container startup |

### USB Deployment
```bash
# Create USB image
./scripts/create-usb-image.sh /tmp/hemlock-usb

# On target machine
cd /tmp/hemlock-usb && sudo ./deploy.sh
```

### Session 2026-06-13: Hemlock Minimal Deployment (NEW)
- Complete Hemlock Minimal package built and validated
- 55.8 MB archive with 2,501 entries
- All core files validated: config, scripts (14), core, tests, Docker, skills, config
- **Exclusions verified**: `.git` (0), `node_modules` non-playwright (0), `scripts/scripts` (excluded)
- **Skills**: 131 DrDeeks skills + Enterprise blueprint + OpenClaw built-in
- **Unified USB Skill**: `skills/drdeeks/unified-usb-skill.skill` (89 KB ZIP with 20 reference docs, 8 scripts)
- **Daily Auto-Pull**: Cron job `pull-drdeeks-skills-daily` at 2 AM UTC
- **Setup Wizard Integration**: Patched `hermes_cli/setup.py` with `_offer_launch_tui_and_docker()` and `_start_docker_container()`
- **Container Cron**: `container-init.sh` installs cron, adds daily pull at 2 AM
- **Tar Archiving**: Correct prefix handling with `-C /staging hemlock-minimal`
- **Playwright Tests**: 18/18 pass (health + gateway), 168 skipped (MCP auth)
- **MCP Loopback**: Internal port random (41213, 39925, etc.), requires proxy
- **Dockerfile.runtime** now in both root and `docker/` directory
```

