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

# --- Pattern: wrapper command prefix (sudo, env, command, builtin) ---
# sudo and env can carry flags with optional arguments (e.g. sudo -u root,
# env -u VARNAME FOO=bar, env --unset=VARNAME) before the wrapped command.
# GNU-style long options with inline =value (--opt=val) are also consumed.
WRAPPER_PREFIX='(sudo([[:space:]]+-[-a-zA-Z0-9]+(=[^[:space:]]+)?([[:space:]]+[^-[:space:]][^[:space:]]*)?)*[[:space:]]+|command[[:space:]]+|builtin[[:space:]]+|env([[:space:]]+-[-a-zA-Z0-9]+(=[^[:space:]]+)?([[:space:]]+[^-[:space:]=][^[:space:]]*)?)*([[:space:]]+[A-Za-z_][A-Za-z0-9_]*=[^[:space:]]*)*[[:space:]]+)*'

# --- Helper: deny output (JSON-safe via jq) ---
_deny() {
    jq -cn --arg reason "$1" '{"hookSpecificOutput":{"permissionDecision":"deny","permissionDecisionReason":$reason}}' >&2
    exit 2
}

# Block commands that print credentials to stdout
# Handles leading env assignments plus sudo/command/builtin prefixes
# (e.g. FOO=bar command echo $SECRET_KEY)
# Also handles env prefix with flags and assignments (e.g. env -u FOO sudo -u root echo $SECRET_KEY)
# Shell control keywords (then/do/else) are treated as command boundaries.
if echo "$COMMAND" | grep -qiE '((^|;|&&|\|\||\|)[[:space:]]*|(^|[[:space:]])(then|do|else)[[:space:]]+)([A-Za-z_][A-Za-z0-9_]*=[^[:space:]]*[[:space:]]+)*'"$WRAPPER_PREFIX"'(echo|printf|cat)[[:space:]]+.*\$\{?[A-Za-z0-9_]*(KEY|TOKEN|SECRET|PASSWORD|CREDENTIAL|AUTH)'; then
    _deny "🔒 Blocked: command would expose credentials. Use run-with-secrets.sh for credential injection."
fi

# Block bare env/printenv (dumps all env vars including secrets)
# Also catches leading env assignments: FOO=bar env, FOO=bar printenv
# Handles sudo/command/builtin prefixes and env-as-wrapper (env env, env printenv)
# Also catches assignment-only env invocations: env FOO=bar (still dumps env)
# Catches env with flags that still dump: env -0, env --null, env -v
# Catches env -u NAME (unsets one var but still dumps the rest)
# Each flag optionally consumes a following non-flag argument (e.g. -u NAME)
if echo "$COMMAND" | grep -qE '((^|;|&&|\|\||\|)[[:space:]]*|(^|[[:space:]])(then|do|else)[[:space:]]+)([A-Za-z_][A-Za-z0-9_]*=[^[:space:]]*[[:space:]]+)*'"$WRAPPER_PREFIX"'(printenv|env)([[:space:]]+(-[-a-zA-Z0-9]+([[:space:]]+[^-[:space:]=][^[:space:]]*)?|[A-Za-z_][A-Za-z0-9_]*=[^[:space:]]*))*[[:space:]]*($|;|&&|\|\||\|)'; then
    _deny "🔒 Blocked: bare env/printenv dumps all variables. Use echo \$SPECIFIC_VAR instead."
fi

# Block reads of secrets files (covers bare name + path prefixes)
# Handles leading env assignments, sudo, command, builtin, env prefixes
if echo "$COMMAND" | grep -qE '((^|;|&&|\|\||\|)[[:space:]]*|(^|[[:space:]])(then|do|else)[[:space:]]+)([A-Za-z_][A-Za-z0-9_]*=[^[:space:]]*[[:space:]]+)*'"$WRAPPER_PREFIX"'(cat|less|more|head|tail)[[:space:]]+(([^[:space:]]*/)?\.\.env\.secrets|([^[:space:]]*/)?secrets/\.env|~/dotfiles/secrets/)'; then
    _deny "🔒 Blocked: direct read of secrets file. Use run-with-secrets.sh for credential access."
fi

# Block piped installs without inspection
# Anchored to command boundaries so harmless mentions in echo/grep/docs do not match.
# Handles sudo, command, builtin, env prefixes before the executed curl.
# Allows leading VAR=value assignments before wrapper prefixes.
# Shell control keywords (then/do/else) are treated as command boundaries.
if echo "$COMMAND" | grep -qE '((^|;|&&|\|\||\|)[[:space:]]*|(^|[[:space:]])(then|do|else)[[:space:]]+)([A-Za-z_][A-Za-z0-9_]*=[^[:space:]]*[[:space:]]+)*'"$WRAPPER_PREFIX"'curl([[:space:]]+[^|;]+)?[[:space:]]*\|[[:space:]]*(ba)?sh([[:space:]]*($|;|&&|\|\||\|))'; then
    _deny "🔒 Blocked: piped install detected. Download first, inspect, then execute."
fi

exit 0
