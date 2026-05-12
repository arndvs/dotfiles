#!/usr/bin/env bash
# FAIL_MODE: closed
# secret-guard.sh — PreToolUse hook: block credential-exposing commands.
#
# Receives Claude Code PreToolUse JSON on stdin.
# Exits 2 (block) if the command would expose credentials.
# Defense-in-depth alongside deny rules in Claude Code settings.

set -euo pipefail

# --- Fail-closed trap: any unhandled error = deny ---
_fail_closed() {
    echo '{"hookSpecificOutput":{"permissionDecision":"deny","permissionDecisionReason":"secret-guard: unhandled error — denying (fail-closed)"}}' >&2
    exit 2
}
trap '_fail_closed' ERR

if ! command -v jq &>/dev/null; then
    exit 0  # jq required — skip gracefully if missing
fi

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty')

# Skip if no command (non-Bash tool calls pass through)
[[ -z "$COMMAND" ]] && exit 0

# Block commands that print credentials to stdout
if echo "$COMMAND" | grep -qiE '(^|\s|;|&&|\|)(echo|printf|cat)\s+.*\$[A-Za-z_]*(KEY|TOKEN|SECRET|PASSWORD|CREDENTIAL|AUTH)'; then
    echo '{"decision":"block","reason":"🔒 Blocked: command would expose credentials. Use run-with-secrets.sh for credential injection."}' >&2
    exit 2
fi

# Block bare env/printenv (dumps all env vars including secrets)
if echo "$COMMAND" | grep -qE '(^|\s|;|&&|\|)(printenv|env)\s*($|;|&&|\|)'; then
    echo '{"decision":"block","reason":"🔒 Blocked: bare env/printenv dumps all variables. Use echo $SPECIFIC_VAR instead."}' >&2
    exit 2
fi

# Block cat on secrets files
if echo "$COMMAND" | grep -qE 'cat\s+(\.env\.secrets|secrets/\.env|~/dotfiles/secrets/)'; then
    echo '{"decision":"block","reason":"🔒 Blocked: direct read of secrets file. Use run-with-secrets.sh for credential access."}' >&2
    exit 2
fi

# Block piped installs without inspection
if echo "$COMMAND" | grep -qE 'curl\s.*\|\s*(ba)?sh'; then
    echo '{"decision":"block","reason":"🔒 Blocked: piped install detected. Download first, inspect, then execute."}' >&2
    exit 2
fi

exit 0
