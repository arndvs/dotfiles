#!/usr/bin/env bash
# FAIL_MODE: closed
# migration-guard.sh — PreToolUse hook: block migration commands without confirmation.
#
# Receives Claude Code PreToolUse JSON on stdin.
# Exits 2 (block) if a database migration targets a non-test database.

set -euo pipefail

# --- Fail-closed trap: any unhandled error = deny ---
_fail_closed() {
    echo '{"hookSpecificOutput":{"permissionDecision":"deny","permissionDecisionReason":"migration-guard: unhandled error — denying (fail-closed)"}}' >&2
    exit 2
}
trap '_fail_closed' ERR

if ! command -v jq &>/dev/null; then
    exit 0  # jq required — skip gracefully if missing
fi

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty')

[[ -z "$COMMAND" ]] && exit 0

# Detect migration commands across common ORMs
if echo "$COMMAND" | grep -qiE '(prisma\s+migrate\s+(deploy|dev)|prisma\s+db\s+push|artisan\s+migrate|knex\s+migrate|db-migrate\s+up|typeorm\s+migration:run|drizzle-kit\s+push)'; then
    # Allow test database targets
    if echo "$COMMAND" | grep -qiE '(DATABASE_URL.*test|localhost:5433|:5433|_test\b)'; then
        exit 0
    fi

    echo '{"decision":"block","reason":"⚠️ Migration detected. Confirm this targets the correct database before proceeding."}' >&2
    exit 2
fi

exit 0
