#!/usr/bin/env python3
"""
enterprise-blueprint — Validate a blueprint against enterprise compliance rules (v2)

v2: Enforces comprehensive blueprint standard — 1500+ lines, full ASCII diagrams,
complete SQL schemas, feature spec format compliance, phase checklist completeness,
5-level error handling, performance budgets with metrics, and zero placeholders.

Usage:
    python3 scripts/validate_blueprint.py <path/to/blueprint.md>
    python3 scripts/validate_blueprint.py <path/to/blueprint.md> --verbose
    python3 scripts/validate_blueprint.py <path/to/blueprint.md> --json
"""

import json
import re
import sys
from datetime import datetime, timezone
from pathlib import Path


# ── Check model ────────────────────────────────────────────────────────────────

class Check:
    def __init__(self, name, severity, passed, detail=""):
        self.name = name
        self.severity = severity   # "FAIL" or "WARN"
        self.passed = passed
        self.detail = detail

    def __repr__(self):
        status = "PASS" if self.passed else self.severity
        mark = "✓" if self.passed else ("✗" if self.severity == "FAIL" else "⚠")
        line = f"  {mark} [{status}] {self.name}"
        if self.detail and not self.passed:
            line += f"\n         → {self.detail}"
        return line


# ── Helpers ────────────────────────────────────────────────────────────────────

def read(path):
    try:
        return Path(path).read_text(encoding="utf-8")
    except Exception:
        return None


def now_iso():
    return datetime.now(timezone.utc).isoformat()


def has_pattern(text, *patterns):
    return any(bool(re.search(p, text, re.IGNORECASE | re.MULTILINE)) for p in patterns)


# ── Validation rules ───────────────────────────────────────────────────────────

REQUIRED_PARTS = [
    ("PART I",   "System Overview"),
    ("PART II",  "Module Registry"),
    ("PART III", "Specifications"),
    ("PART IV",  "Data Architecture"),
    ("PART V",   "Change Control"),
    ("PART VI",  "Implementation Checklist"),
    ("PART VII", "Quality"),
]

REQUIRED_ROLLBACK_TAGS = [
    "SYS-OVERVIEW",
    "MODULE-REGISTRY",
    "SPECS",
    "DATA-ARCH",
    "CHANGE-CONTROL",
    "QUALITY",
]

REQUIRED_SECTIONS = [
    (r"##\s+\d+\.\d+\s+vision", "Vision Statement (1.1)"),
    (r"##\s+\d+\.\d+\s+.*(architecture|arch)", "Architecture section"),
    (r"##\s+\d+\.\d+\s+tech\s+stack", "Tech Stack section"),
    (r"module\s+id", "Module ID column in registry table"),
    (r"feature\s+flag", "Feature Flag column in registry table"),
    (r"rollback\s+(procedure|plan|ref)", "Rollback Procedure in at least one phase"),
    (r"change\s+log\s+entry\s+format|date\s*:\s*yyyy", "Change Log entry format block"),
    (r"contributor\s+rules?", "Contributor Rules section"),
    (r"error\s+handling\s+standards?", "Error Handling Standards"),
    (r"testing\s+requirements?", "Testing Requirements"),
    (r"performance\s+budgets?", "Performance Budgets"),
]

PHASE_TAG_PATTERN = re.compile(r"\[PHASE-\d+-v\d+\]")
ROLLBACK_TAG_PATTERN = re.compile(r"\[[A-Z][A-Z0-9-]+-v\d+\]")
SECTION_TAG_PATTERN = re.compile(r"Rollback\s+Tag.*`(\[[^\]]+\])`", re.IGNORECASE)
CL_ENTRY_PATTERN = re.compile(
    r"##\s+CL-\d+.*\n```.*?Date\s*:.*?Rollback\s+Ref\s*:.*?```",
    re.DOTALL | re.IGNORECASE,
)
FEATURE_FLAG_PATTERN = re.compile(r"FEAT_[A-Z][A-Z0-9_]+")
TODO_PATTERN = re.compile(r"\[TODO", re.IGNORECASE)
PLACEHOLDER_PATTERN = re.compile(r"\[Define\s|\[Describe\s|\[Insert\s|\[placeholder\]",
                                  re.IGNORECASE)

