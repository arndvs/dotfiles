#!/usr/bin/env bash
# FAIL_MODE: open
# hud-reads.sh — Emit "read" events to the HUD daemon.
#
# Handles two Claude Code hook events:
#   PostToolUse(Read)    → fires after every file read
#   InstructionsLoaded   → fires when CLAUDE.md / rules / @-includes load
#
# Two tracking modes:
#   1. Dotfiles reads  → tracks which instructions/skills/rules/agents loaded
#   2. Project reads   → tracks file reads in external projects (for cross-project visibility)

set -euo pipefail
trap 'exit 0' ERR  # fail-open: any error → allow

INPUT=$(cat)

# jq required — bail without it
command -v jq &>/dev/null || exit 0

HOOK_EVENT=$(echo "$INPUT" | jq -r '.hookEventName // .hook_event_name // .event // "unknown"')

# Extract file path based on hook type
case "$HOOK_EVENT" in
    PostToolUse)
        FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty')
        ;;
    InstructionsLoaded)
        FILE_PATH=$(echo "$INPUT" | jq -r '.file_path // empty')
        ;;
    *)
        exit 0
        ;;
esac

[[ -z "$FILE_PATH" ]] && exit 0

# ── Normalize paths (Windows/MSYS compat) ────────────────────────────────────
normalize() {
    local p="$1"
    p="${p//\\//}"
    # C:/Users/... → /c/Users/...
    if [[ "$p" =~ ^([A-Za-z]):/ ]]; then
        p="/${BASH_REMATCH[1],,}/${p:3}"
    fi
    echo "$p"
}

FILE_PATH=$(normalize "$FILE_PATH")
DOTFILES="${DOTFILES:-$HOME/dotfiles}"
DOTFILES_N=$(normalize "$DOTFILES")

# Source event emitter
source "$DOTFILES/bin/write-hud-state.sh"

# ── Mode 1: Dotfiles file (instruction/skill/rule/agent) ─────────────────────
if [[ "$FILE_PATH" == "$DOTFILES_N"/* ]]; then
    REL_PATH="${FILE_PATH#$DOTFILES_N/}"

    # Filter: only HUD-relevant files
    case "$REL_PATH" in
        *.instructions.md|CLAUDE.md|CLAUDE.base.md) ;;
        instructions/*)                              ;;
        skills/*)                                    ;;
        rules/*)                                     ;;
        agents/*)                                    ;;
        *)                                           exit 0 ;;
    esac

    write_hud_event "read" "Read $REL_PATH"
    exit 0
fi

# ── Mode 2: External project file — track as project read ────────────────────
# Derive project from git root of the file, fallback to parent directory name.
_file_dir=$(dirname "$FILE_PATH")
_project=""
_project_path=""

# Walk up to find .git root
_dir="$_file_dir"
while [[ "$_dir" != "/" && "$_dir" != "." ]]; do
    if [[ -d "$_dir/.git" ]]; then
        _project=$(basename "$_dir")
        _project_path="${_dir/$HOME/~}"
        break
    fi
    _dir=$(dirname "$_dir")
done

# Fallback: use immediate parent directory name
if [[ -z "$_project" ]]; then
    _project=$(basename "$_file_dir")
    _project_path="${_file_dir/$HOME/~}"
fi

# Build relative path from project root for the message
if [[ -n "$_project_path" ]]; then
    _proj_abs="${_project_path/#\~/$HOME}"
    _rel="${FILE_PATH#$_proj_abs/}"
else
    _rel=$(basename "$FILE_PATH")
fi

write_hud_event "read" "Read $_rel" "$_project" "$_project_path"
exit 0
