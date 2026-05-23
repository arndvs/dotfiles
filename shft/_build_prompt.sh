#!/usr/bin/env bash
# _build_prompt.sh — Shared prompt builder for shft scripts.
# Sources into afk.sh / once.sh. Exports $PROMPT and $PROMPT_FILE.
#
# Requires: SCRIPT_DIR set by the caller.

PREVIOUS_COMMITS=$(git log --oneline -5 2>/dev/null || echo "No commits yet")

issues=$(gh issue list --state open --json number,title,body,comments 2>/dev/null || echo "[]")

# Sanitize issue content — escape ALL XML-like tags to prevent prompt injection.
# Our wrapper tags (<github-issues>, <previous-commits>) are added AFTER this step.
issues=$(printf '%s' "$issues" | sed -E 's|<(/?[a-zA-Z][a-zA-Z0-9_-]*[^>]*)>|\&lt;\1\&gt;|g')

_target_directive=""
if [[ -n "${SHFT_TARGET_ISSUE:-}" ]]; then
    _target_directive="
PRIORITY OVERRIDE: You MUST work on issue #${SHFT_TARGET_ISSUE} first. Skip task selection priority — this issue has been explicitly targeted. If the issue does not exist in the list above, report it and stop.
"
fi

PROMPT="<github-issues>
$issues
</github-issues>

<previous-commits>
$PREVIOUS_COMMITS
</previous-commits>
${_target_directive}
$(cat "$SCRIPT_DIR/prompt.md")"

# Clean up internal variables — only PROMPT and PROMPT_FILE should leak to caller
unset PREVIOUS_COMMITS issues _target_directive

# Write prompt to a temp file to avoid ARG_MAX limits on large backlogs
PROMPT_FILE=$(mktemp /tmp/shft-prompt.XXXXXX)
printf '%s' "$PROMPT" > "$PROMPT_FILE"
