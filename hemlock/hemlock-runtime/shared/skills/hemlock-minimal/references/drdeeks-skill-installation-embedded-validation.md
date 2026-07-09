# DrDeeks Skill Installation with Embedded Validation

## Overview

Skills from https://github.com/drdeeks/skills.git are distributed as `.skill` zip archives. The installation follows a **bootstrap pattern**:

1. **Bootstrap `skill-installer`** — the gateway skill that installs all others
2. **Batch install all skills** — using embedded validation (no external `skill-creator-pro` dependency)

## Bootstrap Process

```bash
# 1. Clone repo
git clone https://github.com/drdeeks/skills.git /tmp/drdeeks-skills
cd /tmp/drdeeks-skills

# 2. Extract and install skill-installer to shared skills dir
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

## Embedded Validation (Key Update)

The `skill-installer` now includes **fully embedded validation** — no external `skill-creator-pro` dependency needed.

### Validation Pipeline

```
.skill file → Format Detection → Extract → Embedded Validation → Install → Post-Check → Receipt
                              ↓              ↓
                         Frontmatter    Content Quality
                         Structure      Sources
                         Agnostic       Syntax
```

### Embedded Validation Checks

| Check | What It Validates | Weight |
|---|---|---|
| Frontmatter | Valid YAML, required keys (name, description), hyphen-case naming | 20% |
| Structure | SKILL.md, scripts/ (2+ files), references/ (3+ files) | 15% |
| Agnostic paths | No hardcoded `/home/user/`, `~/.config/`, `/tmp/` paths | 15% |
| Content quality | No `TODO/FIXME/WIP/TBD` placeholder markers | 20% |
| Sources | External services have Sources section with official docs | 10% |
| Scripts | Python (ast.parse), Bash (bash -n), Node (node --check) | 5% |
| Redundancy | No overlap with existing skills (<0.7 similarity) | 10% |
| Pricing | Warns on pricing mentions without Pricing section | Warning |

### Batch Install All Skills

```bash
INSTALLER="/shared-skills/skill-installer/scripts/batch_install.py"
python3 "$INSTALLER" /tmp/drdeeks-skills \
    --target /shared-skills \
    --validate \
    --report /tmp/drdeeks-install-report.json
```

### Validation Output

```json
{
  "operation": "batch_install",
  "timestamp": "2026-06-12T23:41:26.807399+00:00",
  "status": "success",
  "summary": {
    "total": 100,
    "successes": 99,
    "failures": 1
  },
  "details": [
    {"skill_name": "skill-a", "success": true, ...},
    ...
  ]
}
```

### Skills That "Fail" Validation (Expected)

The `skill-installer` itself will show validation warnings because its SKILL.md documents validation rules that include `TODO/FIXME` examples in a table. This is expected — use `--no-validate` for skill-installer itself.

## Installation in Hemlock

### In Container (at build time)

```dockerfile
COPY scripts/populate-skills.sh /scripts/populate-skills.sh
RUN chmod +x /scripts/populate-skills.sh
```

### At Runtime (entrypoint.sh)

```bash
populate-skills [source_dir] [target_volume]
# Default: source=/skills-source, target=hemlock-shared-skills
```

The script:
1. Bootstraps skill-installer from `skill-installer.skill`
2. Runs batch install with validation
3. Generates `install-report.json`
4. Lists installed skills

### Populate Skills Command

```bash
/entrypoint.sh populate-skills [/skills-source]
# or
docker exec hemlock-runtime /entrypoint.sh populate-skills
```

## Key Files in skill-installer

| File | Purpose |
|---|---|
| `SKILL.md` | Skill definition with embedded validation docs |
| `scripts/install_skill.py` | Main installer with embedded `validate_skill_embedded()` |
| `scripts/batch_install.py` | Batch installer |
| `scripts/extract_skill.py` | .skill archive extraction |
| `scripts/validate_install.py` | Post-install validation |

## Embedded Validation Code

The `validate_skill_embedded()` function in `install_skill.py` includes:

- `validate_frontmatter()` — YAML parsing, required keys, naming
- `check_agnostic_compliance()` — Hardcoded path detection
- `check_structure()` — SKILL.md, scripts/, references/ presence
- `check_content_quality()` — `TODO/FIXME/WIP` detection
- `check_sources_verification()` — External service docs
- `check_script_syntax()` — Python/Bash/Node syntax
- `check_pricing_accuracy()` — Pricing section warnings

All checks use stdlib only — zero pip dependencies.

## Rollback on Failure

```bash
python3 /shared-skills/skill-installer/scripts/install_skill.py \
    /path/to/skill.skill \
    --target /shared-skills \
    --validate \
    --rollback-on-failure
```

If validation fails post-install, the backup is restored automatically.

## Emergency Install (Skip Validation)

```bash
python3 /shared-skills/skill-installer/scripts/install_skill.py \
    /path/to/skill.skill \
    --target /shared-skills \
    --no-validate
```

## Legacy DrDeeks Installation (Without Embedded Validation)

For reference, the old pattern required `skill-creator-pro`:

```bash
# Old pattern (deprecated)
python3 /path/to/skill-creator-pro/scripts/validate_pro.py /path/to/skill
```

The embedded validation replaces this entirely — no external dependency needed.

## References

- https://github.com/drdeeks/skills.git
- skill-installer.skill (bootstrap)
- All 100+ .skill files are zip archives with SKILL.md at root