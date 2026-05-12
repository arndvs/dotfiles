#!/usr/bin/env bash
# FAIL_MODE: open
# typecheck.sh — Stop hook: run TypeScript type checker.
#
# Receives Claude Code Stop JSON on stdin.
# Blocks the agent from stopping (exit 2) if type errors exist.
# Skips silently if no tsconfig.json or no modified .ts/.tsx files.

set -euo pipefail

if ! command -v jq &>/dev/null; then
    exit 0
fi

INPUT=$(cat)
CWD=$(echo "$INPUT" | jq -r '.cwd // empty')

[[ -z "$CWD" ]] && exit 0
cd "$CWD" || exit 0

# Skip if no TypeScript config
[[ -f "tsconfig.json" ]] || exit 0

# Skip if no TypeScript files were modified
MODIFIED_TS=$(git diff --name-only HEAD 2>/dev/null | grep -E '\.(ts|tsx)$' || true)
[[ -z "$MODIFIED_TS" ]] && exit 0

# Prefer package.json typecheck script if available
if [[ -f "package.json" ]] && jq -e '.scripts["typecheck"] // .scripts["type-check"]' package.json &>/dev/null; then
    OUTPUT=$(npm run --silent typecheck 2>&1) || {
        echo "$OUTPUT" >&2
        echo '{"decision":"block","reason":"Type errors found. Fix before completing."}' >&2
        exit 2
    }
else
    OUTPUT=$(npx tsc --noEmit 2>&1) || {
        echo "$OUTPUT" >&2
        echo '{"decision":"block","reason":"Type errors found. Fix before completing."}' >&2
        exit 2
    }
fi

exit 0
