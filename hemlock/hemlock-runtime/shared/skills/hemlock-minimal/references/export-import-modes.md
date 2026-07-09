# Export/Import Modes

## Export Modes (Fixed Definitions)

| Mode | Includes | Excludes |
|------|----------|----------|
| **Minimal** | `agent.json`, `SOUL.md`, `IDENTITY.md`, `USER.md`, `TOOLS.md`, `MEMORY.md`, `STARTUP.md`, `HEARTBEAT.md`, `avatars/`, `tools/` | `config.yaml`, `.env`, `.secrets/`, `sessions/`, `memory/`, `skills/`, `logs/`, `media/`, `projects/` |
| **Standard** | Minimal + `config.yaml`, `.env`, `.secrets/`, `HEARTBEAT.md`, `skills/`, **latest 5 sessions/**, **latest 5 memory/** | Full `sessions/`, full `memory/`, `logs/`, `media/`, `projects/` |
| **Full** | **Entire volume** | Nothing |

**Usage:**
```bash
/entrypoint.sh agent-export <id> [minimal|standard|full] [dest]
/entrypoint.sh agent-import <src> <new_id> [mode]
/entrypoint.sh crew-export <name> [minimal|standard|full] [dest]
/entrypoint.sh crew-import <src> <new_name>
/entrypoint.sh agent-backup <id>
```

### Export Implementation Details

- **Minimal**: `tar -czf` with core identity + avatars/ + tools/ (NO config, NO .env)
- **Standard**: Minimal + config.yaml, .env, .secrets/, HEARTBEAT.md, skills/, `ls -t sessions/ | head -5`, `ls -t memory/ | head -5`
- **Full**: `tar -czf` everything in volume
### Step 1: Bootstrap skill-installer (the gateway skill)

```bash
git clone https://github.com/drdeeks/skills.git /tmp/drdeeks-skills
cd /tmp/drdeeks-skills

# Extract and install skill-installer to shared skills dir
python3 -c "
import zipfile, tempfile, shutil
from pathlib import Path
with zipfile.ZipFile('skill-installer.skill', 'r') as z:
    tmpdir = Path(tempfile.mkdtemp(prefix='si_'))
    z.extractall(tmpdir)
target = Path('/shared-skills') / 'skill-installer'
target.mkdir(parents=True, exist_ok=True)
for item in (tmpdir / 'skill-installer').rglob('*'):
    if item.is_file():
        dest = target / item.relative_to(tmpdir / 'skill-installer')
        dest.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(item, dest)
print('✓ skill-installer bootstrapped to', target)
"
```

### Step 2: Batch install all skills with embedded validation

The updated `skill-installer` includes **embedded validation** (no external `skill-creator-pro` dependency):

```bash
INSTALLER="/shared-skills/skill-installer/scripts/batch_install.py"
python3 "$INSTALLER" /tmp/drdeeks-skills \
    --target /shared-skills \
    --validate \
    --report /tmp/drdeeks-install-report.json
```

### Key Features of Embedded Validation

| Check | What It Validates |
|---|---|
| Frontmatter | Valid YAML, required keys (name, description), hyphen-case naming |
| Structure | SKILL.md, scripts/ (2+ files), references/ (3+ files) |
| Agnostic paths | No hardcoded `/home/user/`, `~/.config/`, `/tmp/` paths |
| Content quality | No `TODO/FIXME/WIP/TBD` placeholder markers |
| Sources | External services have Sources section with official docs |
| Syntax | Python (ast.parse), Bash (bash -n), Node (node --check) |
| Pricing | Warns on pricing mentions without Pricing section |

### Validation Pipeline

```
.skill file → Format Detection → Extract → Embedded Validation → Install → Post-Check → Receipt
                              ↓              ↓
                         Frontmatter    Content Quality
                         Structure      Sources
                         Agnostic       Syntax
```

### Rollback on Failure

```bash
python3 /shared-skills/skill-installer/scripts/install_skill.py \
    /path/to/skill.skill \
    --target /shared-skills \
    --validate \
    --rollback-on-failure
```

### Emergency Install (Skip Validation)

```bash
python3 /shared-skills/skill-installer/scripts/install_skill.py \
    /path/to/skill.skill \
    --target /shared-skills \
    --no-validate
```

---

## Export/Import Modes (Detailed)

| Mode | Includes | Use Case | Size |
|---|---|---|---|
| **MINIMAL** | agent.json, SOUL.md, config.yaml, .env*, TOOLS.md, AGENTS.md | Quick config backup | ~KB |
| **STANDARD** | MINIMAL + tools/, skills/, .secrets/, recent memory/sessions/, configs/ | Regular backup | ~MB |
| **FULL** | Everything including .secrets/, logs/, media/, projects/, all sessions | Migration/disaster recovery | ~100MB+ |

### Usage

```bash
# Export agent
./scripts/agent-export.sh --id analyst-1 --mode standard --dest ./backup

# Import agent (recreates volume + extracts)
./scripts/agent-import.sh --source ./backup/analyst-1.tar.gz --id analyst-1

# Export crew (includes member agents)
./scripts/crew-export.sh --name trading-desk --mode full --dest ./backup

# Full system backup
./scripts/hemlock-full/backup.sh

# Restore full system
./scripts/hemlock-full/restore.sh hemlock-backup-20260612-143022.tar.gz
```

### Export Script Behavior

- **MINIMAL**: `tar -czf` with `--include=agent.json --include=SOUL.md --include=config.yaml --include=.env* --include=TOOLS.md --include=AGENTS.md`
- **STANDARD**: Adds `tools/`, `skills/`, `.secrets/`, `memory/`, `sessions/`, `config/`
- **FULL**: `rsync -av --exclude=node_modules --exclude=.git --exclude=__pycache__ --exclude='*.pyc'`

---

