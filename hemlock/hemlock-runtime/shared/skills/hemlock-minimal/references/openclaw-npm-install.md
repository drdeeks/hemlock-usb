# OpenClaw npm Install — Peer Dependency Resolution

## Problem

OpenClaw's `package.json` has peer dependency conflicts that prevent clean `npm install`:

```
npm ERR! ERESOLVE unable to resolve dependency tree
npm ERR! While resolving: @openclaw/telegram@...
npm ERR! Found: oxlint@...
npm ERR! node_modules/oxlint
npm ERR! peer oxlint@"..." from @oxlint/eslint-plugin@...
```

The conflict is primarily between `oxlint` and `tsgolint` peer dependencies.

## Solution

Use the `--legacy-peer-deps` flag to bypass peer dependency resolution:

```bash
cd /opt/openclaw/lib/node_modules/openclaw
npm install --production --legacy-peer-deps
```

## In Dockerfile

```dockerfile
# Install OpenClaw dependencies (using system npm)
RUN cd /opt/openclaw/lib/node_modules/openclaw && npm install --production --legacy-peer-deps 2>&1 | tail -10
```

## In Container (Manual Fix)

If the build didn't install deps correctly:

```bash
# From host
docker run -d --name hemlock-fix --entrypoint sleep hemlock/runtime:latest infinity
docker exec -u root hemlock-fix bash -c "cd /opt/openclaw/lib/node_modules/openclaw && npm install --production --legacy-peer-deps"
docker commit hemlock-fix hemlock/runtime:latest
docker rm -f hemlock-fix
```

## Root Cause

OpenClaw's dependency tree has conflicting peer dependencies between:
- `oxlint` (used by some extensions)
- `tsgolint` / TypeScript tooling
- Various ESLint plugins with conflicting peer requirements

The `--legacy-peer-deps` flag tells npm to ignore peer dependency conflicts and install anyway — which works because the actual runtime doesn't require all peer deps to be satisfied simultaneously.

## Verification

After install, verify the gateway starts:

```bash
docker run --rm \
    -v hemlock-gateway:/workspace/gateway \
    hemlock/runtime:latest \
    openclaw gateway run --allow-unconfigured --port 18789
```

Should output:
```
[gateway] loading configuration…
[gateway] resolving authentication…
[gateway] starting...
[gateway] starting HTTP server...
[canvas] host mounted at http://0.0.0.0:18789/__openclaw__/canvas/
[gateway] MCP loopback server listening on http://127.0.0.1:XXXXX/mcp
[heartbeat] started
[health-monitor] started...
[gateway] agent model: openai/gpt-5.4
[gateway] ready (N plugins: ...) 
```

## Troubleshooting

| Symptom | Cause | Fix |
|---------|-------|-----|
| `Cannot find package 'tslog'` | npm install didn't run | Run `npm install --production --legacy-peer-deps` |
| `EACCES: permission denied openclaw.mjs` | Volume permissions | `chown -R agent:agent /opt/openclaw/lib/node_modules/openclaw` |
| `Node.js v22` errors | Node version too new | Pin to Node 20.x LTS |
| `require is not defined` in npm | npm broken (ES module) | Use Node 20 with npm 10+ |

## Dockerfile Best Practice

```dockerfile
# Install Node.js 20.x LTS with working npm
RUN curl -fsSL https://deb.nodesource.com/setup_20.x | bash - && \
    apt-get install -y nodejs=20.20.2-1nodesource1 && \
    npm --version

# Install OpenClaw dependencies (using system npm)
RUN cd /opt/openclaw/lib/node_modules/openclaw && npm install --production --legacy-peer-deps 2>&1 | tail -10
```

**Key**: Use system npm (Node 20) instead of OpenClaw's bundled npm (which has ES module issues).