#!/usr/bin/env bash
# FAIL_MODE: open
# git-post-push.sh — PostToolUse hook: nag when no PR exists after push.
#
# Receives Claude Code PostToolUse JSON on stdin (matcher: Bash).
# If the command was a successful git push and no PR exists for the current
# branch, outputs an info reminder to create one.
# Fail-open: if gh CLI is missing or network fails, silently passes.

set -Eeuo pipefail
trap 'exit 0' ERR  # fail-open: any error → allow

if ! command -v jq &>/dev/null; then
    exit 0
fi

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty')

# cd into the hook event's working directory
EVENT_CWD=$(echo "$INPUT" | jq -r '.cwd // empty')
if [[ -n "$EVENT_CWD" ]]; then
    cd "$EVENT_CWD" || exit 0  # fail-open
fi

# Only trigger on git push commands (POSIX ERE: [[:space:]] not \s)
[[ -z "$COMMAND" ]] && exit 0

# Skip if the push failed (non-zero exit in tool_result)
EXIT_CODE=$(echo "$INPUT" | jq -r '.tool_result.exit_code // .tool_result.exitCode // "0"')
[[ "$EXIT_CODE" != "0" ]] && exit 0
# Only trigger on git push commands (POSIX ERE: [[:space:]] not \s)
# Allow global options (--no-pager, -c key=val) between git and push.
# Dangerous flags (-C/--git-dir/--work-tree) are handled below.
GIT_OPTS='([[:space:]]+(-[a-zA-Z]([[:space:]]+[^-[:space:]][^[:space:]]*)?|--[a-z][a-z-]*(=[^[:space:]]+)?))*'
if ! echo "$COMMAND" | grep -qE "(^|;|&&|\|\||\|)[[:space:]]*([A-Za-z_][A-Za-z0-9_]*=[^[:space:]]*[[:space:]]+)*git${GIT_OPTS}[[:space:]]+push([[:space:]]|\$)"; then
    exit 0
fi

# Skip git push invocations that explicitly target a different repo/work tree.
# This hook resolves branch/PR state from the hook event's cwd, so handling
# these forms would risk checking the wrong branch and missing the reminder.
# Allow global options before the repo-targeting flags (e.g. git --no-pager -C /repo push)
if echo "$COMMAND" | grep -qE "(^|;|&&|\|\||\|)[[:space:]]*([A-Za-z_][A-Za-z0-9_]*=[^[:space:]]*[[:space:]]+)*git${GIT_OPTS}([[:space:]]+(-C|--git-dir|--work-tree)([=[:space:]][^;&|[:space:]]+)*)+${GIT_OPTS}[[:space:]]+push([[:space:]]|\$)"; then
    exit 0
fi

# Skip if gh CLI not available
if ! command -v gh &>/dev/null; then
    exit 0
fi

# Skip if not in a git repo
if ! git rev-parse --is-inside-work-tree &>/dev/null; then
    exit 0
fi

BRANCH=$(git branch --show-current 2>/dev/null || echo "")
[[ -z "$BRANCH" ]] && exit 0

# Skip for base branches — no PR needed
if echo "$BRANCH" | grep -qxE 'main|master|dev|develop'; then
    exit 0
fi

# Portable timeout (macOS may lack timeout)
_timeout() {
    if command -v timeout &>/dev/null; then
        timeout "$@"
    else
        "${@:2}"
    fi
}

# Check if a PR already exists for this branch (timeout after 5s)
PR_COUNT=$(_timeout 5 gh pr list --head "$BRANCH" --state open --json number --jq 'length' 2>/dev/null || echo "")

# If gh failed or timed out, silently pass
[[ -z "$PR_COUNT" ]] && exit 0

if [[ "$PR_COUNT" == "0" ]]; then
    jq -cn --arg msg "📋 No PR exists for branch '$BRANCH'. Consider running: gh pr create" \
        '{"hookSpecificOutput":{"additionalContext":$msg}}' >&2
fi

exit 0
