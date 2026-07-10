#!/usr/bin/env bash
# verify-models.sh — verify the GGUF library against the tooling manifest.
# The models live on the Ventoy exFAT (/models); this volume carries their
# identity: manifest.json with size + sha256 per file. The bundled hf CLI
# (../bin/hf) can cross-check hashes upstream on Hugging Face.
# Usage:
#   bash verify-models.sh              # size check (fast) + hash check where recorded
#   bash verify-models.sh --hash       # (re)compute sha256 for every model (slow, ~GB/min)
#   bash verify-models.sh --models-dir <dir>
set -u

TOOLING_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MANIFEST="$TOOLING_ROOT/models/manifest.json"
MODELS_DIR=""
DO_HASH=0
while [ $# -gt 0 ]; do
    case "$1" in
        --hash) DO_HASH=1; shift ;;
        --models-dir) MODELS_DIR="$2"; shift 2 ;;
        *) echo "unknown flag: $1" >&2; exit 2 ;;
    esac
done

# Locate the models dir: explicit flag, else the Ventoy mount's /models.
if [ -z "$MODELS_DIR" ]; then
    for c in /media/*/Ventoy/models /run/media/*/Ventoy/models /cdrom/models; do
        [ -d "$c" ] && { MODELS_DIR="$c"; break; }
    done
fi
[ -d "${MODELS_DIR:-}" ] || { echo "models dir not found — pass --models-dir" >&2; exit 2; }

python3 - "$MANIFEST" "$MODELS_DIR" "$DO_HASH" <<'PYEOF'
import hashlib, json, sys
from pathlib import Path

manifest_path, models_dir, do_hash = Path(sys.argv[1]), Path(sys.argv[2]), sys.argv[3] == "1"
manifest = json.loads(manifest_path.read_text()) if manifest_path.exists() else {"models": {}}
models = manifest.setdefault("models", {})

def sha256(p):
    h = hashlib.sha256()
    with open(p, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 22), b""):
            h.update(chunk)
    return h.hexdigest()

ok = bad = unknown = 0
for f in sorted(models_dir.glob("*.gguf")):
    rec = models.get(f.name)
    size = f.stat().st_size
    if rec is None:
        models[f.name] = {"size": size, "sha256": None}
        rec = models[f.name]
        print(f"NEW      {f.name} ({size/1e9:.2f} GB) — registered")
    if rec["size"] != size:
        print(f"SIZE-BAD {f.name}: manifest {rec['size']} vs disk {size}")
        bad += 1
        continue
    if do_hash or rec.get("sha256") is None and do_hash:
        pass
    if do_hash:
        digest = sha256(f)
        if rec.get("sha256") in (None, ""):
            rec["sha256"] = digest
            print(f"HASHED   {f.name}: {digest[:16]}… recorded")
            ok += 1
        elif rec["sha256"] == digest:
            print(f"OK       {f.name}")
            ok += 1
        else:
            print(f"HASH-BAD {f.name}: expected {rec['sha256'][:16]}… got {digest[:16]}…")
            bad += 1
    else:
        if rec.get("sha256"):
            print(f"SIZE-OK  {f.name} (hash recorded; run --hash to re-verify)")
            ok += 1
        else:
            print(f"SIZE-OK  {f.name} (no hash yet — run --hash to record)")
            unknown += 1

manifest_path.write_text(json.dumps(manifest, indent=2, sort_keys=True) + "\n")
print("---")
print(f"ok={ok} bad={bad} unhashed={unknown}")
sys.exit(1 if bad else 0)
PYEOF
