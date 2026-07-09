#!/usr/bin/env python3
"""plugin_selftest.py — verify the tool-enforcement plugin is intact.

Checks the manifest template, imports the plugin module, and exercises both
hooks (pre_llm_call guidance injection, pre_tool_call violation logging).

Usage: python3 scripts/plugin_selftest.py
Exit 0 = plugin healthy.
"""
import importlib.util
import io
import sys
from contextlib import redirect_stdout
from pathlib import Path

SKILL_ROOT = Path(__file__).resolve().parent.parent


def main():
    failures = []

    manifest = SKILL_ROOT / "references" / "templates" / "plugin.yaml"
    if manifest.exists():
        text = manifest.read_text()
        for key in ("name:", "version:", "provides_hooks:"):
            if key not in text:
                failures.append(f"manifest missing {key}")
        print(f"PASS manifest {manifest.relative_to(SKILL_ROOT)}")
    else:
        failures.append("manifest template missing")

    spec = importlib.util.spec_from_file_location(
        "tool_enforcement_plugin", SKILL_ROOT / "__init__.py")
    mod = importlib.util.module_from_spec(spec)
    try:
        spec.loader.exec_module(mod)
        print("PASS module import")
    except Exception as e:
        failures.append(f"module import failed: {e}")
        mod = None

    if mod is not None:
        guidance = mod.inject_tool_guidance(is_first_turn=True)
        for phrase in ("chmod 700", "write_file"):
            if phrase not in guidance:
                failures.append(f"guidance missing phrase: {phrase}")
        if not failures:
            print(f"PASS pre_llm_call guidance ({len(guidance)} chars)")

        buf = io.StringIO()
        with redirect_stdout(buf):
            mod.log_path_violations(tool_name="terminal",
                                    args={"command": "chmod 700 /some/dir"})
        if "PROHIBITED" in buf.getvalue():
            print("PASS pre_tool_call flags restrictive chmod")
        else:
            failures.append("pre_tool_call did not flag chmod 700")

        buf = io.StringIO()
        with redirect_stdout(buf):
            mod.log_path_violations(tool_name="write_file",
                                    args={"path": "/somewhere/else/file.txt"})
        # only warns when HERMES_HOME is set; either outcome is acceptable here
        print("PASS pre_tool_call write_file path check callable")

    print("---")
    if failures:
        for f in failures:
            print(f"FAIL {f}")
        return 1
    print("PLUGIN HEALTHY")
    return 0


if __name__ == "__main__":
    sys.exit(main())
