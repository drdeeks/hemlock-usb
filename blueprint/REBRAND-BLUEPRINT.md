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

## Canonical naming & env glossary (docket #3 — DECIDED 2026-07-09)

Three names, three roles — use these consistently in ALL new prose:

| Name | Role | Implementation detail (never in user-facing prose) |
|------|------|-----------------------------------------------------|
| **Hemlock Gateway** | control plane: platforms, routing, agent loop, workspace injection | the vendored `openclaw` engine, exposed as `hemlock-gateway`; its own schema keeps `.openclaw` config dir and `OPENCLAW_*` vars |
| **Hemlock-loop** | the per-agent brain MCP: cognition + data ops, isolated per AGENT_ID | `agent_brain_mcp.py`, implemented by hermes |
| **hermes** | internal cognition/implementation name only | `hermes_cli`, `/opt/hermes`, `HERMES_HOME` (legacy mirror) |

Canonical sentence: *"The Hemlock Gateway reaches each agent's brain over its
per-agent Hemlock-loop MCP."*

**`HEMLOCK_*` environment variables** (the coexisting meanings, now documented):

| Variable | Meaning | Set by |
|----------|---------|--------|
| `HEMLOCK_HOME` | THIS agent/crew's data home (its volume) — canonical; `HERMES_HOME` mirrors it for legacy | Dockerfiles (`/runtime`), re-pointed per agent by entrypoint.sh, per-brain by gen-openclaw-config.py |
| `HEMLOCK_DIR` | path to the hemlock-runtime tree on the HOST (menu-side) | menu.sh auto-detect or operator |
| `HEMLOCK_ENABLED` | menu-side opt-in flag for Hemlock options (`--hemlock`/`-H`) | menu.sh arg parsing |
| `HEMLOCK_DOCKER` / `HEMLOCK_CONTAINER` | "running inside the Hemlock container" marker | Dockerfiles |
| `HEMLOCK_MINIMAL` / `HEMLOCK_LEAN` / `HEMLOCK_CORE` | which image variant this is | each variant's Dockerfile |
| `HEMLOCK_MODE`, `HEMLOCK_GATEWAY_PORT`, `HEMLOCK_KNOWLEDGE_DIR`, `HEMLOCK_VENTOY_MOUNT`, `HEMLOCK_NONINTERACTIVE` | runtime mode / port / knowledge dir / mount / no-prompt flags | operator or scripts |

`OPENCLAW_ROOT`, `OPENCLAW_CONFIG`, `OPENCLAW_GATEWAY_PORT` are the engine's own
names — implementation details, kept (Governing Principle 3).

## DOCKET — incoming rebranded drop audit (2026-07-09)

An externally-produced full rebrand landed at
`_incoming-docs/hemlock-usb-REBRANDED-wDASHBOARD.tar.gz` (menu.sh +
hemlock-runtime + NEW hemlock-dashboard SPA). Audited same day; adopt as the
rebrand baseline **after** the gate items below. Extracted copy examined at
the session scratchpad; the tarball is the source of record.

**Audit verdict:** lexically complete (0 "openclaw"/"hermes" hits across
1,284 files), forked from the 2026-07-09 tree (carries CL-041: identity-kit
bake, honor-only enforcer entrypoint, launcher node-fallback, menu option-11
fixes — nothing regressed; menu.sh delta is 30 lines, all lexical).
Dashboard = rebranded "Hemlock Control" PWA (Lit/Vite, i18n, legacy-theme
migration), not yet wired to anything.

**Gate items (must fix before build/deploy):**

1. **CLI name collision (build-breaking). — RESOLVED 2026-07-09.**
   Agent pyproject console script `hemlock` (was `hermes`) and the front-door
   wrapper `/usr/local/bin/hemlock` both claimed the same path.
   **Owner decision:** nothing is installed via a package manager; every CLI
   lives local within the repo and is *copied* into place, and a collision on
   a name is resolved by copying under a distinct Hemlock-oriented name.
   - Front-door wrapper (`scripts/hemlock`, launches the management TUI) keeps
     the bare **`hemlock`** — it is a repo file, copied (not pip/ln) into bin.
   - Agent/brain CLI (`hermes_cli.main:main`) → **`hemlock-agent`**, joining
     the family `hemlock` / `hemlock-agent` / `hemlock-runtime`. pip no longer
     claims bare `hemlock`, so the `ln`/COPY conflict is gone.
   Applied on `tui-rebrand`: `hermes-agent/pyproject.toml` `[project.scripts]`
   renamed; `hermes_cli/uninstall.py` now targets `hemlock-agent` (legacy
   `hemlock`/`hermes` still cleaned, front-door wrapper protected by the
   `hermes_cli` content guard). The gateway/vendored-lib naming is item #2.
