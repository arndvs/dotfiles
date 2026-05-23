#!/usr/bin/env bash

# HITL shft — runs Claude once while you watch.
# Usage: ./shft/once.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

source "$SCRIPT_DIR/_build_prompt.sh"
trap 'rm -f "$PROMPT_FILE"' EXIT

# Inject proxy env vars if enabled
source "$SCRIPT_DIR/_proxy_env.sh" "hitl"

# ANTHROPIC_MODEL is set by _proxy_env.sh when proxying; --model flag not needed.
claude --permission-mode acceptEdits -- "$(cat "$PROMPT_FILE")"
