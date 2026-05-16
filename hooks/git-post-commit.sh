#!/usr/bin/env bash
# FAIL_MODE: open
# git-post-commit.sh — PostToolUse hook: nag when commits are unpushed.
#
# Receives Claude Code PostToolUse JSON on stdin (matcher: Bash).
# If the command was a successful git commit and there are unpushed
# commits, outputs an info reminder with the count.
# Fail-open: if jq is missing or any error occurs, silently passes.

set -Eeuo pipefail
trap 'exit 0' ERR  # fail-open: any error → allow

if ! command -v jq &>/dev/null; then
    exit 0
fi

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty')
[[ -z "$COMMAND" ]] && exit 0

# cd into the hook event's working directory
EVENT_CWD=$(echo "$INPUT" | jq -r '.cwd // empty')
if [[ -n "$EVENT_CWD" ]]; then
    cd "$EVENT_CWD" || exit 0
fi

# Skip if the commit failed
EXIT_CODE=$(echo "$INPUT" | jq -r '.tool_result.exit_code // .tool_result.exitCode // "0"')
[[ "$EXIT_CODE" != "0" ]] && exit 0

# Only trigger on git commit commands
# Allow global options between git and commit
GIT_OPTS='([[:space:]]+(-[a-zA-Z]([[:space:]]+[^-[:space:]][^[:space:]]*)?|--[a-z][a-z-]*(=[^[:space:]]+)?))*'
if ! echo "$COMMAND" | grep -qE "(^|;|&&|\|\||\|)[[:space:]]*([A-Za-z_][A-Za-z0-9_]*=[^[:space:]]*[[:space:]]+)*git${GIT_OPTS}[[:space:]]+commit([[:space:]]|$)"; then
    exit 0
fi

# Not inside a git repo → skip
if ! git rev-parse --is-inside-work-tree &>/dev/null; then
    exit 0
fi

# No upstream configured → skip (can't count unpushed)
if ! git rev-parse --abbrev-ref '@{u}' &>/dev/null 2>&1; then
    exit 0
fi

# Count unpushed commits
UNPUSHED=$(git rev-list '@{u}..HEAD' 2>/dev/null | wc -l | tr -d ' ')
if [[ "$UNPUSHED" -gt 0 ]]; then
    BRANCH=$(git branch --show-current 2>/dev/null || echo "HEAD")
    cat <<EOF
{"hookSpecificOutput":{"additionalContext":"⚠️ ${UNPUSHED} unpushed commit(s) on ${BRANCH}. Remember to push before ending the session."}}
EOF
fi
