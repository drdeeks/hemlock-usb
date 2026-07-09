# Hemlock Rebrand Blueprint

> Hemlock IS the combined system — control plane + cognition over MCP as ONE brand.
> This document maps every branding surface, classifies what must / may / must-never
> change, and sequences the work so nothing breaks mid-flight.
> Measured against the tree on 2026-07-04 — counts are real, not estimates.

## Why (not cosmetic)

Proven collision: a host OpenClaw was broken for weeks because Hemlock and host installs
fight over the SAME names — `OPENCLAW_ROOT`, `HERMES_HOME`, `~/.openclaw`, PATH entries,
port 18789. Interim shims now referee the fight (env guards in `run-native.sh`, installer
preflight, port 1437). The rebrand ends the fight by construction: `HEMLOCK_*` everything.

## Governing principles

1. **Alias-first, never big-bang.** Both names resolve during migration; legacy aliases
   stay through at least one release after each phase.
2. **The agent and the owner see only Hemlock.** Internal plumbing can lag; visible
   surfaces cannot.
3. **Vendored code is an engine, not a brand.** `docker/openclaw-runtime/` (the upstream
   node package) is treated like "node" or "python" — wrapped, configured, never edited.
   Renaming inside it would be forked maintenance forever.
4. **Attribution stays.** Licenses, NOTICE files, README credit to upstream projects
   remain intact — debranding the product ≠ erasing provenance.
5. **Every phase ships alone**: rebuild → health suite green → gateway handshake →
   Telegram round-trip → commit. No phase starts until the previous one proves out.

## Measured inventory (where the branding actually is)

| Surface | Count | Examples |
|---|---|---|
| Python files mentioning "hermes" (our code) | 199 | everything under `docker/hermes-agent/` |
| Files reading `HERMES_HOME` | 46 | `hermes_constants.py` `get_hermes_home()`, paths.py |
| Files mentioning "Nous" | 61 | `prompt_builder.py` identity, `banner.py`, `anthropic_adapter.py` |
| Our python mentioning "openclaw" | 23 | gen-openclaw-config, gateway glue |
| scripts/ + docker/ shell layer | 39 files | entrypoint.sh, runtime.sh, agent-*.sh |
| Files referencing `~/.hermes` paths | 79 | state, sessions, config resolution |
| Files referencing `/opt/hermes` | 15 | Dockerfiles, entrypoint, menu |
| `python3 -m hermes_cli.main` call sites | 16 | entrypoint, run-native, scripts |
| Python modules named hermes_* | 6 | `hermes_cli/`, `hermes/`, `hermes_{constants,logging,state,time}.py` |
| pyproject package name | ✅ already `hemlock` | done |
| Docker image/container names | ✅ `hemlock:*`, `hemlock_runtime` | done |
| Gateway port | ✅ 1437 (was 18789) | done 2026-07-04 |
| `HEMLOCK_HOME` canonical env | ✅ aliased in (HERMES_HOME still works) | done |

## Surface classification

### A — Agent/owner-visible: MUST rebrand (the actual point)
- `prompt_builder.py` DEFAULT_AGENT_IDENTITY ("Hermes Agent", "Nous Research"),
  the Nous subscription block, banner.py ASCII/branding, CLI help text,
  log subsystem labels shown to the owner, error messages, TUI headers,
  workspace-template docs the agent reads (already mostly $HEMLOCK_HOME).
- Rule: an agent introspecting its own environment should conclude "I am Hemlock."

### B — Interfaces users touch: rebrand WITH aliases
- Env vars: `HERMES_HOME→HEMLOCK_HOME` (alias exists; migrate the 46 readers to prefer
  HEMLOCK_HOME), `HERMES_ONLY/OPENCLAW_ONLY→HEMLOCK_MODE` (mode toggle already exists;
  retire legacy last), `OPENCLAW_GATEWAY_PORT→HEMLOCK_GATEWAY_PORT` (alias),
  `OPENCLAW_ROOT→HEMLOCK_GATEWAY_ROOT` (alias).
- Paths: `~/.hermes→~/.hemlock` (79 files — via ONE resolver function, see R3),
  container `/opt/hermes→/opt/hemlock/brain`, `/opt/openclaw→/opt/hemlock/gateway`
  (cheap at image rebuild; keep symlinks `/opt/hermes→/opt/hemlock/brain` one release).