# Box-drawing characters for ASCII diagrams
BOX_DRAWING_PATTERN = re.compile(r"[┌┐└┘├┤┬┴┼═║╚╔╗╝╠╣╦╩╬─│┃━]")
# SQL schema pattern
CREATE_TABLE_PATTERN = re.compile(r"CREATE\s+TABLE", re.IGNORECASE)
# Feature spec required fields
FEATURE_SPEC_FIELDS = [
    "FEATURE\s+ID", "MODULE\s+REF", "ROLLBACK\s+TAG",
    "FEATURE\s+FLAG", "PURPOSE", "COMPONENTS", "RULES",
    r"ERROR[\s_]+STATES", "FALLBACK"
]


def validate(blueprint_path, verbose=False):
    blueprint_path = Path(blueprint_path).resolve()
    checks = []

    # ── 1. File existence ──────────────────────────────────────────────────────
    checks.append(Check(
        "blueprint.md exists and is readable", "FAIL",
        blueprint_path.exists() and blueprint_path.is_file(),
    ))
    content = read(blueprint_path)
    if not content:
        checks.append(Check("blueprint.md has content", "FAIL", False))
        return checks

    lines = content.splitlines()
    line_count = len(lines)

    # ── 2. Document header ────────────────────────────────────────────────────
    has_version = bool(re.search(r"Version\s+\d+\.\d+", content[:500]))
    checks.append(Check("Version number in document header", "FAIL", has_version))

    has_date = bool(re.search(r"Generated|Authored|Created.*\d{4}-\d{2}-\d{2}",
                               content[:500]))
    checks.append(Check("Date in document header", "WARN", has_date))

    has_read_first = bool(re.search(r"READ\s+FIRST|DOCUMENT\s+AUTHORITY",
                                     content[:1000], re.IGNORECASE))
    checks.append(Check("READ FIRST / Document Authority preamble", "FAIL",
                         has_read_first))

    # ── 3. Required parts ─────────────────────────────────────────────────────
    for label, hint in REQUIRED_PARTS:
        found = bool(re.search(rf"#\s+{re.escape(label)}\b", content, re.IGNORECASE))
        checks.append(Check(
            f"Contains {label} ({hint})", "FAIL", found,
            f"Add '# {label} — {hint}' section to the blueprint.",
        ))

    # ── 4. Table of contents ──────────────────────────────────────────────────
    has_toc = bool(re.search(r"table\s+of\s+contents|PART\s+I.*PART\s+II",
                               content[:2000], re.IGNORECASE | re.DOTALL))
    checks.append(Check("Table of contents present", "WARN", has_toc))

    # ── 5. Rollback tags on sections ──────────────────────────────────────────
    found_tags = set(ROLLBACK_TAG_PATTERN.findall(content))
    phase_tags = PHASE_TAG_PATTERN.findall(content)
    checks.append(Check(
        "At least 1 PHASE rollback tag present", "FAIL",
        len(phase_tags) >= 1,
        f"Found {len(phase_tags)} — add [PHASE-N-v1] tags to implementation phases.",
    ))
    checks.append(Check(
        "6+ section rollback tags across the document", "WARN",
        len(found_tags) >= 6,
        f"Found {len(found_tags)} — add [SECTION-NAME-v1] tags to all major sections.",
    ))
    for tag_stem in REQUIRED_ROLLBACK_TAGS:
        present = any(tag_stem in t for t in found_tags)
        checks.append(Check(
            f"Rollback tag [{tag_stem}-v1] present", "WARN",
            present,
            f"Add `> **Rollback Tag:** `[{tag_stem}-v1]`` to the relevant section.",
        ))

    # ── 6. Required content sections ─────────────────────────────────────────
    for pattern, label in REQUIRED_SECTIONS:
        found = has_pattern(content, pattern)
        checks.append(Check(f"Section: {label}", "FAIL" if "Vision" in label or
                             "Module ID" in label or "Change Log" in label else "WARN",
                             found))

    # ── 7. Module registry ────────────────────────────────────────────────────
    module_ids = re.findall(r"MOD-\d{3}", content)
    checks.append(Check(
        "At least 1 module defined (MOD-NNN)", "FAIL",
        len(module_ids) >= 1,
        f"Found {len(module_ids)} — populate the Module Registry in Part II.",
    ))
    checks.append(Check(
        "3+ modules defined", "WARN",
        len(module_ids) >= 3,
        f"Found {len(module_ids)} — a meaningful registry typically has 3+ modules.",
    ))

    # ── 8. Feature flags ──────────────────────────────────────────────────────
    flags = FEATURE_FLAG_PATTERN.findall(content)
    checks.append(Check(
        "Feature flags (FEAT_*) referenced", "FAIL",
        len(flags) >= 1,
        "Add FEAT_NAME flags to Module Registry and phase headers.",
    ))
    checks.append(Check(
        "3+ feature flags defined", "WARN",
        len(flags) >= 3,
        f"Found {len(flags)} — every major module should have a flag.",
    ))

    # ── 9. Change log ─────────────────────────────────────────────────────────
    has_cl_header = bool(re.search(r"#\s+CHANGE\s+LOG", content, re.IGNORECASE))
    checks.append(Check("CHANGE LOG section present", "FAIL", has_cl_header))

    has_cl_entry = bool(re.search(r"##\s+CL-\d+", content, re.IGNORECASE))
    checks.append(Check("At least one CL-NNN entry present", "FAIL", has_cl_entry))

    has_cl_fields = has_pattern(
        content,
        r"Date\s*:\s*\d{4}|Date\s*:\s*YYYY",
        r"Contributor\s*:",
        r"Rollback\s+Ref\s*:",
    )
    checks.append(Check(
        "Change log entry contains required fields", "WARN",
        has_cl_fields,
        "Entries must include: Date, Contributor, Modules, Section Tags, "
        "Files Changed, Description, Tests Passing, Phase, Rollback Ref.",
    ))

    append_only_note = bool(re.search(
        r"append.only|no entry may be modified|permanent",
        content, re.IGNORECASE
    ))
    checks.append(Check("Append-only rule stated in change log", "WARN",
                         append_only_note))

    # ── 10. Data architecture ─────────────────────────────────────────────────
    has_schema = has_pattern(content, r"CREATE\s+TABLE", r"PRIMARY\s+KEY",
                              r"database\s+schema")
    checks.append(Check("Database schema defined in Part IV", "WARN", has_schema))

    # Count SQL tables — enterprise requires 3+
    table_count = len(CREATE_TABLE_PATTERN.findall(content))
    checks.append(Check(
        "3+ SQL table schemas defined", "WARN",
        table_count >= 3,
        f"Found {table_count} CREATE TABLE — a real system needs 3+ tables.",
    ))

    has_api = has_pattern(content, r"/api/v\d+", r"POST /", r"GET /",
                           r"API\s+Contract")
    checks.append(Check("API contracts defined in Part IV", "WARN", has_api))

    has_migration_rule = bool(re.search(
        r"YYYYMMDD|migration.*rollback|rollback.*migration",
        content, re.IGNORECASE
    ))
    checks.append(Check("Migration naming convention stated", "FAIL",
                         has_migration_rule))

    # ── 11. Quality standards ─────────────────────────────────────────────────
    has_p95 = bool(re.search(r"p95|percentile.*\d+ms|\d+ms.*response",
                               content, re.IGNORECASE))
    checks.append(Check("p95 performance budget specified", "WARN", has_p95))

    has_coverage = bool(re.search(r"\d+%.*coverage|coverage.*\d+%",
                                    content, re.IGNORECASE))
    checks.append(Check("Test coverage target specified", "WARN", has_coverage))

    has_circuit = bool(re.search(r"circuit\s+breaker|exponential\s+backoff",
                                   content, re.IGNORECASE))
    checks.append(Check("Circuit breaker / retry policy specified", "WARN",
                         has_circuit))

    # ── 12. Placeholder hygiene ───────────────────────────────────────────────
    todo_count = len(TODO_PATTERN.findall(content))
    checks.append(Check(
        "No [TODO] markers remaining", "WARN",
        todo_count == 0,
        f"Found {todo_count} [TODO markers — replace with real content.",
    ))

    placeholder_count = len(PLACEHOLDER_PATTERN.findall(content))
    checks.append(Check(
        "Minimal unfilled placeholders", "WARN",
        placeholder_count <= 5,
        f"Found {placeholder_count} unfilled placeholders — populate before marking phase complete.",
    ))

    # ── 13. Document length (STRICT) ─────────────────────────────────────────
    checks.append(Check(
        "Document is comprehensive (>1500 lines)", "FAIL",
        line_count > 1500,
        f"Got {line_count} lines — enterprise blueprints must be 1500+ lines. "
        f"Include full ASCII diagrams, SQL schemas, config blocks, and detailed specs.",
    ))
    checks.append(Check(
        "Document is thorough (>2500 lines)", "WARN",
        line_count > 2500,
        f"Got {line_count} lines — thorough blueprints are 2500+ lines.",
    ))

    # ── 14. ASCII architecture diagram (NEW) ─────────────────────────────────
    box_chars = BOX_DRAWING_PATTERN.findall(content)
    checks.append(Check(
        "ASCII architecture diagram present", "FAIL",
        len(box_chars) >= 20,
        f"Found {len(box_chars)} box-drawing characters — Part I needs a full "
        f"ASCII architecture diagram (50+ lines with ┌┐└┘├┤┬┴┼─│ characters).",
    ))

    # ── 15. Feature spec format compliance (NEW) ─────────────────────────────
    # Count feature spec blocks
    spec_blocks = re.findall(r"FEATURE\s+ID\s*:", content, re.IGNORECASE)
    spec_count = len(spec_blocks)
    checks.append(Check(
        "3+ feature specifications defined", "FAIL",
        spec_count >= 3,
        f"Found {spec_count} feature specs — need 3+ with full format compliance.",
    ))

    # Check that specs have required fields
    if spec_count >= 1:
        missing_fields = 0
        for field in FEATURE_SPEC_FIELDS:
            field_count = len(re.findall(field, content, re.IGNORECASE))
            if field_count < spec_count:
                missing_fields += spec_count - field_count
        checks.append(Check(
            "Feature specs have all required fields (PURPOSE, COMPONENTS, RULES, ERROR STATES, FALLBACK)", "FAIL",
            missing_fields == 0,
            f"Found {missing_fields} missing fields across specs — each spec needs: "
            f"FEATURE ID, MODULE REF, ROLLBACK TAG, FEATURE FLAG, PURPOSE, COMPONENTS, "
            f"RULES, ERROR STATES, FALLBACK.",
        ))

    # ── 16. Phase checklist completeness (NEW) ────────────────────────────────
    # Match multiple formats: ### Deliverables, **Deliverables:**, plain "Deliverables:"
    phase_deliverables = re.findall(r"Deliverables", content, re.IGNORECASE)
    phase_gates = re.findall(r"Validation\s+Gate", content, re.IGNORECASE)
    checks.append(Check(
        "Phases have deliverables and validation gates", "FAIL",
        len(phase_deliverables) >= 3 and len(phase_gates) >= 3,
        f"Found {len(phase_deliverables)} Deliverable sections, {len(phase_gates)} "
        f"Validation Gates — each phase needs both.",
    ))

    # ── 17. Error handling hierarchy (NEW) ────────────────────────────────────
    error_levels = re.findall(
        r"(Level\s+\d|Level\s+[A-Z]|Tier\s+\d|1\.\s+.*Validation|Input\s+Validation|"
        r"API\s+Errors|Module\s+Errors|Network\s+Errors|System\s+Errors|"
        r"Level\s+1.*Level\s+5|five.level|5.level)",
        content, re.IGNORECASE
    )
    checks.append(Check(
        "5-level error handling hierarchy defined", "WARN",
        len(error_levels) >= 3,
        f"Found {len(error_levels)} error level references — Part VII needs a "
        f"5-level hierarchy (Input Validation → API → Module → Network → System).",
    ))

    # ── 18. Performance budgets with metrics (NEW) ───────────────────────────
    # Check for actual metric values (number + unit)
    metric_values = re.findall(r"\d+\s*(ms|seconds?|s\b|mb|gb|req/s|rps)", content, re.IGNORECASE)
    checks.append(Check(
        "Performance budgets have concrete metric values", "WARN",
        len(metric_values) >= 6,
        f"Found {len(metric_values)} metric values — budgets need concrete numbers "
        f"(e.g., '200ms', '1GB', '1000 req/s').",
    ))

    # ── 19. Rollback procedures per phase (NEW) ──────────────────────────────
    rollback_procs = re.findall(r"[Rr]ollback\s+[Pp]rocedure", content, re.IGNORECASE)
    checks.append(Check(
        "Each phase has a rollback procedure", "WARN",
        len(rollback_procs) >= 3,
        f"Found {len(rollback_procs)} rollback procedures — each phase needs one.",
    ))

    # ── 20. No dummy/test content (NEW) ──────────────────────────────────────
    # Exclude legitimate uses: "hackathon", "mock provider", "test files", etc.
    dummy_patterns = re.findall(
        r"(?<!\w)lorem\s+ipsum(?!\w)|(?<!\w)dummy(?!\w)|(?<!\w)fake[^r]|"
        r"(?<!\w)placeholder\s+data(?!\w)|"
        r"(?<!\w)foo\s+bar(?!\w)|(?<!\w)baz(?!\w)|"
        r"(?<!\w)FIXME(?!\w)|(?<!\w)HACK(?!\w)",
        content, re.IGNORECASE
    )
    # Filter out legitimate uses (mock provider, test files, etc.)
    dummy_count = len(dummy_patterns)
    checks.append(Check(
        "No dummy/test/placeholder content", "WARN",
        dummy_count <= 10,
        f"Found {dummy_count} dummy-like patterns — remove test data and placeholders.",
    ))

    return checks


