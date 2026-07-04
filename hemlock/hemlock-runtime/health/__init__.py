"""
Hemlock Operational Health Package

Health validators for the Hemlock runtime. Each sub-package provides
a focused validator for a specific concern area.

Validators:
  paths/      - PathResolver resolution, directory writability, Docker detection
  env/        - Environment variables, API keys, config files
  identity/   - Agent identity files, builder codes, persona configuration
  gateway/    - Platform adapters, port availability, messaging config
  imports/    - Core module import checks
  adapters/   - Platform adapter initialization
  orchestration/ - Process registry, skill manager, MCP brain
  persistence/ - SQLite, JSON, file I/O
  doctor_bridge.py - Unified orchestration of all validators

Usage:
  # Run all health checks
  python3 -m health.doctor_bridge

  # Quick check (paths, env, imports only)
  python3 -m health.doctor_bridge --quick

  # Auto-fix issues
  python3 -m health.doctor_bridge --fix

  # JSON output for automation
  python3 -m health.doctor_bridge --json

  # From OpenClaw pre-flight
  python3 -c "from health.doctor_bridge import run_all_checks; report = run_all_checks(quick=True); import sys; sys.exit(0 if report.healthy else 1)"
"""

__version__ = "0.1.0"