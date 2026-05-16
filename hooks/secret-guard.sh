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

# --- Common wrapper prefix pattern ---
# Matches optional wrapper commands before the real command:
#   sudo   — with flags and optional flag arguments: sudo -E, sudo -u root
#   command, builtin — shell builtins
#   env    — with flags, flag arguments, and assignments: env -i, env -u VAR FOO=bar
# Flag arguments are consumed via optional non-flag token after each flag.
# The regex engine backtracks to avoid consuming the target command as a flag argument.
WRAPPER_PREFIX='(sudo([[:space:]]+-[-a-zA-Z0-9]+([[:space:]]+[^-[:space:]][^[:space:]]*)?)*[[:space:]]+|command[[:space:]]+|builtin[[:space:]]+|env([[:space:]]+-[-a-zA-Z0-9]+([[:space:]]+[^-[:space:]=][^[:space:]]*)?)*([[:space:]]+[A-Za-z_][A-Za-z0-9_]*=[^[:space:]]*)*[[:space:]]+)*'

# Block commands that print credentials to stdout
# Handles sudo (with options), command, builtin, env (with flags/assignments) prefixes
if echo "$COMMAND" | grep -qiE '(^|;|&&|\|\||\|)[[:space:]]*'"$WRAPPER_PREFIX"'(echo|printf|cat)[[:space:]]+.*\$\{?[A-Za-z0-9_]*(KEY|TOKEN|SECRET|PASSWORD|CREDENTIAL|AUTH)'; then
    _deny "🔒 Blocked: command would expose credentials. Use run-with-secrets.sh for credential injection."
fi

# Block bare env/printenv (dumps all env vars including secrets)
# Also catches leading env assignments: FOO=bar env, FOO=bar printenv
# Handles wrapper prefixes and env-as-wrapper (env env, env printenv)
# Also catches assignment-only env invocations: env FOO=bar (still dumps env)
# Catches env with flags that still dump: env -0, env -u VAR, env --null
if echo "$COMMAND" | grep -qE '(^|;|&&|\|\||\|)[[:space:]]*([A-Za-z_][A-Za-z0-9_]*=[^[:space:]]*[[:space:]]+)*'"$WRAPPER_PREFIX"'(printenv|env)([[:space:]]+(-[-a-zA-Z0-9]+([[:space:]]+[^-[:space:]=;|&][^[:space:];|&]*)?|[A-Za-z_][A-Za-z0-9_]*=[^[:space:]]*))*[[:space:]]*($|;|&&|\|\||\|)'; then
    _deny "🔒 Blocked: bare env/printenv dumps all variables. Use echo \$SPECIFIC_VAR instead."
fi

# Block reads of secrets files (covers bare name + path prefixes)
# Handles wrapper prefixes (including env with flags and assignments)
if echo "$COMMAND" | grep -qE '(^|;|&&|\|\||\|)[[:space:]]*'"$WRAPPER_PREFIX"'(cat|less|more|head|tail)[[:space:]]+(([^[:space:]]*/)?\.env\.secrets|([^[:space:]]*/)?secrets/\.env|~/dotfiles/secrets/)'; then
    _deny "🔒 Blocked: direct read of secrets file. Use run-with-secrets.sh for credential access."
fi

# Block piped installs without inspection
if echo "$COMMAND" | grep -qE 'curl[[:space:]].*\|[[:space:]]*(ba)?sh'; then
    _deny "🔒 Blocked: piped install detected. Download first, inspect, then execute."
fi

exit 0
