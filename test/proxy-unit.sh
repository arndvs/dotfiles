#!/usr/bin/env bash
# test/proxy-unit.sh — Unit tests for proxy helper functions.
#
# Tests the pure-logic helpers extracted from shft and _proxy_env.sh:
#   _proxy_get / _proxy_set   — JSON state read/write
#   _proxy_load_key            — env var extraction
#   _proxy_running             — PID-first, health-fallback detection
#   _proxy_env_get             — jq > python > grep cascade
#   proxy stop                 — PID validation before kill
#   shft status                — port defaulting
#
# These tests use a temp directory for state, no real daemon required.
# Usage: bash test/proxy-unit.sh
set -euo pipefail
cd "$(git rev-parse --show-toplevel 2>/dev/null || echo "$(dirname "$0")/..")"

# ── Test harness ──────────────────────────────────────────────────────────────
PASS=0
FAIL=0
FAILURES=()

_ok() {
    PASS=$((PASS + 1))
    printf "  \033[32m✓\033[0m %s\n" "$1"
}
_fail() {
    FAIL=$((FAIL + 1))
    FAILURES+=("$1: $2")
    printf "  \033[31m✗\033[0m %s — %s\n" "$1" "$2"
}
assert_eq() {
    local label="$1" expected="$2" actual="$3"
    if [[ "$expected" == "$actual" ]]; then _ok "$label"
    else _fail "$label" "expected '$expected', got '$actual'"; fi
}
assert_contains() {
    local label="$1" needle="$2" haystack="$3"
    if [[ "$haystack" == *"$needle"* ]]; then _ok "$label"
    else _fail "$label" "expected to contain '$needle' in: $haystack"; fi
}
assert_not_contains() {
    local label="$1" needle="$2" haystack="$3"
    if [[ "$haystack" != *"$needle"* ]]; then _ok "$label"
    else _fail "$label" "should NOT contain '$needle' in: $haystack"; fi
}
assert_exit() {
    local label="$1" expected="$2" actual="$3"
    if [[ "$expected" == "$actual" ]]; then _ok "$label"
    else _fail "$label" "expected exit $expected, got $actual"; fi
}

# ── Temp environment ──────────────────────────────────────────────────────────
TMP=$(mktemp -d)
# Resolve to canonical path (MINGW mktemp returns /tmp/... but tools resolve to C:/...)
TMP=$(cd "$TMP" && pwd)
trap 'rm -rf "$TMP"' EXIT

# Source _lib.sh for green/yellow/red (needed by shft helpers)
source "$PWD/bin/_lib.sh"

# ── Set up the shft globals the helpers need ──────────────────────────────────
PROXY_STATE_DIR="$TMP/.shft"
PROXY_STATE_FILE="$PROXY_STATE_DIR/proxy.json"
PROXY_LOG_FILE="$PROXY_STATE_DIR/proxy.log"
PROXY_DEFAULT_PORT=4000
DOTFILES="$PWD"
VENV_DIR="$PWD/secrets/.venv"
if find_python 2>/dev/null; then SHFT_PYTHON="$PYTHON"; else SHFT_PYTHON=""; fi

# ═══════════════════════════════════════════════════════════════════════════════
echo
echo "Proxy unit tests"
echo "════════════════════════════════════════════════"

# ── Source the helper functions from shft (stop before CMD dispatch) ───────────
# We can't source the whole script (it runs main), so extract the functions.
# Strategy: define the functions inline by sourcing just the function block.

# _proxy_get / _proxy_set / _proxy_running / _proxy_load_key
# These are defined in shft between "# ── Proxy state helpers" and "# Require gh CLI"
eval "$(sed -n '/^# ── Proxy state helpers/,/^# Require gh CLI/{ /^# Require gh CLI/d; p; }' shft/shft)"

# ══════════════════════════════════════════════════════════════════════════════
echo
echo "_proxy_set + _proxy_get — JSON state round-trip"
echo "────────────────────────────────────────────────"

mkdir -p "$PROXY_STATE_DIR"
_proxy_set "enabled" "true"
assert_eq "set+get boolean" "true" "$(_proxy_get enabled)"

_proxy_set "port" "4000"
assert_eq "set+get number" "4000" "$(_proxy_get port)"

_proxy_set "dir" "proxy-dir-value"
assert_eq "set+get string" "proxy-dir-value" "$(_proxy_get dir)"

_proxy_set "pid" "12345"
assert_eq "set+get pid" "12345" "$(_proxy_get pid)"

# Missing field returns empty
assert_eq "get missing field" "" "$(_proxy_get nonexistent)"

# Missing state file returns empty
rm -f "$PROXY_STATE_FILE"
assert_eq "get from missing file" "" "$(_proxy_get enabled)"

# ══════════════════════════════════════════════════════════════════════════════
echo
echo "_proxy_load_key — extracts only LITELLM_MASTER_KEY"
echo "────────────────────────────────────────────────"

_fake_proxy_dir="$TMP/fake-proxy"
mkdir -p "$_fake_proxy_dir"

