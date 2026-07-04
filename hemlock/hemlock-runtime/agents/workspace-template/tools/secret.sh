#!/usr/bin/env bash
# =============================================================================
# secret.sh — Encrypted secret management
# =============================================================================
#
# Stores secrets as encrypted .json.enc files in $HERMES_HOME/.secrets/.
# Decrypts on read, encrypts on write. Plaintext never touches disk long-term.
#
# Encryption: AES-256-CBC with PBKDF2
# Key: $HERMES_HOME/.secrets/.secret-key (auto-generated, 600 perms)
#
# Usage:
#   bash tools/secret.sh get <name> [key]         Get a value
#   bash tools/secret.sh list                      List secret names
#   bash tools/secret.sh show [name]               OWNER view: full decrypted JSON
#   bash tools/secret.sh set <name> <key> <value>  Save a secret
#   bash tools/secret.sh has <name> [key]          Check if exists
#   bash tools/secret.sh delete <name>             Delete a secret
#   bash tools/secret.sh init                      Generate encryption key
#   bash tools/secret.sh migrate                   Convert plaintext to encrypted
#
# OWNER vs AGENT: `show` decrypts and prints full secrets for the human OWNER to
# view/manage/audit (exports carry .secrets/ + .secret-key for exactly this). Agents
# should use get/has for the single value they need and must NEVER copy decrypted
# secrets into memory/logs — but the owner is a first-class stakeholder and is never
# locked out of their own secrets.
#
# Examples:
#   bash tools/secret.sh get neynar api_key
#   bash tools/secret.sh set github token "ghp_abc123"
#   bash tools/secret.sh list
#
# File format:
#   .secrets/.secret-key         Encryption key (auto-generated)
#   .secrets/.<name>.json.enc    Encrypted secret files
#   .secrets/.<name>.json        Plaintext (temporary, deleted after encrypt)
#
# NEVER read .secrets/ files directly. Always use this script.
# NEVER chmod 700 anything. Use 755 (dirs) or 644 (files).
# =============================================================================

set -euo pipefail

SECRETS_DIR="${HEMLOCK_HOME:-${HERMES_HOME:-.}}/.secrets"
KEY_FILE="${SECRETS_DIR}/.secret-key"
ENC_CMD="openssl enc -aes-256-cbc -salt -pbkdf2 -pass file:${KEY_FILE}"
DEC_CMD="openssl enc -d -aes-256-cbc -pbkdf2 -pass file:${KEY_FILE}"

mkdir -p "$SECRETS_DIR" 2>/dev/null

# Auto-init key if missing
if [ ! -f "$KEY_FILE" ]; then
    openssl rand -base64 32 > "$KEY_FILE"
    chmod 600 "$KEY_FILE"
fi

# Decrypt a .enc file to stdout
decrypt_file() {
    local enc_file="$1"
    [ -f "$enc_file" ] || return 1
    $DEC_CMD -in "$enc_file" 2>/dev/null
}

# Encrypt stdin to a .enc file
encrypt_to() {
    local enc_file="$1"
    $ENC_CMD -out "$enc_file" 2>/dev/null
    chmod 600 "$enc_file"
}

# Get JSON file path (checks both .enc and plain .json)
get_secret_file() {
    local name="$1"
    if [ -f "${SECRETS_DIR}/.${name}.json.enc" ]; then
        echo "${SECRETS_DIR}/.${name}.json.enc"
    elif [ -f "${SECRETS_DIR}/.${name}.json" ]; then
        echo "${SECRETS_DIR}/.${name}.json"
    else
        return 1
    fi
}

# Read secret JSON (handles both encrypted and plaintext)
read_secret_json() {
    local name="$1"
    local file
    file=$(get_secret_file "$name") || { echo "ERROR: Secret '${name}' not found" >&2; exit 1; }

    if [[ "$file" == *.enc ]]; then
        decrypt_file "$file"
    else
        cat "$file"
    fi
}

# Write secret JSON (always encrypts). Plaintext NEVER touches disk — the JSON
# is piped straight into openssl; no temp .json file is ever written.
write_secret_json() {
    local name="$1"
    local json="$2"
    printf '%s\n' "$json" | encrypt_to "${SECRETS_DIR}/.${name}.json.enc"
}

case "${1:-}" in
    get)
        name="${2:?Usage: secret.sh get <name> [key]}"
        key="${3:-}"

        json=$(read_secret_json "$name")

        if [ -n "$key" ]; then
            SECRET_JSON="$json" SECRET_KEY="$key" SECRET_NAME="$name" python3 -c '
import json, os, sys
data = json.loads(os.environ["SECRET_JSON"])
for k in os.environ["SECRET_KEY"].split("."):
    if isinstance(data, dict) and k in data:
        data = data[k]
    else:
        print("ERROR: Key %s not found in %s" % (os.environ["SECRET_KEY"], os.environ["SECRET_NAME"]), file=sys.stderr)
        sys.exit(1)
print(data)
' 2>/dev/null
        else
            SECRET_JSON="$json" python3 -c '
import json, os
data = json.loads(os.environ["SECRET_JSON"])
if isinstance(data, dict):
    for k in data:
        print(k)