2. **Vendored gateway lib rename assumed but not executed.** The drop ships
   `docker/hemlock-runtime/lib/` and `tools/` EMPTY; its Dockerfiles expect
   `lib/node_modules/hemlock/hemlock.mjs`. Our vendored package is named
   `openclaw` with 657 dist files self-referencing `.openclaw` (config dir,
   package resolution). NOTE: renaming inside vendored code violates
   Governing Principle 3 ("engine, not a brand"). Owner decision required:
   (a) keep the vendored package's internal name and point the rebranded
   launcher/Dockerfile at `node_modules/openclaw/openclaw.mjs` as an
   implementation detail (cheap, invisible, principle-compliant), or
   (b) fork-rename the vendored lib (expensive, permanent maintenance).
   **DECIDED (a) — alias, not fork. IMPL DONE 2026-07-09 (`e3c55af4`).**
   The engine stays internally `openclaw` in `node_modules`; exposed as
   **`hemlock-gateway`**. All four variants now symlink both
   `/usr/local/bin/openclaw` (kept for the engine's internal self-reference)
   and `/usr/local/bin/hemlock-gateway` → `openclaw-container`. Our own
   launcher invocations (entrypoint.sh, entrypoint-minimal.sh,
   health-check.sh) call `hemlock-gateway`, so ps/logs read "Hemlock Gateway".
   The stray `docker/openclaw-runtime/bin/openclaw` dev-path
   (`/home/drdeek/.openclaw/...`) was rewritten to resolve the engine relative
   to itself (OPENCLAW_ROOT) with bundled-or-system node fallback; verified
   portable. `.openclaw` config dir/keys untouched (engine-internal).
3. **Semantic flattening.** Gateway and brain both became "Hemlock" —
   self-contradictory prose in `gen-hemlock-config.py` ("Hemlock runs its
   own agents with NO Hemlock brains… Hemlock is ignored"), fabricated
   `docs.hemlock.ai` domain, and five coexisting `HEMLOCK_*` meanings
   (`_HOME` agent, `_ROOT` gateway, `_DIR` menu repo path, `_DOCKER`,
   `_MINIMAL`). Needs a naming pass distinguishing gateway vs brain in prose.
   **DECIDED naming + IMPL DONE for the current tree 2026-07-09
   (`973ec6ee`, `8868ffdb`; skills repo `5f5f626`):** **Hemlock Gateway** =
   control plane (the openclaw engine, aliased); **Hemlock-loop** = the MCP
   server exposing the hermes brain's tools to the gateway; **hermes** stays
   internal. Done: gen-openclaw-config.py prose/log lines; fabricated
   `docs.hemlock.ai` replaced with the real skills repo URL (runtime scripts,
   enterprise blueprint doc, knowledge-indexer); `HEMLOCK_*` env glossary
   added above (canonical naming section); `HEMLOCK_HOME` now set in all four
   image ENVs and mirrored at entrypoint.sh's per-agent re-point (the two
   previously diverged); skills repo swept (`hermes <cmd>` → `hemlock-agent`,
   docs to `HEMLOCK_HOME`, scripts prefer-with-fallback; 7 skills patch-bumped,
   all validate PASS 0/0). REMAINING (drop-side only): the same pass over the
   REBRANDED drop's `gen-hemlock-config.py` self-contradictions when #13
   integration happens.
4. **Dashboard wiring.** Nothing serves `hemlock-dashboard/`; decide where
   it mounts (gateway static assets vs menu-launched app-mode) — depends
   on item 2's decision.
5. **Skills-repo coordination. — RESOLVED 2026-07-09 (CL-045).**
   Bake policy settled: every image variant (minimal included — crew/agents
   share the runtime, brain MCP exposes `agent_skills_list`) bakes ONLY the
   7-skill kernel — skill-creator, skill-installer, autonomous-crew,
   enterprise-blueprint, loop-enforcer, agent-identity-architecture,
   guardrail-enforcement — refreshed from canonical `~/hemlock/skills`.
   Everything else auto-populates at runtime from github
   (`skills-auto-update.sh`) plus operator-added sources via the new menu
   option 21 (owner-namespaced, portable list). Amends CL-041. STILL TODO
   (separate from the bake): the curated skills' own text that says
   `hermes kanban …` / `${HERMES_HOME}` needs the CLI-name sweep to
   `hemlock-agent` / the Hemlock env names (depends on #1, done).
6. **Partial tree.** The drop contains only menu.sh + runtime + dashboard —
   integration is a merge into the repo, never a replace (usb/, blueprint/,
   README, CHANGELOG, dist/ live only here).
