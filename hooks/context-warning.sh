#!/usr/bin/env bash
# FAIL_MODE: open
# context-warning.sh — UserPromptSubmit hook: inject graduated context warnings.
#
# ⚠️  STUB — requires statusLine experiment to confirm input format.
# Run hooks/experiments/statusline-probe.sh first, then fill in the USED_PCT
# source below.
#
# This hook reads the current context usage percentage (written to a state file
# by a statusLine command) and injects graduated warnings via additionalContext.
# It does NOT block the prompt — blocking erases the user's prompt from context.
#
# Thresholds:
#   40% — advisory: start wrapping up the current slice
#   70% — urgent:  follow the handoff protocol now
#
# The statusLine command must write the percentage to the state file on each
# update. This hook reads it. The two scripts form a bridge:
#   statusLine → writes ~/.claude/context-pct → context-warning.sh reads it

set -euo pipefail

STATE_FILE="$HOME/.claude/context-pct"

# Read the percentage from the state file (written by statusLine command)
# TODO: replace this with the confirmed source after running the probe
if [[ -f "$STATE_FILE" ]]; then
    USED_PCT=$(cat "$STATE_FILE" 2>/dev/null | tr -d '[:space:]')
else
    exit 0  # no state file = no statusLine bridge configured
fi

# Validate it's a number
if ! [[ "$USED_PCT" =~ ^[0-9]+$ ]]; then
    exit 0
fi

if (( USED_PCT >= 70 )); then
    cat <<EOF
{
  "hookSpecificOutput": {
    "hookEventName": "UserPromptSubmit",
    "additionalContext": "🔴 CONTEXT WARNING: Usage at ${USED_PCT}%. Follow the handoff protocol NOW. Commit all work, write remaining plan to working/, provide the pickup command for a fresh session."
  }
}
EOF
    exit 0
fi

if (( USED_PCT >= 40 )); then
    cat <<EOF
{
  "hookSpecificOutput": {
    "hookEventName": "UserPromptSubmit",
    "additionalContext": "⚠️ CONTEXT WARNING: Usage at ${USED_PCT}%. Start wrapping up this slice. Consider committing current work and starting a fresh session soon."
  }
}
EOF
    exit 0
fi

exit 0
