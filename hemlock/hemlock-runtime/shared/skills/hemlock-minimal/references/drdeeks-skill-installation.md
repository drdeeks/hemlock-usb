# DrDeeks Skills Installation Protocol

The DrDeeks skills repository (https://github.com/drdeeks/skills.git) contains `.skill` files that are **zip archives** containing the full skill directory structure.

## Bootstrap Process

**The `skill-installer.skill` is the bootstrap skill** that installs all others.

### Step 1: Clone and Bootstrap

```bash
git clone https://github.com/drdeeks/skills.git /tmp/drdeeks-skills
cd /tmp/drdeeks-skills

# Extract and install skill-installer (bootstrap)
python3 -c "
import zipfile, tempfile, shutil
from pathlib import Path
with zipfile.ZipFile('skill-installer.skill', 'r') as z:
    tmpdir = Path(tempfile.mkdtemp(prefix='si_'))
    z.extractall(tmpdir)
target = Path('$OPENCODE_SKILLS_DIR') / 'skill-installer'
target.mkdir(parents=True, exist_ok=True)
for item in (tmpdir / 'skill-installer').rglob('*'):
    if item.is_file():
        dest = target / item.relative_to(tmpdir / 'skill-installer')
        dest.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(item, dest)
print('✓ skill-installer installed to', target)
"
```

### Step 2: Verify Installation

```bash
ls $OPENCODE_SKILLS_DIR/skill-installer/
# SKILL.md  scripts/  references/

python3 $OPENCODE_SKILLS_DIR/skill-installer/scripts/install_skill.py --help
```

### Step 3: Batch Install All Skills

```bash
python3 $OPENCODE_SKILLS_DIR/skill-installer/scripts/batch_install.py \
    /tmp/drdeeks-skills \
    --target $OPENCODE_SKILLS_DIR \
    --validate \
    --report /tmp/install-report.json
```

### Step 4: Check Report

```bash
python3 -c "
import json
with open('/tmp/install-report.json') as f:
    r = json.load(f)
print(f'Total: {r[\"summary\"][\"total\"]}')
print(f'Successes: {r[\"summary\"][\"successes\"]}')
print(f'Failures: {r[\"summary\"][\"failures\"]}')
for d in r['details']:
    status = '✓' if d['success'] else '✗'
    print(f'  {status} {d[\"skill_name\"]}')
"
```

## Validation Pipeline (Automatic)

Every skill goes through:

```
.skill file → Format Detection → Extract → Validate (skill-creator-pro) → Install → Post-Check → Receipt
```

**Validation checks (weighted):**
| Check | Weight | Description |
|-------|--------|-------------|
| Frontmatter | 20% | Valid YAML, required keys, naming |
| Structure | 15% | SKILL.md, scripts/, references/, assets/ |
| Content | 20% | No placeholders, no TODOs |
| Agnostic | 15% | No hardcoded paths, cross-platform |
| Redundancy | 10% | No overlap with existing skills |
| Sources | 10% | Documented, verified |
| Scripts | 5% | Working, tested |
| Accessibility | 5% | Clear triggers |

## Hemlock Integration

Set in your `.env` or entrypoint:

```bash
export OPENCODE_SKILLS_DIR="/shared-skills"  # Shared read-only volume
```

The `/shared-skills` volume is symlinked into each agent workspace at creation time.

## Complete One-Liner

```bash
#!/usr/bin/env bash
# install-all-drdeeks-skills.sh

set -euo pipefail
REPO_DIR="/tmp/drdeeks-skills"
SKILLS_DIR="${OPENCODE_SKILLS_DIR:-$HOME/.config/opencode/skills}"

[[ -d "$REPO_DIR" ]] || git clone https://github.com/drdeeks/skills.git "$REPO_DIR"

# Bootstrap
python3 -c "
import zipfile, tempfile, shutil
from pathlib import Path
with zipfile.ZipFile('$REPO_DIR/skill-installer.skill', 'r') as z:
    tmpdir = Path(tempfile.mkdtemp(prefix='si_'))
    z.extractall(tmpdir)
target = Path('$SKILLS_DIR') / 'skill-installer'
target.mkdir(parents=True, exist_ok=True)
for item in (tmpdir / 'skill-installer').rglob('*'):
    if item.is_file():
        dest = target / item.relative_to(tmpdir / 'skill-installer')
        dest.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(item, dest)
print('✓ Bootstrap installed')
"

# Batch install
python3 "$SKILLS_DIR/skill-installer/scripts/batch_install.py" "$REPO_DIR" \
    --target "$SKILLS_DIR" \
    --validate \
    --report /tmp/drdeeks-install-report.json
```