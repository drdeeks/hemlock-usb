# USB-Hemlock Profile Manifest — Schema & Operations

> **Authoritative.** Profiles are USB-resident JSON files that describe how to
> assemble a boot: one primary overlay (the rootfs) + N data volumes mounted
> into it. Phase 2 of the multi-state work (CL-007). Agent/crew **roles** are
> a Hemlock concern; the manifest's `role` field is only a **storage-routing
> hint** for where a volume should mount.

## Location

```
<USB-mount>/usb-hemlock/profiles/<name>.json
```

Host fallback (`~/.config/usb-compute-automation/profiles/`) is used only when
the USB is not mounted or not writable. Auto-loading prefers the USB copy.

## Schema

```json
{
  "name":      "agent-loops",
  "device":    "/dev/sdb",
  "iso":       "/ubuntu-24.04.4-desktop-amd64.iso",
  "primary":   { "file": "/persistence/tooling.dat", "label": "casper-rw" },
  "data_volumes": [
    { "file": "/persistence/hemlock.dat", "mount": "/opt/hemlock",   "role": "hemlock",  "options": "defaults,nofail" },
    { "file": "/persistence/models.dat",  "mount": "/opt/models",    "role": "models",   "options": "defaults,nofail" },
    { "file": "/persistence/docker.dat",  "mount": "/var/lib/docker","role": "docker",   "options": "defaults,nofail" }
  ],
  "env":       { "OLLAMA_MODELS": "/opt/models/ollama", "HEMLOCK_DIR": "/opt/hemlock" },
  "default":   false,
  "boot_mode": "ventoy",
  "notes":     "Tooling + hemlock + models. Docker on its own volume."
}
```

### Field reference

| Field | Required | Notes |
|---|---|---|
| `device` | yes | `/dev/sdX` of the USB this profile targets. Set at save time; used by `_uca_autoload_profile`. |
| `iso` | yes (`boot_mode=ventoy`) | Path **relative to the USB mount**. Drives `ventoy.json.persistence[].image`. |
| `primary.file` | yes (`boot_mode=ventoy`) | Path to the rootfs overlay (e.g. `/persistence/tooling.dat`). Drives `ventoy.json.persistence[].backend`. **Must be ext4 labeled `casper-rw` for Ubuntu/casper.** |
| `primary.label` | optional | Default `casper-rw`. Informational; the on-disk fs label is what casper actually checks. |
| `data_volumes[].file` | yes | Path on USB (relative to mount). |
| `data_volumes[].mount` | yes | Mount point INSIDE the booted system (e.g. `/opt/hemlock`). |
| `data_volumes[].role` | optional | `tooling \| hemlock \| models \| docker \| custom`. Routing hint only — agent/crew roles are Hemlock's job. `docker` (or `mount=/var/lib/docker`) triggers a `docker.service` drop-in. |
| `data_volumes[].options` | optional | mount opts; default `defaults,nofail`. |
| `env` | optional | KEY/VALUE pairs written to `/etc/environment` in the primary (one line each). |
| `default` | optional | `true` → autoboot. menu.sh applies this profile's `device`/`iso`/`env` before auto-detection. |
| `boot_mode` | optional | `ventoy` (default) — compile to Ventoy persistence plugin. `qemu` — skip Ventoy compile; ISO is launched via menu **Access & Boot → 7** (e.g. macOS VMs). |
| `notes` | optional | Free-form. |

## Operations

The menu surface for these is **option 15** (Device / Boot Profiles):

| Menu | Action | What it touches |
|---|---|---|
| 15→3 | Save current as profile | Writes a new JSON (USB-first). |
| 15→7 | Set default (autoboot) | Flips `.default` on one file; clears it on the others. |
| **15→8** | **Edit manifest** | Interactive: set primary, add/remove data volumes, set boot_mode/iso, or open in `$EDITOR`. |
| **15→9** | **Compile → ventoy.json** | Writes the `persistence` plugin (image + backend + autosel=1). **Always backs up** `ventoy.json.bak.<ts>` first. No-op for `boot_mode=qemu`. |
| **15→10** | **Apply mounts to primary** | Loop-mounts the primary overlay; installs `/usr/local/sbin/uca-mount-volumes.sh` + `/etc/systemd/system/uca-volumes.service` (enabled via `multi-user.target.wants` symlink). Adds a `docker.service` drop-in if any volume is `role=docker` or mounted at `/var/lib/docker`. Writes `env` to `/etc/environment`. |
| **15→11** | **Preview** | Read-only — shows the manifest, marks `[MISSING]` data volumes, lists what apply would write. No mutation. |

Every mutation honors `DRY_RUN=true` (preview the exact mv/install/jq with no
side effects).

## Generated boot artifacts (inside the primary overlay)

`apply` writes three things into the rootfs:

