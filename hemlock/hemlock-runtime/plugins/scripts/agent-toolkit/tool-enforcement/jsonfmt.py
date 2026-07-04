#!/usr/bin/env python3
"""
jsonfmt — Enterprise JSON formatter, validator, and fixer.

Safely formats, validates, and repairs JSON/JSON5 files.
Backs up before any modification. Reports all changes.

Usage:
    jsonfmt <file>                    Format in-place (default: 4-space indent)
    jsonfmt <file> --check            Validate only, exit 1 if broken
    jsonfmt <file> --indent 2         Custom indentation
    jsonfmt <file> --tabs             Use tabs instead of spaces
    jsonfmt <file> --compact           Minified output
    jsonfmt <file> --json5            Allow JSON5 (comments, trailing commas)
    jsonfmt <file> --fix              Auto-fix common issues before formatting
    jsonfmt <file> --output out.json  Write to different file
    jsonfmt <file> --diff             Show diff without modifying
    jsonfmt <file> --backup-dir /tmp  Custom backup location
    cat file.json | jsonfmt -         Read from stdin

Safety:
    - Always backs up before in-place modification
    - Never modifies files that are already valid and formatted
    - Reports every change made
    - Exit codes: 0=ok, 1=invalid, 2=error
"""

import json
import sys
import os
import re
import shutil
import argparse
import subprocess
from pathlib import Path
from datetime import datetime
from typing import Optional, Tuple


def strip_json5(content: str) -> str:
    """Remove JSON5 features (comments, trailing commas, single quotes, unquoted keys)."""
    lines = content.split('\n')
    result = []
    for line in lines:
        # Remove single-line comments (but not inside strings)
        in_string = False
        escape = False
        cleaned = []
        i = 0
        while i < len(line):
            ch = line[i]
            if escape:
                cleaned.append(ch)
                escape = False
                i += 1
                continue
            if ch == '\\':
                cleaned.append(ch)
                escape = True
                i += 1
                continue
            if ch == '"' and not in_string:
                in_string = True
            elif ch == '"' and in_string:
                in_string = False
            if ch == '/' and not in_string and i + 1 < len(line) and line[i + 1] == '/':
                break  # rest of line is comment
            cleaned.append(ch)
            i += 1
        result.append(''.join(cleaned))

    content = '\n'.join(result)

    # Remove multi-line comments
    content = re.sub(r'/\*.*?\*/', '', content, flags=re.DOTALL)

    # Remove trailing commas before } or ]
    content = re.sub(r',\s*([}\]])', r'\1', content)

    # Replace single-quoted strings with double-quoted
    # Be careful not to replace apostrophes inside double-quoted strings
    content = re.sub(r"(?<![\\])'([^'\\]*(?:\\.[^'\\]*)*)'", r'"\1"', content)

    # Add quotes around unquoted keys (word followed by colon)
    content = re.sub(r'(?<=[{,\n])\s*([a-zA-Z_][a-zA-Z0-9_]*)\s*:', r' "\1":', content)

    return content


def fix_common_issues(content: str) -> Tuple[str, list]:
    """Fix common JSON issues. Returns (fixed_content, list_of_fixes)."""
    fixes = []
    original = content

    # Fix 1: Remove BOM
    if content.startswith('\ufeff'):
        content = content[1:]
        fixes.append("removed BOM (byte order mark)")

    # Fix 2: Remove // comments
    if re.search(r'(?<!["\'])//', content):
        content = re.sub(r'(?<!["\'])//.*?$', '', content, flags=re.MULTILINE)
        fixes.append("removed single-line comments")

    # Fix 3: Remove /* */ comments
    if '/*' in content:
        content = re.sub(r'/\*.*?\*/', '', content, flags=re.DOTALL)
        fixes.append("removed multi-line comments")

    # Fix 4: Trailing commas
    if re.search(r',\s*[}\]]', content):
        content = re.sub(r',\s*([}\]])', r'\1', content)
        fixes.append("removed trailing commas")

    # Fix 5: Single quotes to double quotes
    if re.search(r"(?<![\\])'", content):
        content = re.sub(r"(?<![\\])'([^'\\]*(?:\\.[^'\\]*)*)'", r'"\1"', content)
        fixes.append("converted single quotes to double quotes")

    # Fix 6: Unquoted keys
    if re.search(r'(?<=[{,\n])\s*[a-zA-Z_][a-zA-Z0-9_]*\s*:', content):
        content = re.sub(r'(?<=[{,\n])\s*([a-zA-Z_][a-zA-Z0-9_]*)\s*:', r' "\1":', content)
        fixes.append("quoted unquoted keys")

    # Fix 7: Missing closing brackets/braces
    opens = content.count('{') + content.count('[')
    closes = content.count('}') + content.count(']')
    if opens > closes:
        diff = opens - closes
        content = content.rstrip() + '\n' + '}' * diff + '\n'
        fixes.append(f"added {diff} missing closing bracket(s)")

    return content, fixes


def validate_json(content: str) -> Tuple[bool, Optional[str]]:
    """Validate JSON. Returns (is_valid, error_message)."""
    try:
        json.loads(content)
        return True, None
    except json.JSONDecodeError as e:
        return False, f"line {e.lineno}, col {e.colno}: {e.msg}"


def format_json(content: str, indent: int = 4, compact: bool = False, use_tabs: bool = False) -> str:
    """Format JSON with specified indentation."""
    data = json.loads(content)
    if compact:
        return json.dumps(data, separators=(',', ':'), ensure_ascii=False)
    if use_tabs:
        return json.dumps(data, indent='\t', ensure_ascii=False)
    return json.dumps(data, indent=indent, ensure_ascii=False) + '\n'


