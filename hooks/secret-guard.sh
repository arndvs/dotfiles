#!/usr/bin/env bash
# FAIL_MODE: closed
# secret-guard.sh — PreToolUse hook: block credential-exposing commands.
#
# Receives Claude Code PreToolUse JSON on stdin.
# Exits 2 (block) if the command would expose credentials.
# Defense-in-depth alongside deny rules in Claude Code settings.

set -Eeuo pipefail

# --- Fail-closed trap: any unhandled error = deny ---
_fail_closed() {
    echo '{"hookSpecificOutput":{"permissionDecision":"deny","permissionDecisionReason":"secret-guard: unhandled error — denying (fail-closed)"}}' >&2
    exit 2
}
trap '_fail_closed' ERR

if ! command -v jq &>/dev/null; then
    echo '{"hookSpecificOutput":{"permissionDecision":"deny","permissionDecisionReason":"secret-guard: jq is required but not found. Install jq."}}' >&2
    exit 2
fi

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty')

# Skip if no command (non-Bash tool calls pass through)
[[ -z "$COMMAND" ]] && exit 0

# --- Helper: deny output (JSON-safe via jq) ---
_deny() {
    jq -cn --arg reason "$1" '{"hookSpecificOutput":{"permissionDecision":"deny","permissionDecisionReason":$reason}}' >&2
    exit 2
}

# Block commands that print credentials to stdout
if echo "$COMMAND" | grep -qiE '(^|;|&&|\|\||\|)[[:space:]]*(sudo[[:space:]]+)?(echo|printf|cat)[[:space:]]+.*\$\{?[A-Za-z0-9_]*(KEY|TOKEN|SECRET|PASSWORD|CREDENTIAL|AUTH)'; then
    _deny "🔒 Blocked: command would expose credentials. Use run-with-secrets.sh for credential injection."
fi

# Block bare env/printenv (dumps all env vars including secrets)
if echo "$COMMAND" | grep -qE '(^|;|&&|\|\||\|)[[:space:]]*(printenv|env)[[:space:]]*($|;|&&|\|\||\|)'; then
    _deny "🔒 Blocked: bare env/printenv dumps all variables. Use echo \$SPECIFIC_VAR instead."
fi

# Block cat on secrets files (covers bare name + path prefixes)
if echo "$COMMAND" | grep -qE '(^|;|&&|\|\||\|)[[:space:]]*(sudo[[:space:]]+)?cat[[:space:]]+(([^[:space:]]*/)?\.env\.secrets|([^[:space:]]*/)?secrets/\.env|~/dotfiles/secrets/)'; then
    _deny "🔒 Blocked: direct read of secrets file. Use run-with-secrets.sh for credential access."
fi

# Block piped installs without inspection
if echo "$COMMAND" | grep -qE 'curl[[:space:]].*\|[[:space:]]*(ba)?sh'; then
    _deny "🔒 Blocked: piped install detected. Download first, inspect, then execute."
fi

exit 0
