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

# Inject proxy env vars if enabled (sets ANTHROPIC_BASE_URL etc.)
source "$SCRIPT_DIR/_proxy_env.sh" "afk"

# ── TypeScript engine delegation ─────────────────────────────────────────────
if [[ "${SHFT_ENGINE:-bash}" == "ts" ]]; then
    echo "=== shft engine: TypeScript (sandcastle) ==="
    _push_afk_event "info" "AFK delegating to TypeScript engine (parallel, max-parallel=${MAX_PARALLEL:-4})"

    _engine_env=(env)
    [[ -n "${ANTHROPIC_BASE_URL:-}" ]]                      && _engine_env+=("ANTHROPIC_BASE_URL=$ANTHROPIC_BASE_URL")
    [[ -n "${ANTHROPIC_AUTH_TOKEN:-}" ]]                     && _engine_env+=("ANTHROPIC_AUTH_TOKEN=$ANTHROPIC_AUTH_TOKEN")
    [[ -n "${ANTHROPIC_MODEL:-}" ]]                          && _engine_env+=("ANTHROPIC_MODEL=$ANTHROPIC_MODEL")
    [[ -n "${CLAUDE_CODE_DISABLE_EXPERIMENTAL_BETAS:-}" ]]   && _engine_env+=("CLAUDE_CODE_DISABLE_EXPERIMENTAL_BETAS=$CLAUDE_CODE_DISABLE_EXPERIMENTAL_BETAS")
    [[ -n "${CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC:-}" ]] && _engine_env+=("CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=$CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC")

    mint_json=$("$RUN_WITH_SECRETS" "$PYTHON_BIN" "$MINT_SCRIPT") || {
        echo "ERROR: failed to mint GitHub App token" >&2
        exit 1
    }

    afk_token=$(printf '%s' "$mint_json" | jq -r '.token // empty')
    if [[ -z "$afk_token" ]]; then
        echo "ERROR: token mint returned empty token" >&2
        exit 1
    fi

    _engine_env+=("GITHUB_TOKEN=$afk_token")

    "${_engine_env[@]}" npx tsx "$SCRIPT_DIR/engine/main.ts" \
        --repo "$(pwd)" \
        --workflow parallel \
        --max-iterations "$MAX_ITERATIONS" \
        --max-issues "${MAX_ISSUES:-5}" \
        --max-parallel "${MAX_PARALLEL:-4}" || {
        echo "ERROR: TypeScript engine failed" >&2
        _push_afk_event "info" "Engine parallel run failed"
        exit 1
    }

    unset afk_token

    _push_afk_event "info" "AFK engine complete (parallel mode)"
    echo "shft engine complete (parallel mode)"
    exit 0
fi
# Use plain claude when srt sandbox can't reach the proxy
# (WSL2 has no host network access; MSYS/Windows has no Docker Linux sandbox)
if grep -qi microsoft /proc/version 2>/dev/null || [[ "$(uname -o 2>/dev/null)" == "Msys" ]]; then
    _CLAUDE_CMD=(claude)