- CLI: `python3 -m hermes_cli.main` → `hemlock` console entry (`hemlock gateway run`,
  `hemlock chat`, ...) with `hermes` kept as an alias shim one release.
- Skill tag block: runtime registry reads `metadata.hermes.tags` → read
  `metadata.hemlock.tags` FIRST, `hermes` as fallback; skill-creator remap gains
  `hemlock` as a provider target (keep `hermes`/`openclaw` targets for people running
  the real upstreams — that's the provider-adaptive system working as designed).

### C — Internal identifiers: rename LAST or never (invisible, highest risk)
- Python module names (`hermes_cli/`, `hermes_state.py`, ...): imports everywhere;
  rename only after A+B are stable — or accept them as internal forever (users never
  see module names). Recommended: rename in one mechanical commit with a
  compatibility shim module (`hermes_cli/__init__.py` re-exporting from `hemlock_cli`).
- Log file names, docker layer comments, internal dict keys.

### D — NEVER change
- `docker/openclaw-runtime/` vendored internals (upstream engine).
- Licenses, copyright, NOTICE, upstream attribution in README.
- Git history (no rewriting pushed history for branding).
- `metadata.hermes.tags` / `metadata.openclaw.tags` as SUPPORTED provider targets in
  skill tooling — those name OTHER people's harnesses, not our brand.

## Phase plan (each = one PR-sized commit + full verification)

| Phase | Scope | Files (est) | Risk |
|---|---|---|---|
| **R0** | Freeze + scripted inventory (`grep -c` manifest committed as baseline) | 1 doc | none |
| **R1** | Class A: identity strings, banner, prompts, CLI help, TUI headers, subsystem labels | ~15 | low — strings only |
| **R2** | Env vars: introduce `HEMLOCK_*` for gateway root/port/mode; all readers prefer HEMLOCK_*, fall back to legacy; entrypoint exports BOTH | ~20 | low — additive |
| **R3** | Paths: single `get_hemlock_home()` resolver (`~/.hemlock`, honors legacy `~/.hermes` if it exists — informative migration note, never forced move); container paths at rebuild + compat symlinks | ~10 real edits (79 call sites route through resolver) | medium |
| **R4** | CLI: `hemlock` console script entry point; 16 `hermes_cli.main` call sites updated; `hermes` shim prints a one-line notice then delegates | ~18 | medium |
| **R5** | Skill registry: `metadata.hemlock.tags` primary + remap target; seeder remaps to hemlock | ~4 | low |
| **R6** | Docs sweep: READMEs, AGENTS.md, TOOLS.md, menu text, USB references (badge already says OpenClaw+Hermes → becomes "Hemlock runtime — MCP inside") | ~30 docs | none |
| **R7** (optional, last) | Class C module renames with shims | ~200 mechanical | high — do only if wanted |

**Then:** rebuild all four variants → refresh `dist/` tarballs → v0.2.0 release with
assets → the `--release` installer picks them up automatically.

## Verification gate (every phase)

```
1. python3 -m health.doctor_bridge --quick       # all green
2. docker build (full variant) + container boot   # entrypoint completes
3. gateway up on 1437 + brain MCP handshake       # the loop works
4. one Telegram round-trip (test bot, never the real registrar)
5. guardrail gate + skill validate PASS           # repo integrity intact
6. grep manifest vs R0 baseline                   # count went DOWN, nothing new leaked
```

## Decision points for the owner (answer before R1 starts)

1. **Agent identity text** — what does a Hemlock agent say it is? (One paragraph for
   DEFAULT_AGENT_IDENTITY; today it claims Hermes/Nous.)
2. **`~/.hemlock` migration** — auto-detect legacy `~/.hermes` and offer (not force)
   a copy, or just honor it in place forever?
3. **R7 module renames** — worth the churn, or keep internals as-is permanently?
4. **The `hermes` CLI shim** — how long does it live? (Suggest: until v1.0.)
5. **Upstream credit placement** — footer of README ("built on OpenClaw + Hermes") or
   a dedicated CREDITS.md?

## What is already done (don't redo)

HEMLOCK_HOME alias · HEMLOCK_MODE toggle · image/container names · port 1437 ·
pyproject name `hemlock` · host-isolation guards · workspace-template docs using
$HEMLOCK_HOME · no-Hermes-only-image decision · installer/menu/release plumbing.
