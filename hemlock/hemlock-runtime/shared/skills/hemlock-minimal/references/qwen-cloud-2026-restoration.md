# qwen-cloud-2026 Restoration Procedure

**Validated**: 2026-07-04 | **Source**: hackathon-2026 (only working copy)

---

## Problem

qwen-cloud-2026 contained only 11 files (5 agent SOUL.md + config.yaml) — all source code, demos, federation server, and project configurations were missing. The complete autonomous federation system existed ONLY in `/home/ubuntu/hermes-agent/workspaces/hackathon-2026/`.

---

## Restoration Command

```bash
SOURCE="/home/ubuntu/hermes-agent/workspaces/hackathon-2026"
DEST="/home/ubuntu/qwen-cloud-2026"

# Copy 5 agent projects
for project in autopilot aires mnemosyne agora edgewalker; do
  cp -r "$SOURCE/$project" "$DEST/"
done

# Copy federation gateway
cp -r "$SOURCE/federation" "$DEST/"

# Copy shared providers
cp -r "$SOURCE/shared" "$DEST/"

# Copy enterprise configs
cp -r "$SOURCE/config" "$SOURCE/rules" "$SOURCE/scripts" "$SOURCE/docs" "$DEST/"

# Copy agent personalities (already present but ensure)
cp -r "$SOURCE/agents" "$DEST/"

# Copy crews, history, root files
cp -r "$SOURCE/crews" "$SOURCE/history" "$DEST/"
for file in .env HACKATHON_RESOURCES.html HACKATHON_RULES.html LICENSE README.md package.json hackathon-models.json; do
  cp "$SOURCE/$file" "$DEST/"
done
```

---

## Verification Checklist

| Component | Files | Test Command |
|-----------|-------|--------------|
| autopilot | 132 | `cd $DEST/autopilot && node demo.js` |
| aires | 126 | `cd $DEST/aires && node demo.js` |
| mnemosyne | 148 | `cd $DEST/mnemosyne && npm install && npm start` |
| agora | 112 | `cd $DEST/agora && node demo.js` |
| edgewalker | 113 | `cd $DEST/edgewalker && node demo.js` |
| federation | 811 | `cd $DEST/federation && npm install && node server.js &` |

---

## Federation Endpoints (Port 41207)

```
GET  /health                          → {"status":"healthy",...}
GET  /api/blueprints                  → Lists all 5 projects
GET  /api/memory/stats                → 4-layer stats (obsidian, semantic, daily, memory, identity)
GET  /api/memory/identity             → Returns SOUL.md content
GET  /api/memory/daily                → Returns daily notes
POST /api/join                        → Agent registration
```

---

## Key Architecture Points

1. **Federation is standalone** — agents register via `/api/join`, it routes between them, provides memory APIs, serves blueprints. Not tied to any single project.

2. **5 agent projects are independent** — can run standalone, register with federation, or work in crews. The `agents/` directory holds persistent identities (SOUL.md + config.yaml).

3. **Enterprise blueprint skills** in `.hermes/skills/devops/` are the *tooling* that built/validates this system — not part of runtime but part of development workflow.

---

## Agent Providers (from hackathon-models.json)

| Project | Model | Provider |
|---------|-------|----------|
| autopilot | qwen-plus-latest | DashScope |
| aires | qwen3-max-preview | DashScope |
| agora | qwen3-max-preview | DashScope |
| edgewalker | qwen3-coder-plus | DashScope |
| mnemosyne | (server-based) | Express + SQLite |

---

## Pitfalls Avoided

- ❌ Don't copy node_modules — run `npm install` in each project after copy
- ❌ Don't assume mnemosyne has a demo.js — it's a server (`npm start`)
- ❌ Don't start federation without `npm install` first (800+ npm packages)
- ✅ Federation binds to port 41207 — check for conflicts before starting
- ✅ All demos use REAL DashScope API — requires valid API keys in .env