def backup_file(filepath: str, backup_dir: Optional[str] = None) -> str:
    """Create backup. Returns backup path."""
    filepath = Path(filepath)
    if backup_dir:
        bk_dir = Path(backup_dir)
    else:
        bk_dir = filepath.parent / '.jsonfmt-backups'
    bk_dir.mkdir(parents=True, exist_ok=True)

    ts = datetime.now().strftime('%Y%m%d_%H%M%S')
    bk_path = bk_dir / f"{filepath.name}.{ts}.bak"
    shutil.copy2(filepath, bk_path)
    return str(bk_path)


def get_diff(original: str, formatted: str, filepath: str) -> str:
    """Generate unified diff."""
    import difflib
    orig_lines = original.splitlines(keepends=True)
    fmt_lines = formatted.splitlines(keepends=True)
    diff = difflib.unified_diff(
        orig_lines, fmt_lines,
        fromfile=f"{filepath} (original)",
        tofile=f"{filepath} (formatted)",
        lineterm=''
    )
    return ''.join(diff)


def main():
    parser = argparse.ArgumentParser(
        description='JSON formatter, validator, and fixer.',
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  jsonfmt openclaw.json                  Format in-place
  jsonfmt openclaw.json --check          Validate only
  jsonfmt openclaw.json --fix            Fix issues then format
  jsonfmt openclaw.json --diff           Preview changes
  jsonfmt openclaw.json --indent 2       2-space indent
  jsonfmt openclaw.json --compact        Minified
  jsonfmt openclaw.json --json5          Parse JSON5 format
  cat config.json | jsonfmt -            Stdin
        """
    )
    parser.add_argument('file', help='JSON file (use - for stdin)')
    parser.add_argument('--check', action='store_true', help='Validate only, no modification')
    parser.add_argument('--fix', action='store_true', help='Auto-fix common issues before formatting')
    parser.add_argument('--json5', action='store_true', help='Parse as JSON5 (strip comments, trailing commas)')
    parser.add_argument('--indent', type=int, default=4, help='Indentation spaces (default: 4)')
    parser.add_argument('--tabs', action='store_true', help='Use tabs instead of spaces')
    parser.add_argument('--compact', action='store_true', help='Minified output (no whitespace)')
    parser.add_argument('--output', '-o', help='Output file (default: overwrite input)')
    parser.add_argument('--diff', action='store_true', help='Show diff without modifying')
    parser.add_argument('--backup-dir', help='Backup directory (default: .jsonfmt-backups/)')
    parser.add_argument('--no-backup', action='store_true', help='Skip backup (dangerous)')

    args = parser.parse_args()

    # Read input
    if args.file == '-':
        content = sys.stdin.read()
        filepath = '<stdin>'
        is_file = False
    else:
        filepath = args.file
        is_file = True
        if not os.path.exists(filepath):
            print(f"Error: {filepath} not found", file=sys.stderr)
            sys.exit(2)
        with open(filepath, 'r', encoding='utf-8-sig') as f:
            content = f.read()

    original = content

    # Step 1: JSON5 stripping
    if args.json5:
        content = strip_json5(content)

    # Step 2: Auto-fix
    if args.fix:
        content, fixes = fix_common_issues(content)
        if fixes:
            print(f"Fixes applied to {filepath}:")
            for fix in fixes:
                print(f"  - {fix}")
            print()

    # Step 3: Validate
    is_valid, error = validate_json(content)
    if not is_valid:
        # Try JSON5 strip as fallback
        if not args.json5:
            stripped = strip_json5(original)
            is_valid_stripped, _ = validate_json(stripped)
            if is_valid_stripped:
                print(f"Warning: {filepath} is JSON5, not standard JSON", file=sys.stderr)
                print(f"  Use --json5 flag to parse correctly", file=sys.stderr)
                print(f"  Or use --fix to convert to standard JSON", file=sys.stderr)
                sys.exit(1)

        print(f"Invalid JSON in {filepath}:", file=sys.stderr)
        print(f"  {error}", file=sys.stderr)

        if args.check:
            sys.exit(1)

        if not args.fix:
            print(f"  Run with --fix to auto-repair", file=sys.stderr)
            sys.exit(1)

        # Already tried fix, still broken
        sys.exit(1)

    if args.check:
        print(f"Valid: {filepath}")
        sys.exit(0)

    # Step 4: Format
    formatted = format_json(content, indent=args.indent, compact=args.compact, use_tabs=args.tabs)

    # Step 5: Check if already formatted
    if content == formatted and not args.fix:
        print(f"Already formatted: {filepath}")
        sys.exit(0)

    # Step 6: Diff mode
    if args.diff:
        diff = get_diff(original, formatted, filepath)
        if diff:
            print(diff)
        else:
            print(f"No changes: {filepath}")
        sys.exit(0)

    # Step 7: Output
    if args.output:
        with open(args.output, 'w', encoding='utf-8') as f:
            f.write(formatted)
        print(f"Written: {args.output}")
    elif is_file:
        # Backup
        if not args.no_backup:
            bk = backup_file(filepath, args.backup_dir)
            print(f"Backup: {bk}")

        with open(filepath, 'w', encoding='utf-8') as f:
            f.write(formatted)
        print(f"Formatted: {filepath}")
    else:
        sys.stdout.write(formatted)

    sys.exit(0)


if __name__ == '__main__':
    main()
