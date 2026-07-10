# Tooling Volume (`tooling.dat`)

The foundational data volume every USB-Hemlock stick carries. Mounted at
`/opt/tooling` in the booted system by `startup.sh` (via `rc.local`).

| Path | Role |
|---|---|
| `bin/hf` | Self-contained Hugging Face CLI (pylib carried on this volume) — model downloads, upstream hash checks, auth |
| `pylib/` | Python libraries the volume carries (`huggingface_hub`) — no host install needed |
| `tooling-update.sh` | Boot-time/on-demand updater: apt toolchain, npm globals (node/react), pylib upgrades; version snapshot every run |
| `models/manifest.json` | Identity of the GGUF library on the Ventoy partition: size + sha256 per model |
| `models/verify-models.sh` | Verifies the library against the manifest; `--hash` records/re-verifies sha256 |
| `logs/` | Update logs (boot logs live on the Ventoy partition at `usb-hemlock/logs/`) |

The GGUFs themselves stay on the Ventoy exFAT (`/models`) — big, portable,
readable everywhere. This volume carries their *identity* so any host can
verify the library is intact and untampered before trusting it.
