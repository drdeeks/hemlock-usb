#!/usr/bin/env bash
# agent_volume.sh — manage the named volumes that isolate agents and crews
# in the hemlock-minimal runtime (hemlock-agent-<id>, hemlock-crew-<name>).
# Usage:
#   bash scripts/agent_volume.sh list
#   bash scripts/agent_volume.sh create agent <id>
#   bash scripts/agent_volume.sh create crew <name>
#   bash scripts/agent_volume.sh inspect <volume>
#   bash scripts/agent_volume.sh remove <volume> [--force]
set -euo pipefail

cmd="${1:-list}"

case "$cmd" in
    list)
        echo "hemlock agent/crew volumes:"
        docker volume ls --format '{{.Name}}' | grep -E '^hemlock-(agent|crew)-' || echo "  (none)"
        ;;
    create)
        kind="${2:?usage: create agent|crew <name>}"
        name="${3:?usage: create agent|crew <name>}"
        case "$kind" in agent|crew) ;; *) echo "kind must be 'agent' or 'crew'" >&2; exit 2 ;; esac
        vol="hemlock-${kind}-${name}"
        if docker volume inspect "$vol" >/dev/null 2>&1; then
            echo "exists: $vol"
        else
            docker volume create "$vol" >/dev/null
            echo "created: $vol"
        fi
        ;;
    inspect)
        vol="${2:?usage: inspect <volume>}"
        docker volume inspect "$vol"
        ;;
    remove)
        vol="${2:?usage: remove <volume> [--force]}"
        case "$vol" in
            hemlock-agent-*|hemlock-crew-*) ;;
            *) echo "refusing: only hemlock-agent-*/hemlock-crew-* volumes are managed here" >&2; exit 2 ;;
        esac
        if [ "${3:-}" != "--force" ]; then
            echo "This deletes ALL state in $vol. Re-run with --force to confirm." >&2
            exit 1
        fi
        docker volume rm "$vol"
        echo "removed: $vol"
        ;;
    *)
        echo "usage: $0 {list|create agent|crew <name>|inspect <vol>|remove <vol> --force}" >&2
        exit 2
        ;;
esac