# Happy path
cat > "$_fake_proxy_dir/.env" <<'EOF'
LITELLM_MASTER_KEY=sk-test-key-abc123
OTHER_SECRET=should-not-leak
DATABASE_URL=postgres://localhost/db
EOF
_key=$(_proxy_load_key "$_fake_proxy_dir")
assert_eq "extracts master key" "sk-test-key-abc123" "$_key"

# Does NOT leak other vars
assert_not_contains "no OTHER_SECRET" "should-not-leak" "$_key"

# Missing .env
_missing_output=$(_proxy_load_key "$TMP/nonexistent" 2>&1 || true)
assert_contains "missing .env errors" "not found" "$_missing_output"

# Empty key
cat > "$_fake_proxy_dir/.env" <<'EOF'
OTHER_VAR=something
EOF
_empty_key=$(_proxy_load_key "$_fake_proxy_dir" 2>/dev/null || true)
assert_eq "empty key returns empty" "" "$_empty_key"

# ══════════════════════════════════════════════════════════════════════════════
echo
echo "_proxy_running — PID check first, health fallback"
echo "────────────────────────────────────────────────"

# With a valid PID (use our own PID — guaranteed alive)
mkdir -p "$PROXY_STATE_DIR"
_proxy_set "pid" "$$"
_proxy_set "port" "19999"  # unlikely to have anything on this port
ec=0; _proxy_running || ec=$?
assert_eq "own PID → running" "0" "$ec"

# With a dead PID and no health endpoint
_proxy_set "pid" "99999999"
_proxy_set "port" "19999"
ec=0; _proxy_running || ec=$?
if [[ $ec -ne 0 ]]; then _ok "dead PID + no health → not running (exit $ec)"
else _fail "dead PID + no health → not running" "expected non-zero exit, got 0"; fi

# With empty PID and no health endpoint
_proxy_set "pid" ""
_proxy_set "port" "19999"
ec=0; _proxy_running || ec=$?
if [[ $ec -ne 0 ]]; then _ok "empty PID + no health → not running (exit $ec)"
else _fail "empty PID + no health → not running" "expected non-zero exit, got 0"; fi

# ══════════════════════════════════════════════════════════════════════════════
echo
echo "proxy stop — PID validation before kill"
echo "────────────────────────────────────────────────"

# Simulate the proxy stop logic (extracted from shft)
_test_proxy_stop() {
    local _pid
    _pid=$(_proxy_get "pid")
    if [[ -n "$_pid" ]] && kill -0 "$_pid" 2>/dev/null; then
        echo "WOULD_KILL:$_pid"
    elif _proxy_running; then
        echo "STALE_PID"
    else
        echo "NOT_RUNNING"
    fi
}

# Empty PID should NOT attempt kill
_proxy_set "pid" ""
_proxy_set "port" "19999"
_stop_result=$(_test_proxy_stop)
assert_eq "stop with empty PID → not running" "NOT_RUNNING" "$_stop_result"

# Dead PID should NOT attempt kill
_proxy_set "pid" "99999999"
_proxy_set "port" "19999"
_stop_result=$(_test_proxy_stop)
assert_eq "stop with dead PID → not running" "NOT_RUNNING" "$_stop_result"

# Valid PID reports it would kill (not actually killing)
_proxy_set "pid" "$$"
_proxy_set "port" "19999"
_stop_result=$(_test_proxy_stop)
assert_eq "stop with valid PID → would kill" "WOULD_KILL:$$" "$_stop_result"

# ══════════════════════════════════════════════════════════════════════════════
echo
echo "status port — defaults to PROXY_DEFAULT_PORT"
echo "────────────────────────────────────────────────"

# Port set
_proxy_set "port" "5555"
_port=$(_proxy_get "port")
_port="${_port:-$PROXY_DEFAULT_PORT}"
assert_eq "explicit port used" "5555" "$_port"

# Port empty (the bug we fixed)
_proxy_set "port" ""
_port=$(_proxy_get "port")
_port="${_port:-$PROXY_DEFAULT_PORT}"
assert_eq "empty port defaults to 4000" "4000" "$_port"

# Port missing from state
rm -f "$PROXY_STATE_FILE"
_port=$(_proxy_get "port")
_port="${_port:-$PROXY_DEFAULT_PORT}"
assert_eq "missing port defaults to 4000" "4000" "$_port"

# ══════════════════════════════════════════════════════════════════════════════
echo
echo "_proxy_env_get — jq > python > grep cascade"
echo "────────────────────────────────────────────────"

# Set up state for _proxy_env_get (uses $_PROXY_STATE, not $PROXY_STATE_FILE)
_PROXY_STATE="$TMP/env-test-proxy.json"
cat > "$_PROXY_STATE" <<'EOF'
{
  "enabled": true,
  "port": 4000,
  "dir": "/home/user/proxy",
  "pid": "12345"
}
EOF

# Source _proxy_env_get from _proxy_env.sh
eval "$(sed -n '/^_proxy_env_get()/,/^}$/p' shft/_proxy_env.sh)"

