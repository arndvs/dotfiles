#!/usr/bin/env bash

# HITL shft — runs Claude once while you watch.
# Usage: ./shft/once.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

source "$SCRIPT_DIR/_build_prompt.sh"
trap 'rm -f "$PROMPT_FILE"' EXIT

# Inject proxy env vars if enabled
source "$SCRIPT_DIR/_proxy_env.sh" "hitl"

# When proxying through Copilot, default to Sonnet (Opus is too slow via proxy)
_model_flag=()
if [[ -n "${ANTHROPIC_BASE_URL:-}" ]]; then
    _model_flag=(--model claude-sonnet-4-6)
fi

claude --permission-mode acceptEdits "${_model_flag[@]}" -- "$(cat "$PROMPT_FILE")"