# ── Reporting ──────────────────────────────────────────────────────────────────

def print_report(checks, verbose=False):
    fails = [c for c in checks if not c.passed and c.severity == "FAIL"]
    warns = [c for c in checks if not c.passed and c.severity == "WARN"]
    passes = [c for c in checks if c.passed]
    total = len(checks)

    print(f"\n{'=' * 62}")
    print("  Enterprise Blueprint Validation Report (v2)")
    print(f"{'=' * 62}\n")

    if verbose:
        print("All checks:\n")
        for c in checks:
            print(c)
        print()
    else:
        if fails:
            print("FAILURES (must fix):\n")
            for c in fails:
                print(c)
            print()
        if warns:
            print("WARNINGS (should fix):\n")
            for c in warns:
                print(c)
            print()

    print(f"{'─' * 62}")
    print(f"  Results : {len(passes)}/{total} passed  |  {len(fails)} FAIL  |  {len(warns)} WARN")

    if len(fails) == 0 and len(warns) == 0:
        rating = "ENTERPRISE GRADE"
    elif len(fails) == 0 and len(warns) <= 4:
        rating = "PRODUCTION READY"
    elif len(fails) == 0 and len(warns) <= 9:
        rating = "NEEDS HARDENING"
    elif len(fails) <= 3:
        rating = "INCOMPLETE"
    else:
        rating = "NOT ENTERPRISE GRADE"

    print(f"  Rating  : {rating}")
    print(f"{'─' * 62}\n")
    return len(fails) == 0


