#!/usr/bin/env bash

# AFK shft — autonomous loop consuming GitHub issues backlog.
# Usage: ./shft/afk.sh [max_iterations]
# Default: 5 iterations

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CTRL_DIR="$(dirname "$SCRIPT_DIR")"
MAX_ITERATIONS="${1:-5}"
LOCKDIR="/tmp/shft-afk.lock"
MINT_SCRIPT="$CTRL_DIR/bin/mint_github_app_token.py"
RUN_WITH_SECRETS="$CTRL_DIR/bin/run-with-secrets.sh"
VENV_DIR="$CTRL_DIR/secrets/.venv"

source "$CTRL_DIR/bin/_lib.sh"

# ── HUD event helper (inline — works without sourcing write-hud-state.sh) ─
WORKING_DIR="$CTRL_DIR/working"
mkdir -p "$WORKING_DIR"

_push_afk_event() {
    local _type="$1" _msg="$2"
    local _ts _td _pipe _proj _path _ctx
    _ts=$(date -u +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null || echo "")
    _td=$(date +"%H:%M:%S" 2>/dev/null || echo "")
    _pipe="$WORKING_DIR/hud.pipe"
    _proj=$(basename "$(pwd)" 2>/dev/null || echo "unknown")
    _path="${PWD/$HOME/~}"
    _ctx="${ACTIVE_CONTEXTS:-general}"
    local _payload
    _payload=$(printf '{"type":"%s","project":"%s","projectPath":"%s","contexts":"%s","message":"%s","timestamp":"%s","time":"%s","source":"afk"}' \
        "$_type" "$_proj" "$_path" "$_ctx" "$_msg" "$_ts" "$_td")
    if [[ -p "$_pipe" ]]; then
        ( printf '%s\n' "$_payload" > "$_pipe" ) 2>/dev/null &
    else
        printf '%s\n' "$_payload" >> "$WORKING_DIR/events.jsonl" 2>/dev/null || true
    fi
}

# Concurrency guard — mkdir is atomic and portable (no flock on macOS)
if ! mkdir "$LOCKDIR" 2>/dev/null; then
    echo "shft already running" >&2
    exit 1
fi
trap 'rmdir "$LOCKDIR" 2>/dev/null' EXIT

if [[ ! -x "$RUN_WITH_SECRETS" ]]; then
    echo "ERROR: $RUN_WITH_SECRETS not found or not executable" >&2
    exit 1
fi

if [[ ! -f "$MINT_SCRIPT" ]]; then
    echo "ERROR: $MINT_SCRIPT not found. Merge AFK credential rotation slices before running AFK." >&2
    exit 1
fi

if ! find_python; then
    echo "ERROR: python3/python not found. Required for GitHub App token mint helper." >&2
    exit 1
fi
PYTHON_BIN="$PYTHON"

if ! "$RUN_WITH_SECRETS" bash "$CTRL_DIR/bin/validate-env.sh" --afk; then
    echo "ERROR: AFK environment validation failed" >&2
    exit 1
fi

for i in $(seq 1 "$MAX_ITERATIONS"); do
    echo "=== shft iteration $i of $MAX_ITERATIONS ==="
    _push_afk_event "info" "AFK iteration $i of $MAX_ITERATIONS started"

    mint_json=$("$RUN_WITH_SECRETS" "$PYTHON_BIN" "$MINT_SCRIPT") || {
        echo "ERROR: failed to mint GitHub App token for iteration $i" >&2
        exit 1
    }

    afk_token=$(printf '%s' "$mint_json" | jq -r '.token // empty')
    afk_token_expires_at=$(printf '%s' "$mint_json" | jq -r '.expires_at // empty')

    if [[ -z "$afk_token" ]]; then
        echo "ERROR: token mint helper returned empty token for iteration $i" >&2
        exit 1
    fi

    if [[ -z "$afk_token_expires_at" ]]; then
        echo "ERROR: token mint helper returned empty expires_at for iteration $i" >&2
        exit 1
    fi

    echo "token minted for iteration $i (expires_at=$afk_token_expires_at)"

    source "$SCRIPT_DIR/_build_prompt.sh"
    trap 'rm -f "$PROMPT_FILE"; rmdir "$LOCKDIR" 2>/dev/null' EXIT
    raw_output=$(mktemp)
    trap 'rm -f "$raw_output" "$PROMPT_FILE"; rmdir "$LOCKDIR" 2>/dev/null' EXIT

    # jq filters for stream-json format
    # stream_text: streams assistant text to stderr for real-time visibility
    # final_result: extracts the terminal result block used for sentinel detection
    stream_text='select(.type == "assistant").message.content[]? | select(.type == "text").text // empty'
    final_result='select(.type == "result") | .result // empty'

    if ! GITHUB_TOKEN="$afk_token" srt claude \
        --print \
        --output-format stream-json \
        < "$PROMPT_FILE" \
        2>/dev/null \
        | awk '/^[[:space:]]*\{/' \
        | tee >(jq -rj "$stream_text" >&2) \
        > "$raw_output"; then
        echo "ERROR: srt failed on iteration $i" >&2
        exit 1
    fi

    unset afk_token

    result=$(jq -r "$final_result" < "$raw_output" 2>/dev/null || true)
    rm -f "$raw_output" "$PROMPT_FILE"

    if echo "$result" | grep -q '<promise>NO MORE TASKS</promise>'; then
        _push_afk_event "info" "AFK complete after $i iterations — no more tasks"
        echo "shft complete after $i iterations"
        exit 0
    fi

    _push_afk_event "info" "AFK iteration $i of $MAX_ITERATIONS complete"
done

echo "shft reached max iterations ($MAX_ITERATIONS)"