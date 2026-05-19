#!/usr/bin/env bash
# test-helpers.sh — Shared test utilities for hook tests.
#
# Source this file in test scripts:
#   source "$(dirname "$0")/test-helpers.sh"
#
# Provides:
#   run_hook <hook-script> <json-input>  — feeds JSON to hook, captures output
#   assert_allow <test-name>             — last hook exited 0, no deny
#   assert_deny <test-name> [pattern]    — last hook exited 2, permissionDecision=deny
#   assert_warn <test-name> [pattern]    — last hook exited 0, additionalContext present
#   make_tmp_repo                        — creates temp git repo, returns path
#   cleanup_tmp_repos                    — removes all temp repos
#   report                               — prints pass/fail summary, exits 1 on failure

set -euo pipefail

TESTS_PASSED=0
TESTS_FAILED=0
TESTS_TOTAL=0
TMP_REPOS=()

# Colors (if terminal supports it)
if [[ -t 1 ]]; then
    GREEN='\033[0;32m'
    RED='\033[0;31m'
    RESET='\033[0m'
else
    GREEN='' RED='' RESET=''
fi

# --- Core: run a hook ---
HOOK_STDOUT=""
HOOK_STDERR=""
HOOK_EXIT=0
_HOOK_STDERR_FILE=""

run_hook() {
    local hook_script="$1"
    local json_input="$2"
    HOOK_EXIT=0
    _HOOK_STDERR_FILE=$(mktemp)
    # Capture stdout and stderr separately
    HOOK_STDOUT=$(printf '%s' "$json_input" | bash "$hook_script" 2>"$_HOOK_STDERR_FILE") || HOOK_EXIT=$?
    HOOK_STDERR=$(cat "$_HOOK_STDERR_FILE" 2>/dev/null || true)
    rm -f "$_HOOK_STDERR_FILE"
}

# --- Parse hook output ---
parse_decision() {
    local combined="${HOOK_STDOUT}${HOOK_STDERR}"
    echo "$combined" | jq -r '.hookSpecificOutput.permissionDecision // empty' 2>/dev/null || true
}

parse_context() {
    local combined="${HOOK_STDOUT}${HOOK_STDERR}"
    echo "$combined" | jq -r '.hookSpecificOutput.additionalContext // empty' 2>/dev/null || true
}

parse_reason() {
    local combined="${HOOK_STDOUT}${HOOK_STDERR}"
    echo "$combined" | jq -r '.hookSpecificOutput.permissionDecisionReason // empty' 2>/dev/null || true
}

# --- Assertions ---
assert_allow() {
    local test_name="$1"
    TESTS_TOTAL=$((TESTS_TOTAL + 1))
    if [[ "$HOOK_EXIT" -ne 0 ]]; then
        TESTS_FAILED=$((TESTS_FAILED + 1))
        printf "${RED}FAIL${RESET} %s — expected exit 0 but got %d\n" "$test_name" "$HOOK_EXIT"
        return
    fi
    local decision
    decision=$(parse_decision)
    if [[ "$decision" == "deny" ]]; then
        TESTS_FAILED=$((TESTS_FAILED + 1))
        printf "${RED}FAIL${RESET} %s — expected ALLOW but got DENY: %s\n" "$test_name" "$(parse_reason)"
        return
    fi
    TESTS_PASSED=$((TESTS_PASSED + 1))
    printf "${GREEN}PASS${RESET} %s\n" "$test_name"
}

