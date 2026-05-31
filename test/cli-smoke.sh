#!/usr/bin/env bash
# test/cli-smoke.sh — Verify all ctrl + shft commands dispatch and exit cleanly.
# Usage: bash test/cli-smoke.sh
# Exit: 0 if all pass, 1 if any fail.
set -euo pipefail

PASS=0
FAIL=0
SKIP=0
FAILURES=()
CMD_TIMEOUT=10  # seconds per command

# Detect timeout binary (macOS coreutils provides gtimeout)
TIMEOUT_BIN=""
if command -v timeout >/dev/null 2>&1; then
    TIMEOUT_BIN="timeout"
elif command -v gtimeout >/dev/null 2>&1; then
    TIMEOUT_BIN="gtimeout"
fi

_run_with_timeout() {
    if [[ -n "$TIMEOUT_BIN" ]]; then
        "$TIMEOUT_BIN" "$CMD_TIMEOUT" "$@"
    else
        "$@"
    fi
}

_test() {
    local label="$1"; shift
    local output ec
    if output=$(_run_with_timeout "$@" 2>&1); then
        PASS=$((PASS + 1))
        printf "  \033[32m✓\033[0m %s\n" "$label"
    else
        ec=$?
        if [[ $ec -eq 124 ]]; then
            FAIL=$((FAIL + 1))
            FAILURES+=("$label (timeout after ${CMD_TIMEOUT}s)")
            printf "  \033[31m✗\033[0m %s (timeout after %ds)\n" "$label" "$CMD_TIMEOUT"
        else
            FAIL=$((FAIL + 1))
            FAILURES+=("$label (exit $ec)")
            printf "  \033[31m✗\033[0m %s (exit %d)\n" "$label" "$ec"
        fi
    fi
}

_skip() {
    local label="$1"; shift
    local reason="$1"
    SKIP=$((SKIP + 1))
    printf "  \033[33m~\033[0m %s — %s\n" "$label" "$reason"
}

echo
echo "ctrl+shft CLI smoke test"
echo "════════════════════════════════════════════════"

# ── ctrl commands ──
echo
echo "ctrl — infrastructure"
echo "────────────────────────────────────────────────"

_test "ctrl --version"          ctrl --version
_test "ctrl help"               ctrl help
_test "ctrl status"             ctrl status
_test "ctrl check"              ctrl check

# HUD subcommands (daemon-independent)
_test "ctrl hud status"         ctrl hud status
_test "ctrl hud url"            ctrl hud url
_test "ctrl hud events"         ctrl hud events
_test "ctrl hud logs"           ctrl hud logs

# Commands that require interaction or are destructive — skip
_skip "ctrl context"            "sources detect-context.sh (slow filesystem scan)"
_skip "ctrl bootstrap"          "interactive / modifies system"
_skip "ctrl sync"               "runs git pull + bootstrap"
_skip "ctrl sync-settings"      "modifies VS Code settings"
_skip "ctrl new-client"         "interactive prompt"
_skip "ctrl migrate"            "writes report file"
_skip "ctrl uninstall"          "destructive"
_skip "ctrl verify-token"       "requires GitHub App credentials"

# HUD subcommands that need daemon running
_skip "ctrl hud start"          "starts daemon"
_skip "ctrl hud stop"           "stops daemon"
_skip "ctrl hud restart"        "restarts daemon"
_skip "ctrl hud open"           "opens browser"
_skip "ctrl hud --fg"           "blocks (foreground mode)"

# sheal-delegated — skip if sheal not installed
if command -v sheal &>/dev/null; then
    _test "ctrl retro (dispatch)"   ctrl retro --help
    _test "ctrl digest (dispatch)"  ctrl digest --help
    _test "ctrl cost (dispatch)"    ctrl cost --help
    _test "ctrl ask (dispatch)"     ctrl ask --help
    _test "ctrl learn (dispatch)"   ctrl learn --help
else
    _skip "ctrl retro"              "sheal not installed"
    _skip "ctrl digest"             "sheal not installed"
    _skip "ctrl cost"               "sheal not installed"
    _skip "ctrl ask"                "sheal not installed"
    _skip "ctrl learn"              "sheal not installed"
fi

# ── shft commands ──
echo
echo "shft — autonomous execution"
echo "────────────────────────────────────────────────"

_test "shft --version"          shft --version
_test "shft help"               shft help
_test "shft status"             shft status
_test "shft next"               shft next
_test "shft done"               shft done
_test "shft context"            shft context
_test "shft plan"               shft plan
_test "shft issues"             shft issues
_test "shft prompt"             shft prompt
_test "shft validate"           shft validate
_test "shft log"                shft log
_test "shft stop"               shft stop

_skip "shft run"                "starts HITL agent session"
_skip "shft afk"                "starts AFK agent loop"
_skip "shft plan edit"          "opens \$EDITOR"
_skip "shft plan clear"         "destructive (deletes plan)"
_skip "shft mint"               "requires GitHub App credentials"

# Proxy subcommands
_test "shft proxy"              shft proxy
_test "shft proxy status"       shft proxy status
_skip "shft proxy start"        "starts daemon"
_skip "shft proxy stop"         "stops daemon"

# ── Summary ──
echo
echo "════════════════════════════════════════════════"
printf "  \033[32m%d passed\033[0m  " "$PASS"
printf "\033[31m%d failed\033[0m  " "$FAIL"
printf "\033[33m%d skipped\033[0m\n" "$SKIP"

if [[ ${#FAILURES[@]} -gt 0 ]]; then
    echo
    echo "  Failures:"
    for f in "${FAILURES[@]}"; do
        printf "    \033[31m✗\033[0m %s\n" "$f"
    done
    echo
    exit 1
fi

echo
exit 0
