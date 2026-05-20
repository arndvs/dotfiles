#!/usr/bin/env bash
# FAIL_MODE: open
# test-gate.sh — PreToolUse hook: run tests before git commit.
#
# Receives Claude Code PreToolUse JSON on stdin (matcher: Bash).
# Blocks the commit (exit 2) if tests fail.
# Skips silently if no test script or no testable files modified.
#
# Complements typecheck.sh (Stop hook) by catching test failures
# before the commit happens, not after.

set -euo pipefail
trap 'exit 0' ERR  # fail-open: any error → allow

if ! command -v jq &>/dev/null; then
    exit 0
fi

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty')

# Skip if no command
[[ -z "$COMMAND" ]] && exit 0

# Only intercept git commit commands (allow global git options like -c key=val, --no-pager)
GIT_OPTS='([[:space:]]+(-[a-zA-Z]([[:space:]]+[^-[:space:]][^[:space:]]*)?|--[a-z][a-z-]*(=[^[:space:]]+)?))*'
if ! echo "$COMMAND" | grep -qE "(^|;|&&|\|\||\|)[[:space:]]*git${GIT_OPTS}[[:space:]]+commit([[:space:]]|$)"; then
    exit 0
fi

# Skip amend commits (typically fixups, not new code)
if echo "$COMMAND" | grep -qE "git${GIT_OPTS}[[:space:]]+commit.*--amend"; then
    exit 0
fi

CWD=$(echo "$INPUT" | jq -r '.cwd // empty')
[[ -z "$CWD" ]] && exit 0
cd "$CWD" || exit 0

# Skip if no package.json (not a JS/TS project)
[[ -f "package.json" ]] || exit 0

# Skip if no test script defined
if ! jq -e '.scripts.test' package.json &>/dev/null; then
    exit 0
fi

# Skip if no testable source files were modified
MODIFIED=$(git diff --cached --name-only 2>/dev/null || true)
[[ -z "$MODIFIED" ]] && MODIFIED=$(git diff --name-only HEAD 2>/dev/null || true)
TESTABLE=$(echo "$MODIFIED" | grep -E '\.(ts|tsx|js|jsx|mjs|cjs)$' || true)
[[ -z "$TESTABLE" ]] && exit 0

# Detect package manager
_pm="npm"
[[ -f "pnpm-lock.yaml" ]] && _pm="pnpm"
[[ -f "yarn.lock" ]] && _pm="yarn"
[[ -f "bun.lockb" ]] && _pm="bun"

# Fail-open: if the detected pm is not installed, allow the commit
if ! command -v "$_pm" &>/dev/null; then
    exit 0
fi

# Run tests — capture output to keep hook JSON clean, dump on failure
_test_out=$(mktemp)
if [[ "$_pm" == "bun" ]]; then
    _test_cmd=(bun run test)
else
    _test_cmd=("$_pm" test)
fi
if ! "${_test_cmd[@]}" >"$_test_out" 2>&1; then
    _tail=$(tail -20 "$_test_out" | tr '\n' ' ' | cut -c1-200)
    rm -f "$_test_out"
    jq -cn --arg reason "test-gate: tests failed. Fix failing tests before committing." \
           --arg context "$_tail" \
        '{"hookSpecificOutput":{"permissionDecision":"deny","permissionDecisionReason":$reason,"additionalContext":$context}}' >&2
    exit 2
fi
rm -f "$_test_out"

exit 0
