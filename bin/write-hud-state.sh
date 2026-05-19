#!/usr/bin/env bash
# write-hud-state.sh — Push events to the HUD daemon.
#
# Source this file:
#   source ~/dotfiles/bin/write-hud-state.sh
#
# Then call:
#   write_hud_event "read"    "Read skills/do-work/SKILL.md"
#   write_hud_event "pass"    "global.instructions.md — Surgical Changes ✓"
#   write_hud_event "fail"    "VIOLATION — rules/migration-safety.md — no rollback"
#   write_hud_event "warn"    "typescript.instructions.md — implicit any detected"
#   write_hud_event "info"    "Task started: implement user avatar"
#   write_hud_event "context" "Active contexts: general,nextjs,typescript"
#   update_hud_compliance 8 1 2    # pass fail warn
#
# Called by:
#   detect-context.sh  → context events (every cd)
#   compliance-audit   → pass/fail/warn/compliance_update events
#   CLAUDE.md hooks    → read events
#   ctrlshft-claude    → stdout parse events
#
# Transport priority (never blocks, never fails loudly):
#   1. Named pipe  → daemon (real-time, <1ms)
#   2. HTTP POST   → daemon (fallback, ~5ms)
#   3. JSONL file  → file watcher (last resort, daemon picks up on next poll)
#
# NOTE: Does NOT source _lib.sh — this file is sourced from .bashrc/.zshrc
# contexts and must remain fully self-contained (same rule as load-secrets.sh).

DOTFILES="${DOTFILES:-$HOME/dotfiles}"
_WD="$DOTFILES/working"
_PIPE="$_WD/hud.pipe"
_JSONL="$_WD/events.jsonl"
_HTTP_PORT="${HUD_PORT:-7823}"

# ── _can_use_pipe — check if named pipe transport is available ────────────────
# Returns 0 (true) if the pipe exists, is a FIFO, and we're not on MSYS/Windows
# where mkfifo creates POSIX pipes that have no reader.
_can_use_pipe() {
    [[ -p "$_PIPE" && "$(uname -o 2>/dev/null)" != "Msys" ]]
}