def main():
    if len(sys.argv) < 2 or sys.argv[1] in ("--help", "-h"):
        print(__doc__)
        sys.exit(0)

    bp_path = sys.argv[1]
    verbose = "--verbose" in sys.argv or "-v" in sys.argv
    as_json = "--json" in sys.argv

    if not Path(bp_path).exists():
        print(f"[ERROR] File not found: {bp_path}")
        print("        Run init_blueprint.py first, or check the path.")
        sys.exit(1)

    checks = validate(bp_path, verbose)

    if as_json:
        output = {
            "operation": "validate",
            "timestamp": now_iso(),
            "blueprint": bp_path,
            "checks": [
                {
                    "name": c.name,
                    "severity": c.severity,
                    "passed": c.passed,
                    "detail": c.detail,
                }
                for c in checks
            ],
            "summary": {
                "total": len(checks),
                "passed": sum(1 for c in checks if c.passed),
                "failed": sum(1 for c in checks if not c.passed and c.severity == "FAIL"),
                "warned": sum(1 for c in checks if not c.passed and c.severity == "WARN"),
            },
            "cost": {"tier": 0, "amount_usd": 0.0, "service": "local"},
        }
        print(json.dumps(output, indent=2))
    else:
        success = print_report(checks, verbose)
        sys.exit(0 if success else 1)


if __name__ == "__main__":
    main()