else
    _CLAUDE_CMD=(srt claude)
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

    # Progress ticker — visual heartbeat while waiting for first Claude response
    _ticker_chars=('⠋' '⠙' '⠹' '⠸' '⠼' '⠴' '⠦' '⠧' '⠇' '⠏')
    _tick_i=0
    _tick_ppid=$$
    while kill -0 "$_tick_ppid" 2>/dev/null; do
        printf "\r  %s thinking..." "${_ticker_chars[$((_tick_i % ${#_ticker_chars[@]}))]}" >&2
        _tick_i=$((_tick_i + 1))
        sleep 0.2
    done &
    _ticker_pid=$!
    # Kill ticker on first output or error
    _stop_ticker() { kill "$_ticker_pid" 2>/dev/null; wait "$_ticker_pid" 2>/dev/null; printf "\r\033[K" >&2; }

    # Thinking-gap spinner — animates when jq output pauses > 1s
    _thinking_filter() {
        local line _tpid=
        _start_think() {
            local _think_ppid=$BASHPID
            ( while kill -0 "$_think_ppid" 2>/dev/null; do
                for c in '⠋' '⠙' '⠹' '⠸' '⠼' '⠴' '⠦' '⠧' '⠇' '⠏'; do
                    printf '\r  %s thinking...' "$c"
                    sleep 0.2
                done
            done ) &
            _tpid=$!
        }
        _kill_think() {
            [[ -n "$_tpid" ]] && kill "$_tpid" 2>/dev/null && wait "$_tpid" 2>/dev/null
            printf '\r\033[K'
            _tpid=
        }
        while true; do
            if IFS= read -r -t 1 line; then
                [[ -n "$_tpid" ]] && _kill_think
                printf '%s\n' "$line"
            elif (( $? > 128 )); then
                [[ -z "$_tpid" ]] && _start_think
            else
                break
            fi
        done
        [[ -n "$_tpid" ]] && _kill_think
    }

    source "$SCRIPT_DIR/_build_prompt.sh"
    trap '_stop_ticker; rm -f "$PROMPT_FILE"; rmdir "$LOCKDIR" 2>/dev/null' EXIT
    raw_output=$(mktemp)
    trap '_stop_ticker; rm -f "$raw_output" "$PROMPT_FILE"; rmdir "$LOCKDIR" 2>/dev/null' EXIT

    # jq filters for stream-json format
    # stream_live: streams tool calls + assistant text to stderr for real-time visibility
    # final_result: extracts the terminal result block used for sentinel detection
    stream_live='
      if .type == "system" and .subtype == "init" then
        "[init] model: \(.model // "unknown") | tools: \(.tools | length)\n"
      elif .type == "assistant" then
        (
          ([.message.content[]? | select(.type == "tool_use") |
            if .name == "Bash" then "[bash] \(.input.command // "" | split("\n")[0] | .[0:120])\n"
            elif .name == "Read" then "[read] \(.input.file_path // "")\n"
            elif .name == "Edit" then "[edit] \(.input.file_path // "")\n"
            elif .name == "Write" then "[write] \(.input.file_path // "")\n"
            elif .name == "Glob" then "[glob] \(.input.pattern // "")\n"
            elif .name == "Grep" then "[grep] \(.input.pattern // "")\n"
            elif .name == "WebSearch" then "[search] \(.input.query // "")\n"
            elif .name == "WebFetch" then "[fetch] \(.input.url // "")\n"
            elif (.name // "" | startswith("mcp_")) then "[mcp] \(.name | ltrimstr("mcp__"))\n"
            elif .name == "TaskCreate" then "[agent] \(.input.prompt // "" | .[0:80])\n"
            elif .name == "Skill" then "[skill] \(.input.skill_name // "")\n"
            else "[\(.name // "tool")]\n"
            end
          ] | join(""))
          +
          ([.message.content[]? | select(.type == "text") | .text | gsub("\u2014"; "--") | gsub("\u2018|\u2019"; "\u0027") | gsub("\u201c|\u201d"; "\u0022") | gsub("[^\u0000-\u007F]"; "")] | join(""))
        )
      elif .type == "result" then
        "\n-- done (\(.duration_ms // 0)ms, $\(.total_cost_usd // 0 | tostring | .[0:6]))\n"
      else empty end'
    final_result='select(.type == "result") | .result // empty'

    # ANTHROPIC_MODEL is set by _proxy_env.sh when proxying; --model flag not needed.
    # Build env array — only pass vars that are actually set.
    _afk_env=(env "GITHUB_TOKEN=$afk_token")
    [[ -n "${ANTHROPIC_BASE_URL:-}" ]]                      && _afk_env+=("ANTHROPIC_BASE_URL=$ANTHROPIC_BASE_URL")
    [[ -n "${ANTHROPIC_AUTH_TOKEN:-}" ]]                     && _afk_env+=("ANTHROPIC_AUTH_TOKEN=$ANTHROPIC_AUTH_TOKEN")
    [[ -n "${ANTHROPIC_MODEL:-}" ]]                          && _afk_env+=("ANTHROPIC_MODEL=$ANTHROPIC_MODEL")
    [[ -n "${CLAUDE_CODE_DISABLE_EXPERIMENTAL_BETAS:-}" ]]   && _afk_env+=("CLAUDE_CODE_DISABLE_EXPERIMENTAL_BETAS=$CLAUDE_CODE_DISABLE_EXPERIMENTAL_BETAS")
    [[ -n "${CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC:-}" ]] && _afk_env+=("CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=$CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC")

    _afk_stderr_log="$WORKING_DIR/afk-iter-${i}-stderr.log"
    if ! "${_afk_env[@]}" \
        "${_CLAUDE_CMD[@]}" \
        --print \
        --verbose \
        --dangerously-skip-permissions \
        --output-format stream-json \
        < "$PROMPT_FILE" \
        2>"$_afk_stderr_log" \
        | awk '/^[[:space:]]*\{/ { print; fflush() }' \
        | { _first=true; while IFS= read -r line; do
              if $_first; then _stop_ticker; _first=false; fi
              printf '%s\n' "$line"
            done; } \
        | tee >(jq --unbuffered -rj "$stream_live" 2>/dev/null | _thinking_filter >&2; cat >/dev/null) \
        > "$raw_output"; then
        _stop_ticker
        echo "ERROR: ${_CLAUDE_CMD[*]} failed on iteration $i" >&2
        echo "  stderr log: $_afk_stderr_log" >&2
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