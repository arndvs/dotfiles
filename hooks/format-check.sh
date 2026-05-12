#!/usr/bin/env bash
# FAIL_MODE: open
# format-check.sh — Stop hook: run project formatter on modified files.
#
# Receives Claude Code Stop JSON on stdin.
# Detects Biome, Prettier, or ESLint and formats modified files.
# Non-blocking — always exits 0. Formatting errors surface in output only.

set -euo pipefail
trap 'exit 0' ERR  # fail-open: any error → allow

if ! command -v jq &>/dev/null; then
    exit 0
fi

INPUT=$(cat)
CWD=$(echo "$INPUT" | jq -r '.cwd // empty')

[[ -z "$CWD" ]] && exit 0
cd "$CWD" || exit 0

# Get modified files (staged + unstaged relative to HEAD)
MODIFIED=$(git diff --name-only HEAD 2>/dev/null || true)
[[ -z "$MODIFIED" ]] && exit 0

# Detect and run formatter (first match wins)
if [[ -f "biome.json" ]] || [[ -f "biome.jsonc" ]]; then
    echo "$MODIFIED" | xargs npx biome format --write 2>/dev/null || true
elif [[ -f ".prettierrc" ]] || [[ -f ".prettierrc.json" ]] || [[ -f ".prettierrc.yml" ]] || \
     [[ -f "prettier.config.js" ]] || [[ -f "prettier.config.mjs" ]] || [[ -f "prettier.config.cjs" ]]; then
    echo "$MODIFIED" | xargs npx prettier --write 2>/dev/null || true
fi

# Run ESLint --fix if configured (independent of formatter — linter, not formatter)
if [[ -f "eslint.config.js" ]] || [[ -f "eslint.config.mjs" ]] || [[ -f "eslint.config.cjs" ]] || \
   [[ -f ".eslintrc.js" ]] || [[ -f ".eslintrc.json" ]] || [[ -f ".eslintrc.yml" ]]; then
    LINTABLE=$(echo "$MODIFIED" | grep -E '\.(js|jsx|ts|tsx|mjs|cjs)$' || true)
    [[ -n "$LINTABLE" ]] && echo "$LINTABLE" | xargs npx eslint --fix 2>/dev/null || true
fi

exit 0
