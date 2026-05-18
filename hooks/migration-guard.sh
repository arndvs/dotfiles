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

# Runner prefix — package managers that invoke migration tools.
# Allow common runner flags so invocations such as:
#   npx --yes prisma migrate deploy
#   pnpm exec --package foo prisma migrate deploy
# still match the anchored migration check.
RUNNER_OPT='[[:space:]]+--?[[:alnum:]][-[:alnum:]]*(=[^[:space:]]+)?([[:space:]]+[^-[:space:]][^[:space:]]*)?'
RUNNER_OPTS="(${RUNNER_OPT})*"
RUNNER_PREFIX="(npx${RUNNER_OPTS}[[:space:]]+|yarn(${RUNNER_OPT})*([[:space:]]+(dlx|run))?(${RUNNER_OPT})*[[:space:]]+|pnpm(${RUNNER_OPT})*([[:space:]]+(dlx|exec|run))?(${RUNNER_OPT})*[[:space:]]+|bunx${RUNNER_OPTS}[[:space:]]+|php[[:space:]]+)?"

# Wrapper prefix (simplified) — sudo, env, command, builtin with GNU-style options
WRAPPER_PREFIX='(sudo([[:space:]]+-[-a-zA-Z0-9]+(=[^[:space:]]+)?([[:space:]]+[^-[:space:]][^[:space:]]*)?)*[[:space:]]+|command[[:space:]]+|builtin[[:space:]]+|env([[:space:]]+-[-a-zA-Z0-9]+(=[^[:space:]]+)?([[:space:]]+[^-[:space:]=][^[:space:]]*)?)*([[:space:]]+[A-Za-z_][A-Za-z0-9_]*=[^[:space:]]*)*[[:space:]]+)*'

# --- Deny nested shell migration invocations outright ---
# A nested shell like `bash -c 'npx prisma migrate deploy'` cannot be reliably
# parsed for per-segment env-prefix checks. Deny and require direct invocation.
NESTED_SHELL_MIGRATION='(bash|sh|dash|ksh|zsh)([[:space:]]+-[-a-zA-Z0-9]+(=[^[:space:]]+)?)*[[:space:]]+-[[:alnum:]]*c[[:alnum:]]*[[:space:]]+'
if echo "$COMMAND" | grep -qiE "${NESTED_SHELL_MIGRATION}.*${MIGRATION_PATTERN}"; then
    _deny "⚠️ Blocked: don't wrap migration commands in nested shells (bash -c, sh -c). Invoke the migration tool directly so the guard can validate the target database."
fi

# Detect migration commands across common ORMs
# Quick-reject: skip early if no migration keyword anywhere in the command
if echo "$COMMAND" | grep -qiE "$MIGRATION_PATTERN"; then
    # Check each command segment independently to prevent chained bypasses.
    # e.g. DATABASE_URL=test npx prisma migrate deploy && npx prisma migrate deploy
    # — the first segment has a test prefix but the second does not.
    # Also split on pipes (|) because env assignments only apply to the first
    # pipeline component: `DATABASE_URL=test echo ok | npx prisma migrate deploy`
    # gives the test URL only to `echo`, not to the migration on the pipe's RHS.
    has_unsafe_migration=false
    while IFS= read -r segment; do
        segment=$(echo "$segment" | sed 's/^[[:space:]]*//')
        [[ -z "$segment" ]] && continue
        # Shell control keywords (then/do/else) can start a segment after splitting
        # on ;/&&/||/|. Strip them so the anchored check sees the actual command.
        # Also strip shell grouping tokens: ( { $(
        segment=$(echo "$segment" | sed -E 's/^(\(|[{]|\$\()[[:space:]]*//; s/^(then|do|else)[[:space:]]+//')
        if echo "$segment" | grep -qiE "^([A-Za-z_][A-Za-z0-9_]*=[^[:space:]]*[[:space:]]+)*${WRAPPER_PREFIX}${RUNNER_PREFIX}${MIGRATION_PATTERN}"; then
            # Allow test database targets — only match env assignments that directly
            # prefix the migration command (VAR=val cmd), not arbitrary command text.
            # Restrict to DATABASE_URL specifically — a generic *_test= pattern would
            # let FOO_TEST=1 bypass the guard without changing the actual DB target.
            # Also deny the exemption when env -i or env -u DATABASE_URL appears,
            # since those strip the assignment before the migration runner sees it.
            # Require an explicit test marker in the URL (delimited by non-alphanumeric
            # characters, e.g. /test, _test, -test) rather than matching any occurrence
            # of "test" (which would pass 'contest', 'latest', etc.).
            env_prefix=$(echo "$segment" | sed -n 's/^\(\([A-Za-z_][A-Za-z0-9_]*=[^[:space:]]*[[:space:]]*\)*\).*/\1/p')
            if [[ -n "$env_prefix" ]] && echo "$env_prefix" | grep -qiE '(^|[[:space:]])DATABASE_URL=[^[:space:]]*([^[:alnum:]]test([^[:alnum:]]|$)|localhost:5433([^0-9]|$)|:5433([^0-9]|$))'; then
                # env -i wipes the entire environment; env -u DATABASE_URL unsets it.
                # Either form means the migration runner won't receive the test URL.
                if echo "$segment" | grep -qE 'env[[:space:]]+-i([[:space:]]|$)|env[[:space:]]+-u[[:space:]]+DATABASE_URL([[:space:]]|$)|env[[:space:]]+--ignore-environment([[:space:]]|$)|env[[:space:]]+--unset=DATABASE_URL([[:space:]]|$)'; then
                    has_unsafe_migration=true
                else
                    continue  # This segment explicitly targets a test database
                fi
            fi
            has_unsafe_migration=true
        fi
    done <<< "$(echo "$COMMAND" | sed 's/&&/\n/g; s/;/\n/g; s/||/\n/g; s/|/\n/g')"

    if [[ "$has_unsafe_migration" == "true" ]]; then
        _deny "⚠️ Migration detected. Confirm this targets the correct database before proceeding."
    fi
fi

exit 0
