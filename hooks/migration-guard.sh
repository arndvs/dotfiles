#!/usr/bin/env bash
# FAIL_MODE: closed
# migration-guard.sh — PreToolUse hook: block migration commands without confirmation.
#
# Receives Claude Code PreToolUse JSON on stdin.
# Exits 2 (block) if a database migration targets a non-test database.

set -Eeuo pipefail

# --- Fail-closed trap: any unhandled error = deny ---
_fail_closed() {
    echo '{"hookSpecificOutput":{"permissionDecision":"deny","permissionDecisionReason":"migration-guard: unhandled error — denying (fail-closed)"}}' >&2
    exit 2
}
trap '_fail_closed' ERR

if ! command -v jq &>/dev/null; then
    echo '{"hookSpecificOutput":{"permissionDecision":"deny","permissionDecisionReason":"migration-guard: jq is required but not found. Install jq."}}' >&2
    exit 2
fi

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty')

[[ -z "$COMMAND" ]] && exit 0

# --- Helper: deny output (JSON-safe via jq) ---
_deny() {
    jq -cn --arg reason "$1" '{"hookSpecificOutput":{"permissionDecision":"deny","permissionDecisionReason":$reason}}' >&2
    exit 2
}

MIGRATION_PATTERN='(prisma[[:space:]]+migrate[[:space:]]+(deploy|dev)|prisma[[:space:]]+db[[:space:]]+push|artisan[[:space:]]+migrate|knex[[:space:]]+migrate|db-migrate[[:space:]]+up|typeorm[[:space:]]+migration:run|drizzle-kit[[:space:]]+push)'

# Detect migration commands across common ORMs
if echo "$COMMAND" | grep -qiE "$MIGRATION_PATTERN"; then
    # Check each command segment independently to prevent chained bypasses.
    # e.g. DATABASE_URL=test npx prisma migrate deploy && npx prisma migrate deploy
    # — the first segment has a test prefix but the second does not.
    has_unsafe_migration=false
    while IFS= read -r segment; do
        segment=$(echo "$segment" | sed 's/^[[:space:]]*//')
        [[ -z "$segment" ]] && continue
        if echo "$segment" | grep -qiE "$MIGRATION_PATTERN"; then
            # Allow test database targets — only match env assignments that directly
            # prefix the migration command (VAR=val cmd), not arbitrary command text.
            env_prefix=$(echo "$segment" | sed -n 's/^\(\([A-Za-z_][A-Za-z0-9_]*=[^[:space:]]*[[:space:]]*\)*\).*/\1/p')
            if [[ -n "$env_prefix" ]] && echo "$env_prefix" | grep -qiE '(DATABASE_URL.*test|localhost:5433([^0-9]|$)|:5433([^0-9]|$)|_test([^A-Za-z0-9_]|$))'; then
                continue  # This segment targets a test database
            fi
            has_unsafe_migration=true
        fi
    done <<< "$(echo "$COMMAND" | sed 's/&&/\n/g; s/;/\n/g; s/||/\n/g')"

    if [[ "$has_unsafe_migration" == "true" ]]; then
        _deny "⚠️ Migration detected. Confirm this targets the correct database before proceeding."
    fi
fi

exit 0
