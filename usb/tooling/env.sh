#!/usr/bin/env bash
# source /opt/tooling/env.sh — activate the tooling volume's self-contained toolchain.
# Provides: node/npm/npx (portable), jq, hf, pylib (huggingface_hub), pip bootstrap.
TOOLING_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export PATH="$TOOLING_ROOT/bin:$TOOLING_ROOT/node/bin:$PATH"
export PYTHONPATH="$TOOLING_ROOT/pylib${PYTHONPATH:+:$PYTHONPATH}"
export TOOLING_ROOT