# ── write_hud_event ─────────────────────────────────────────────────────
write_hud_event() {
    local _type="$1"
    local _msg="$2"
    local _proj_override="${3:-}"   # optional: project name override
    local _path_override="${4:-}"   # optional: project path override

    # Collect context
    local _proj
    _proj="${_proj_override:-$(basename "$(pwd)" 2>/dev/null || echo "unknown")}"
    local _path="${_path_override:-${PWD/$HOME/\~}}"
    local _ctx="${ACTIVE_CONTEXTS:-general}"

    # Timestamps
    local _ts _td
    _ts=$(date -u +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null || echo "")
    _td=$(date +"%H:%M:%S" 2>/dev/null || echo "")

    # JSON-escape the message (backslash, double-quote, newlines)
    local _safe_msg="$_msg"
    _safe_msg=${_safe_msg//\\/\\\\}
    _safe_msg=${_safe_msg//\"/\\\"}
    _safe_msg=${_safe_msg//$'\n'/ }
    _safe_msg=${_safe_msg//$'\r'/ }

    # Build JSON
    local _payload
    _payload=$(printf '{"type":"%s","project":"%s","projectPath":"%s","contexts":"%s","message":"%s","timestamp":"%s","time":"%s"}' \
        "$_type" "$_proj" "$_path" "$_ctx" "$_safe_msg" "$_ts" "$_td")

    # Transport 1 — named pipe (background, non-blocking)
    if _can_use_pipe; then
        ( printf '%s\n' "$_payload" > "$_PIPE" ) 2>/dev/null &
        return 0
    fi

    # Transport 2 — HTTP POST
    if command -v curl &>/dev/null; then
        if curl -sf --max-time 0.3 \
            "http://localhost:$_HTTP_PORT/api/event" \
            -X POST -H "Content-Type: application/json" \
            -d "$_payload" > /dev/null 2>&1; then
            return 0
        fi
    fi

    # Transport 3 — JSONL file (AFK/Docker fallback)
    mkdir -p "$_WD" 2>/dev/null || true
    printf '%s\n' "$_payload" >> "$_JSONL" 2>/dev/null || true
}

# ── update_hud_compliance ───────────────────────────────────────────────
# Called by compliance-audit skill at end of each audit.
# Usage: update_hud_compliance <pass_count> <fail_count> <warn_count>
update_hud_compliance() {
    local _pass="${1:-0}" _fail="${2:-0}" _warn="${3:-0}"
    local _total=$(( _pass + _fail + _warn ))
    local _rate=0
    [[ "$_total" -gt 0 ]] && _rate=$(( (_pass * 100) / _total ))

    local _proj
    _proj=$(basename "$(pwd)" 2>/dev/null || echo "unknown")
    local _ts
    _ts=$(date -u +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null || echo "")

    # Structured compliance_update event with data payload
    local _payload
    _payload=$(printf '{"type":"compliance_update","project":"%s","timestamp":"%s","data":{"pass":%d,"fail":%d,"warn":%d,"rate":%d},"message":"Audit: %d pass %d warn %d fail — rate: %d%%"}' \
        "$_proj" "$_ts" "$_pass" "$_fail" "$_warn" "$_rate" \
        "$_pass" "$_warn" "$_fail" "$_rate")

    if _can_use_pipe; then
        ( printf '%s\n' "$_payload" > "$_PIPE" ) 2>/dev/null &
    elif command -v curl &>/dev/null; then
        curl -sf --max-time 0.3 \
            "http://localhost:$_HTTP_PORT/api/event" \
            -X POST -H "Content-Type: application/json" \
            -d "$_payload" > /dev/null 2>&1 || true
    else
        printf '%s\n' "$_payload" >> "$_JSONL" 2>/dev/null || true
    fi
}

# Export for use in subshells
export -f _can_use_pipe                  2>/dev/null || true
export -f write_hud_event          2>/dev/null || true
export -f update_hud_compliance    2>/dev/null || true

# Backward-compatible alias (shipped name used by older callers)
write_compliance_event() {
    local _verdict="${1:-pass}"
    local _pass="${2:-0}" _fail="${3:-0}" _warn="${4:-0}"
    update_hud_compliance "$_pass" "$_fail" "$_warn"
}
export -f write_compliance_event 2>/dev/null || true

# ── emit_loaded_files ──────────────────────────────────────────────────────────
# Batch-emit read events for a list of loaded files.
# Usage: emit_loaded_files "global.instructions.md" "skills/do-work/SKILL.md" ...
emit_loaded_files() {
    for f in "$@"; do
        write_hud_event "read" "Read $f"
    done
}
export -f emit_loaded_files 2>/dev/null || true

# CLI mode — allow direct invocation for testing
if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    if [[ "${1:-}" == "compliance" ]]; then
        update_hud_compliance "${2:-0}" "${3:-0}" "${4:-0}"
    elif [[ "${1:-}" == "reads" ]]; then
        shift
        emit_loaded_files "$@"
    elif [[ "${1:-}" == "bridge-event" ]]; then
        # Bridge event — read JSON payload from stdin, forward to HUD daemon.
        _bridge_payload="$(cat)"
        if [[ -z "$_bridge_payload" ]]; then
            exit 0
        fi
        # Transport 1 — named pipe
        if _can_use_pipe; then
            ( printf '%s\n' "$_bridge_payload" > "$_PIPE" ) 2>/dev/null &
        # Transport 2 — HTTP POST
        elif command -v curl &>/dev/null; then
            curl -sf --max-time 0.3 \
                "http://localhost:$_HTTP_PORT/api/event" \
                -X POST -H "Content-Type: application/json" \
                -d "$_bridge_payload" > /dev/null 2>&1 || true
        fi
        # Transport 3 — always append to JSONL fallback
        mkdir -p "$_WD" 2>/dev/null || true
        printf '%s\n' "$_bridge_payload" >> "$_JSONL" 2>/dev/null || true
    else
        write_hud_event "${1:-info}" "${2:-}"
    fi
fi
