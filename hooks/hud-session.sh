#!/usr/bin/env bash
# FAIL_MODE: open
# hud-session.sh — SessionStart / Stop hook: emit HUD events.
#
# Receives Claude Code hook JSON on stdin containing session lifecycle data.
# Uses write-hud-state.sh for proper JSON escaping and transport.
# Zero tool-call cost — fires automatically.
#
# Hook events:
#   SessionStart → {session_id, cwd}
#   Stop         → {session_id, transcript_path}

set -euo pipefail
trap 'exit 0' ERR  # fail-open: any error → allow

DOTFILES="${DOTFILES:-$HOME/dotfiles}"

# Source the event emitter (provides write_hud_event with proper escaping)
source "$DOTFILES/bin/write-hud-state.sh"

# Read hook JSON from stdin
INPUT=$(cat)

# Extract fields (graceful fallback if jq is missing)
if command -v jq &>/dev/null; then
    HOOK_EVENT=$(echo "$INPUT" | jq -r '.hookEventName // .hook_event_name // .event // "unknown"')
    SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // .sessionId // "unknown"')
    CWD=$(echo "$INPUT" | jq -r '.cwd // .workingDirectory // empty')
    TRANSCRIPT=$(echo "$INPUT" | jq -r '.transcript_path // .transcriptPath // empty')
else
    # Minimal extraction without jq
    HOOK_EVENT="unknown"
    SESSION_ID="unknown"
    CWD=""
    TRANSCRIPT=""
fi

# cd to project dir so write_hud_event picks up the correct project name
if [[ -n "$CWD" ]]; then
    cd "$CWD" 2>/dev/null || true
fi

case "$HOOK_EVENT" in
    SessionStart)
        write_hud_event "info" "Session started (hook) — $SESSION_ID"
        ;;
    Stop)
        if [[ -n "$TRANSCRIPT" ]]; then
            write_hud_event "info" "Session ended (hook) — transcript: $TRANSCRIPT"
        else
            write_hud_event "info" "Session ended (hook) — $SESSION_ID"
        fi
        ;;
    *)
        write_hud_event "info" "Hook event: $HOOK_EVENT — $SESSION_ID"
        ;;
esac

# Allow the session to proceed
exit 0