assert_eq "env_get enabled" "true" "$(_proxy_env_get enabled)"
assert_eq "env_get port" "4000" "$(_proxy_env_get port)"
assert_eq "env_get dir" "/home/user/proxy" "$(_proxy_env_get dir)"
assert_eq "env_get pid" "12345" "$(_proxy_env_get pid)"
assert_eq "env_get missing" "" "$(_proxy_env_get nonexistent)"

# Missing file
_PROXY_STATE="$TMP/does-not-exist.json"
assert_eq "env_get missing file" "" "$(_proxy_env_get enabled)"

# ══════════════════════════════════════════════════════════════════════════════
echo
echo "Health endpoint consistency — all use /health/readiness"
echo "────────────────────────────────────────────────"

# Verify no stale /health (without /readiness) in the proxy scripts
_bad_health=$(grep -n '/health"' shft/_proxy_env.sh shft/shft 2>/dev/null | grep -v '/health/readiness' | grep -v '^#' | grep -v '# ' || true)
if [[ -z "$_bad_health" ]]; then
    _ok "no bare /health endpoints (all use /health/readiness)"
else
    _fail "found bare /health endpoint" "$_bad_health"
fi

# ══════════════════════════════════════════════════════════════════════════════
echo
echo "set -a; source .env — replaced by _proxy_load_key"
echo "────────────────────────────────────────────────"

# The old pattern leaked all env vars. Verify it's gone from the proxy start command.
_set_a_hits=$(grep -n 'set -a' shft/shft 2>/dev/null || true)
if [[ -z "$_set_a_hits" ]]; then
    _ok "no 'set -a' in shft (uses _proxy_load_key instead)"
else
    _fail "found 'set -a' in shft" "$_set_a_hits"
fi

# ══════════════════════════════════════════════════════════════════════════════
echo
echo "_require_srt/_require_docker gating — WSL/MSYS skip"
echo "────────────────────────────────────────────────"

# Verify the afk command section has the WSL/MSYS gate
_afk_block=$(sed -n '/^    afk)/,/^    ;;$/p' shft/shft)
assert_contains "afk has WSL check" "microsoft /proc/version" "$_afk_block"
assert_contains "afk has MSYS check" "uname -o" "$_afk_block"
assert_contains "afk conditional _require_srt" "_require_srt" "$_afk_block"
assert_contains "afk conditional _require_docker" "_require_docker" "$_afk_block"

# ══════════════════════════════════════════════════════════════════════════════
echo
echo "bridge/worker.py — git_credential_env spread order"
echo "────────────────────────────────────────────────"

# The fix: git_credential_env() is spread BEFORE PATH so our PATH wins
_worker_env_block=$(sed -n '/env = {/,/^    }/p' bridge/worker.py)
# git_credential_env must come before PATH
_cred_line=$(echo "$_worker_env_block" | grep -n 'git_credential_env' | head -1 | cut -d: -f1)
_path_line=$(echo "$_worker_env_block" | grep -n '"PATH"' | head -1 | cut -d: -f1)
if [[ -n "$_cred_line" ]] && [[ -n "$_path_line" ]] && [[ "$_cred_line" -lt "$_path_line" ]]; then
    _ok "git_credential_env spread before PATH (PATH wins)"
else
    _fail "git_credential_env must be spread BEFORE PATH" "cred line=$_cred_line, path line=$_path_line"
fi

# ══════════════════════════════════════════════════════════════════════════════
echo
echo "curl timeouts — _proxy_running has --max-time + --connect-timeout"
echo "────────────────────────────────────────────────"

_running_fn=$(sed -n '/^_proxy_running()/,/^}/p' shft/shft)
assert_contains "has --max-time" "--max-time" "$_running_fn"
assert_contains "has --connect-timeout" "--connect-timeout" "$_running_fn"

# Same in _proxy_env.sh daemon check
_env_daemon_check=$(sed -n '/Verify daemon is running/,/^fi$/p' shft/_proxy_env.sh)
assert_contains "env.sh daemon check has --max-time" "--max-time" "$_env_daemon_check"

# ══════════════════════════════════════════════════════════════════════════════
echo
echo "_proxy_env.sh — python shim guard"
echo "────────────────────────────────────────────────"

_env_get_fn=$(sed -n '/^_proxy_env_get()/,/^}/p' shft/_proxy_env.sh)
assert_contains "validates python3 with --version" "python3 --version" "$_env_get_fn"
assert_contains "validates python with --version" "python --version" "$_env_get_fn"
assert_contains "prefers jq first" "command -v jq" "$_env_get_fn"

# ══════════════════════════════════════════════════════════════════════════════
echo
echo "_proxy_running comment — says PID-first"
echo "────────────────────────────────────────────────"

_running_comment=$(grep -B1 '_proxy_running()' shft/shft | head -1)
assert_contains "comment says PID" "PID" "$_running_comment"
assert_not_contains "no misleading PID-based" "PID-based)" "$_running_comment"

# ══════════════════════════════════════════════════════════════════════════════
# Summary
echo
echo "════════════════════════════════════════════════"
printf "  \033[32m%d passed\033[0m  \033[31m%d failed\033[0m\n" "$PASS" "$FAIL"

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