1. **`/usr/local/sbin/uca-mount-volumes.sh`** — finds the USB by
   `LABEL=Ventoy` (path-agnostic, retries 5×), then loop-mounts each
   `data_volume` (`nofail` so a missing file is skipped, not a boot blocker).
2. **`/etc/systemd/system/uca-volumes.service`** — oneshot, runs the script
   `After=local-fs.target Before=docker.service multi-user.target`. Enabled
   via a manual symlink in `multi-user.target.wants` (we can't run
   `systemctl enable` inside the loop-mount).
3. **`/etc/systemd/system/docker.service.d/10-uca-after-volumes.conf`** (only
   when a docker volume is present) —
   `[Unit] After=uca-volumes.service / Requires=uca-volumes.service`. This
   guarantees the `/var/lib/docker` mount is in place **before** dockerd
   starts, so dockerd uses the volume rather than the underlying rootfs dir.

## Multi-state model (your example)

> *"standardized `tooling.data` always utilized + `hemlock.data` for runtime/
> agents + `models.data` for llama.cpp when running crew workloads"*

```json
{
  "name": "agent-loops",
  "iso":  "/ubuntu-24.04.4-desktop-amd64.iso",
  "primary": { "file": "/persistence/tooling.dat" },
  "data_volumes": [
    { "file": "/persistence/hemlock.dat", "mount": "/opt/hemlock", "role": "hemlock" },
    { "file": "/persistence/models.dat",  "mount": "/opt/models",  "role": "models"  }
  ],
  "env": { "HEMLOCK_DIR": "/opt/hemlock", "MODELS_DIR": "/opt/models" }
}
```

Lighter variant (skip models when you don't need them) — same primary, fewer
data volumes:

```json
{
  "name": "dev",
  "iso":  "/ubuntu-24.04.4-desktop-amd64.iso",
  "primary": { "file": "/persistence/tooling.dat" },
  "data_volumes": [
    { "file": "/persistence/hemlock.dat", "mount": "/opt/hemlock", "role": "hemlock" }
  ]
}
```

Cross-OS profile (future) — a different ISO booted via QEMU instead of
Ventoy's casper persistence (e.g. macOS):

```json
{
  "name": "mac-vm",
  "iso":  "/macos-installer.iso",
  "boot_mode": "qemu",
  "notes": "Launched from Access & Boot → 7 (Boot ISO in QEMU)."
}
```

For `boot_mode=qemu`, `compile` is a no-op and `apply` warns (no Linux
rootfs to inject mounts into). The profile's `iso` is just preferred by the
QEMU ISO-boot action.

## Constraints worth remembering

- **One persistence overlay per boot.** Ventoy/casper mount exactly one
  `casper-rw` backend as the rootfs. To run "tooling + hemlock + models
  together", one is the **primary overlay** and the others are **data
  volumes** mounted inside it. There is no native way to stack three
  overlays as a single root.
- **`casper-rw` is sacred.** The primary overlay's ext4 label MUST be
  `casper-rw` for Ubuntu/casper persistence to work. The Persistence
  Manager's Relabel (12→8) guards this label and refuses to remove it
  without explicit risk acknowledgement.
- **Paths are USB-relative.** Inside the manifest, `iso`, `primary.file`,
  and `data_volumes[].file` are paths **relative to the USB mount root** —
  never absolute host paths. This keeps profiles portable across machines.
- **Docker ordering matters.** If `/var/lib/docker` is a data volume,
  dockerd MUST start after the mount or it will write to the underlying
  rootfs and ignore the volume. The generated drop-in enforces this.

## Cross-references

- `blueprint/ventoy-reference.md` — what `compile` actually writes into
  `ventoy.json` and which Ventoy plugins are supported.
- `menu.sh:_uca_profile_*` — the helpers that implement this schema.
- CL-007 in `blueprint/blueprint.md` — the change-control entry for Phase 2.

## Foundation contract — the tooling bridge (2026-07-08)

**host compute → `tooling.dat` → hemlock.** Every stick carries ONE tooling
volume (`/persistence/tooling.dat`, ext4 label `tooling`) and every profile
rides it: `data_volumes` includes
`{ "file": "/persistence/tooling.dat", "mount": "/opt/tooling", "role": "tooling" }`.
Profile validation warns when a stick has a tooling.dat that a profile does
not reference. The volume carries the shared toolchain (self-contained
Hugging Face CLI + pylib, `tooling-update.sh` continuous updater, the GGUF
`models/manifest.json` + verifier) so agent workspaces keep only their
job-specific modules and dedupe into the bridge long-run. Boot chain:
persistence `/etc/rc.local` → `<usb>/startup.sh` (orchestrator: identity log
→ tooling mount → first-boot essentials → tooling update → operator hooks),
all logging to `<usb>/usb-hemlock/logs/`. Menu option 20 (Tooling Volume)
manages the full lifecycle; canonical script sources live in `usb/tooling/`.
