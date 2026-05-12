#!/usr/bin/env bash
# FAIL_MODE: open
# git-post-push.sh — PostToolUse hook: nag when no PR exists after push.
#
# Receives Claude Code PostToolUse JSON on stdin (matcher: Bash).
# If the command was a successful git push and no PR exists for the current
# branch, outputs an info reminder to create one.
# Fail-open: if gh CLI is missing or network fails, silently passes.

set -euo pipefail

if ! command -v jq &>/dev/null; then
    exit 0
fi

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty')

# Only trigger on git push commands
[[ -z "$COMMAND" ]] && exit 0
if ! echo "$COMMAND" | grep -qE 'git\s+push'; then
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

# Check if a PR already exists for this branch (timeout after 5s)
PR_COUNT=$(timeout 5 gh pr list --head "$BRANCH" --state open --json number --jq 'length' 2>/dev/null || echo "")

# If gh failed or timed out, silently pass
[[ -z "$PR_COUNT" ]] && exit 0

if [[ "$PR_COUNT" == "0" ]]; then
    echo "{\"hookSpecificOutput\":{\"additionalContext\":\"📋 No PR exists for branch '$BRANCH'. Consider running: gh pr create --base dev\"}}" >&2
fi

exit 0
