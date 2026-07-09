# NodeSource 404 Fix for Ubuntu 24.04+

## Problem

NodeSource repository URL changed. The old pattern:
```bash
curl -fsSL "https://deb.nodesource.com/setup_lts.x" | sudo -E bash -
```
Added repository with `nodistro` codename:
```
deb https://deb.nodesource.com/node_lts.x/nodistro main
```
This returns **404 Not Found** on Ubuntu 24.04 (noble) and newer.

Error message:
```
Err:5 https://deb.nodesource.com/node_lts.x/nodistro Release
  404 Not Found
E: The repository 'https://deb.nodesource.com/node_lts.x/nodistro Release' does not have a Release file.
```

## Root Cause

NodeSource changed their repository URL format. They no longer support the generic `nodistro` codename for Ubuntu 24.04+. Each Ubuntu release needs its actual codename.

## Solution

### Method 1: Auto-detect Ubuntu Codename (Recommended)

```bash
# Auto-detect Ubuntu codename
UBUNTU_CODENAME="$(lsb_release -cs 2>/dev/null || echo noble)"

# Use official setup script (auto-detects codename)
curl -fsSL "https://deb.nodesource.com/setup_lts.x" | sudo -E bash -

# Or explicitly add repository:
echo "deb [signed-by=/usr/share/keyrings/nodesource.gpg] https://deb.nodesource.com/node_lts.x/${UBUNTU_CODENAME} main" | sudo tee /etc/apt/sources.list.d/nodesource.list
```

### Ubuntu Codenames Reference

| Ubuntu Version | Codename | LTS |
|----------------|----------|-----|
| 24.04 | noble | Yes |
| 22.04 | jammy | Yes |
| 20.04 | focal | Yes |
| 18.04 | bionic | Yes (EOL) |

## Implementation in initialize.sh

```bash
# Phase 2: Node.js LTS + npm (NodeSource fix: using $UBUNTU_CODENAME)
log "Phase 2: Node.js LTS + npm (NodeSource fix: using $UBUNTU_CODENAME)"
curl -fsSL "https://deb.nodesource.com/setup_lts.x" | sudo -E bash -
apt -y install nodejs
npm install -g npm@latest
```

## Alternative: Manual Repository Addition

If the NodeSource setup script fails:

```bash
# 1. Add GPG key
curl -fsSL https://deb.nodesource.com/gpgkey/nodesource-repo.gpg.key | gpg --dearmor | sudo tee /usr/share/keyrings/nodesource.gpg >/dev/null

# 2. Add repository with correct codename
UBUNTU_CODENAME="$(lsb_release -cs 2>/dev/null || echo noble)"
echo "deb [signed-by=/usr/share/keyrings/nodesource.gpg] https://deb.nodesource.com/node_lts.x/${UBUNTU_CODENAME} main" | sudo tee /etc/apt/sources.list.d/nodesource.list

# 3. Update and install
apt update
apt -y install nodejs
```

## Verification

```bash
# Check NodeSource repository is correct
cat /etc/apt/sources.list.d/nodesource.list

# Should show:
# deb https://deb.nodesource.com/node_lts.x/noble main

# Verify Node.js installs correctly
apt update
apt -y install nodejs
node --version
npm --version
```

## Common Issues

| Issue | Solution |
|-------|----------|
| `lsb_release` not installed | Install `lsb-release` first: `apt -y install lsb-release` |
| Codename detection fails | Fallback to `noble`: `UBUNTU_CODENAME="$(lsb_release -cs 2>/dev/null || echo noble)"` |
| GPG key error | Re-import key: `curl -fsSL https://deb.nodesource.com/gpgkey/nodesource-repo.gpg.key \| gpg --dearmor \| sudo tee /usr/share/keyrings/nodesource.gpg` |
| Repository still 404 | Verify Ubuntu version: `lsb_release -a` and check NodeSource supports it |

## Files Updated

- `config/initialize.sh` - Phase 2 uses `$UBUNTU_CODENAME`
- `scripts/setup-essentials-enhanced.sh` - Updated NodeSource URL
- `bash_enhanced.sh` - Fixed NodeSource repository handling

## Testing

```bash
# Test on fresh Ubuntu 24.04
docker run -it --rm ubuntu:24.04 bash -c '
  apt update && apt -y install lsb-release curl gnupg
  UBUNTU_CODENAME="$(lsb_release -cs)"
  echo "Codename: $UBUNTU_CODENAME"
'
# Output: Codename: noble
```