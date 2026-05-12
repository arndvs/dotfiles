#!/usr/bin/env bash
# FAIL_MODE: open
# plan-quality-gate.sh — PreToolUse hook: warn when scaffolding without a plan.
#
# Receives Claude Code PreToolUse JSON on stdin (matcher: Bash).
# When the command creates directories or scaffolds projects (mkdir, npx create-,
# npm init, etc.), checks if a plan file exists at the git root. Emits an
# info warning if no plan is found. Never blocks.
# Fail-open: non-git directories and missing tools silently pass.

set -euo pipefail

if ! command -v jq &>/dev/null; then
    exit 0
fi

INPUT=$(cat)

TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name // empty')
[[ "$TOOL_NAME" == "Bash" ]] || exit 0

COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty')
[[ -n "$COMMAND" ]] || exit 0

# Only trigger on scaffolding/creation patterns
SCAFFOLD_PATTERN='mkdir|npx create-|npm init|yarn create|pnpm create|cookiecutter|degit|git clone'
if ! echo "$COMMAND" | grep -qE "$SCAFFOLD_PATTERN"; then
    exit 0
fi

# Must be inside a git repo
GIT_ROOT=$(git rev-parse --show-toplevel 2>/dev/null) || exit 0

# Check for plan files at git root
PLAN_FOUND=false
for candidate in PLAN.md plan.md .plan.md docs/PLAN.md docs/plan.md; do
    if [[ -f "$GIT_ROOT/$candidate" ]]; then
        PLAN_FOUND=true
        break
    fi
done

if [[ "$PLAN_FOUND" == "true" ]]; then
    exit 0
fi

# No plan found — emit info warning (never blocks)
MSG="⚠️ No plan file found (PLAN.md, docs/PLAN.md). Consider documenting your approach before scaffolding."
echo "{\"hookSpecificOutput\":{\"additionalContext\":\"$MSG\"}}" >&2
exit 0
