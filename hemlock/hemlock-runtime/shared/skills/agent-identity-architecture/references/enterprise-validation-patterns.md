# Enterprise Skill Validation Patterns
**Patterns and fixes discovered during skill-creator enterprise pipeline validation (2026-07-05)**

## Common Failures & Fixes

### 1. Frontmatter Tags Must Be Quoted
```yaml
# ❌ FAILS - unquoted
tags:
  - autonomous-crew
  - agent-identity

# ✅ PASSES - quoted
tags:
  - "autonomous-crew"
  - "agent-identity"
```

### 2. Hardcoded Paths Rejected
```python
# ❌ FAILS - literal /home/agents or /home/<user>
WORKSPACE_ROOT = Path("/home/agents")
DEFAULT = "/home/<user>/.hermes/skills/..."

# ✅ PASSES - derived from $HOME or env
_DEFAULT_ROOT = str(Path.home() / "agents")
WORKSPACE_ROOT = Path(os.environ.get("WORKSPACE_ROOT", _DEFAULT_ROOT))
identity_skill_path = os.environ.get("AGENT_IDENTITY_SKILL", str(Path.home() / ".hermes" / "skills" / "devops" / "agent-identity-architecture"))
```

### 3. Help Text Examples Also Scanned
```python
# ❌ FAILS - examples in docstrings
Environment:
  WORKSPACE_ROOT      Root directory (default: /home/agents)

# ✅ PASSES - use $HOME or variable syntax
Environment:
  WORKSPACE_ROOT      Root directory (default: $HOME/agents)
```

### 4. Template Files Must Be Read-Only (0444)
```bash
# Auto-fixed by pipeline but good to set initially
chmod 0444 references/templates/**/*
```

### 5. Scripts Need Shebang + --help
```bash
#!/usr/bin/env python3  # or bash
# ...
parser.add_argument("--help", "-h", action="store_true")
if args.help:
    print("Usage: ...")
    sys.exit(0)
```

### 6. References Must Be .md/.txt/.html/.pdf (Not .yaml)
```bash
# ❌ FAILS - .yaml in references/
references/crew-phases.yaml

# ✅ PASSES - .md in references/, .yaml in references/templates/
references/crew-phases.md
references/templates/crew/crew-phases.yaml
```

### 7. templates/ Directory Must Be at references/templates/
```bash
# ❌ FAILS - templates/ at skill root
autonomous-crew/templates/

# ✅ PASSES - templates/ under references/
autonomous-crew/references/templates/
```

### 8. __init__.py Required with Exports
```python
#!/usr/bin/env python3
__skill__ = "skill-name"
__version__ = "1.0.0"
__description__ = "Description"
__category__ = "devops"
__tags__ = [...]
__depends_on__ = [...]
```

### 9. All Scripts Must Pass test_script.py
- Syntax check (py_compile or bash -n)
- Shebang present
- --help exits 0 with usage text
- No --dry-run flag required but warned

## Validation Pipeline Gates

| Gate | Requirement | Notes |
|------|-------------|-------|
| 1. SKILL.md frontmatter | 7+ tags, description, no REPLACE_ME | Enterprise mode |
| 2. scripts/ | 5+ substantive scripts | Non-trivial, >50 lines |
| 3. references/ | 7+ substantive docs | .md/.txt/.html/.pdf only |
| 4. validate.py | Initial informational | Auto-fix runs next |
| 5. auto_fix.py | Safe moves only | Never deletes |
| 6. re-validate | HARD GATE | Must pass 0 FAIL |
| 7. test_script.py | BLOCKING | All scripts pass |
| 8. verify_sources.py | External URLs | If any |
| 9. package_skills.py | Creates .skill archive | Version bump |
| 10. extract-verify | Fresh archive integrity | Hashes match source |

## Pro Tips

1. **Run validation early and often** — `skill_enhance.py update --path <skill> --noninteractive`
2. **Fix structural issues first** — templates location, __init__.py, references format
3. **Use $HOME/Path.home()** — validator rejects any /home/... literal
4. **Quote all YAML strings** — especially tags, depends_on, provides
5. **Move .yaml to references/templates/** — references only allows doc formats
6. **chmod 0444 templates** — pipeline auto-fixes but pre-setting avoids warning
7. **Add --help to every script** — even non-mutating ones get warned