' 2>/dev/null
        fi
        ;;

    list)
        echo "Available secrets:"
        for f in "$SECRETS_DIR"/.*.json*; do
            [ -f "$f" ] || continue
            base=$(basename "$f")
            [[ "$base" == .secret-key ]] && continue
            name="${base%.json.enc}"
            name="${name%.json}"
            name="${name#.}"
            echo "  ${name}"
        done
        ;;

    show)
        # OWNER view: decrypt and print full secret JSON. `show <name>` for one,
        # `show` (no arg) dumps every secret — intended for the human owner to
        # view/manage/audit. Still routed through the script (never cat the .enc).
        name="${2:-}"
        if [ -n "$name" ]; then
            read_secret_json "$name"
        else
            names=$(for f in "$SECRETS_DIR"/.*.json*; do
                [ -f "$f" ] || continue
                b=$(basename "$f"); [[ "$b" == .secret-key ]] && continue
                b="${b%.json.enc}"; b="${b%.json}"; echo "${b#.}"
            done | sort -u)
            if [ -z "$names" ]; then echo "No secrets stored."; exit 0; fi
            for n in $names; do
                echo "=== ${n} ==="
                read_secret_json "$n"
                echo ""
            done
        fi
        ;;

    set)
        name="${2:?Usage: secret.sh set <name> <key> <value>}"
        key="${3:?Key required}"
        value="${4:?Value required}"

        # Read existing or create new
        if existing=$(read_secret_json "$name" 2>/dev/null); then
            json="$existing"
        else
            json="{}"
        fi

        # Update the key
        updated=$(SECRET_JSON="$json" SECRET_KEY="$key" SECRET_VALUE="$value" python3 -c '
import json, os
data = json.loads(os.environ["SECRET_JSON"])
keys = os.environ["SECRET_KEY"].split(".")
target = data
for k in keys[:-1]:
    if k not in target or not isinstance(target[k], dict):
        target[k] = {}
    target = target[k]
target[keys[-1]] = os.environ["SECRET_VALUE"]
print(json.dumps(data, indent=2))
' 2>/dev/null)

        write_secret_json "$name" "$updated"
        echo "OK: Set ${name}.${key}"
        ;;

    has)
        name="${2:?Usage: secret.sh has <name> [key]}"
        key="${3:-}"

        get_secret_file "$name" >/dev/null 2>&1 || exit 1

        if [ -n "$key" ]; then
            json=$(read_secret_json "$name")
            SECRET_JSON="$json" SECRET_KEY="$key" python3 -c '
import json, os, sys
data = json.loads(os.environ["SECRET_JSON"])
for k in os.environ["SECRET_KEY"].split("."):
    if isinstance(data, dict) and k in data:
        data = data[k]
    else:
        sys.exit(1)
' 2>/dev/null
        fi
        ;;

    delete)
        name="${2:?Usage: secret.sh delete <name>}"
        rm -f "${SECRETS_DIR}/.${name}.json" "${SECRETS_DIR}/.${name}.json.enc"
        echo "OK: Deleted ${name}"
        ;;

    init)
        openssl rand -base64 32 > "$KEY_FILE"
        chmod 600 "$KEY_FILE"
        echo "OK: Encryption key generated at ${KEY_FILE}"
        echo "WARNING: Back up this key separately. Without it, secrets cannot be decrypted."
        ;;

    migrate)
        echo "Migrating plaintext secrets to encrypted format..."
        for f in "$SECRETS_DIR"/.*.json; do
            [ -f "$f" ] || continue
            base=$(basename "$f")
            [[ "$base" == .secret-key ]] && continue

            name="${base%.json}"
            name="${name#.}"

            if [ -f "${SECRETS_DIR}/.${name}.json.enc" ]; then
                echo "  SKIP: ${name} (already encrypted)"
                continue
            fi

            # Read plaintext, encrypt
            content=$(cat "$f")
            echo "$content" | encrypt_to "${SECRETS_DIR}/.${name}.json.enc"
            rm -f "$f"
            echo "  Migrated: .${name}.json → .${name}.json.enc"
        done

        # Also migrate non-JSON files
        for f in "$SECRETS_DIR"/.*; do
            [ -f "$f" ] || continue
            base=$(basename "$f")
            [[ "$base" == .secret-key ]] && continue
            [[ "$base" == *.json.enc ]] && continue
            [[ "$base" == *.json ]] && continue

            name="${base%.secret}"
            name="${name%.txt}"
            name="${name%.md}"
            name="${name%.key}"

            content=$(cat "$f" 2>/dev/null)

            if echo "$content" | python3 -c "import json,sys;json.load(sys.stdin)" 2>/dev/null; then
                # Already JSON — encrypt directly
                echo "$content" | encrypt_to "${SECRETS_DIR}/.${name}.json.enc"
            else
                # Plain text — wrap in JSON then encrypt
                python3 -c "
import json
content = open('$f').read().strip()
if '=' in content and '\n' in content:
    data = {}
    for line in content.split('\n'):
        line = line.strip()
        if '=' in line and not line.startswith('#'):
            k, v = line.split('=', 1)
            data[k.strip()] = v.strip()
    print(json.dumps(data, indent=2))
else:
    print(json.dumps({'value': content}, indent=2))
" | encrypt_to "${SECRETS_DIR}/.${name}.json.enc"
            fi

            rm -f "$f"
            echo "  Migrated: ${base} → .${name}.json.enc"
        done
        echo "Migration complete."
        ;;

    *)
        echo "Usage:"
        echo "  secret.sh get <name> [key]       Get a secret value"
        echo "  secret.sh list                   List available secrets"
        echo "  secret.sh show [name]            OWNER: view full decrypted secret(s)"
        echo "  secret.sh set <name> <key> <val> Set a secret value"
        echo "  secret.sh has <name> [key]       Check if secret exists"
        echo "  secret.sh delete <name>          Delete a secret"
        echo "  secret.sh init                   Generate encryption key"
        echo "  secret.sh migrate                Encrypt existing plaintext secrets"
        ;;
esac