assert_deny() {
    local test_name="$1"
    local pattern="${2:-}"
    TESTS_TOTAL=$((TESTS_TOTAL + 1))
    if [[ "$HOOK_EXIT" -ne 2 ]]; then
        TESTS_FAILED=$((TESTS_FAILED + 1))
        printf "${RED}FAIL${RESET} %s — expected exit 2 but got %d\n" "$test_name" "$HOOK_EXIT"
        return
    fi
    local decision
    decision=$(parse_decision)
    if [[ "$decision" != "deny" ]]; then
        TESTS_FAILED=$((TESTS_FAILED + 1))
        printf "${RED}FAIL${RESET} %s — expected DENY but got ALLOW (exit=%d)\n" "$test_name" "$HOOK_EXIT"
        return
    fi
    if [[ -n "$pattern" ]]; then
        local reason
        reason=$(parse_reason)
        if ! echo "$reason" | grep -qiE "$pattern"; then
            TESTS_FAILED=$((TESTS_FAILED + 1))
            printf "${RED}FAIL${RESET} %s — denied but reason doesn't match '%s': %s\n" "$test_name" "$pattern" "$reason"
            return
        fi
    fi
    TESTS_PASSED=$((TESTS_PASSED + 1))
    printf "${GREEN}PASS${RESET} %s\n" "$test_name"
}

assert_warn() {
    local test_name="$1"
    local pattern="${2:-}"
    TESTS_TOTAL=$((TESTS_TOTAL + 1))
    if [[ "$HOOK_EXIT" -ne 0 ]]; then
        TESTS_FAILED=$((TESTS_FAILED + 1))
        printf "${RED}FAIL${RESET} %s — expected exit 0 but got %d\n" "$test_name" "$HOOK_EXIT"
        return
    fi
    local context
    context=$(parse_context)
    if [[ -z "$context" ]]; then
        TESTS_FAILED=$((TESTS_FAILED + 1))
        printf "${RED}FAIL${RESET} %s — expected WARN (additionalContext) but none found\n" "$test_name"
        return
    fi
    if [[ -n "$pattern" ]]; then
        if ! echo "$context" | grep -qiE "$pattern"; then
            TESTS_FAILED=$((TESTS_FAILED + 1))
            printf "${RED}FAIL${RESET} %s — warned but context doesn't match '%s': %s\n" "$test_name" "$pattern" "$context"
            return
        fi
    fi
    TESTS_PASSED=$((TESTS_PASSED + 1))
    printf "${GREEN}PASS${RESET} %s\n" "$test_name"
}

# --- Temp repo management ---
make_tmp_repo() {
    local tmp_dir
    tmp_dir=$(mktemp -d)
    git -C "$tmp_dir" init -b main --quiet 2>/dev/null
    git -C "$tmp_dir" config user.email "test@test.com"
    git -C "$tmp_dir" config user.name "Test"
    touch "$tmp_dir/README.md"
    git -C "$tmp_dir" add . && git -C "$tmp_dir" commit -m "init" --quiet 2>/dev/null
    TMP_REPOS+=("$tmp_dir")
    echo "$tmp_dir"
}

cleanup_tmp_repos() {
    for dir in "${TMP_REPOS[@]}"; do
        rm -rf "$dir" 2>/dev/null || true
    done
}

# --- Build JSON input for hooks ---
make_pretooluse_json() {
    local command="$1"
    local cwd="${2:-.}"
    jq -cn --arg cmd "$command" --arg cwd "$cwd" '{
        "tool_name": "Bash",
        "tool_input": {"command": $cmd},
        "cwd": $cwd
    }'
}

make_posttooluse_json() {
    local command="$1"
    local cwd="${2:-.}"
    local exit_code="${3:-0}"
    jq -cn --arg cmd "$command" --arg cwd "$cwd" --arg ec "$exit_code" '{
        "tool_name": "Bash",
        "tool_input": {"command": $cmd},
        "tool_result": {"exit_code": $ec},
        "cwd": $cwd
    }'
}

# --- Report ---
report() {
    echo ""
    echo "---"
    printf "%d tests: ${GREEN}%d passed${RESET}" "$TESTS_TOTAL" "$TESTS_PASSED"
    if [[ $TESTS_FAILED -gt 0 ]]; then
        printf ", ${RED}%d failed${RESET}" "$TESTS_FAILED"
    fi
    echo ""

    cleanup_tmp_repos

    if [[ $TESTS_FAILED -gt 0 ]]; then
        exit 1
    fi
    exit 0
}

trap 'cleanup_tmp_repos' EXIT
