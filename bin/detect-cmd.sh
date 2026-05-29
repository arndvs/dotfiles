#!/usr/bin/env bash
# detect-cmd.sh — Inject cmd business context into the active client output.
#
# Called by detect-client.sh after client detection. Reads the `cmd-venture:`
# field from the active client's client.instructions.md and appends
# @-references to the matched venture's context files from ~/cmd/.
#
# When no client is active or no cmd-venture field is set, this is a no-op.
#
# Usage:
#   source ~/dotfiles/bin/detect-cmd.sh "$ACTIVE_CLIENT"
#   (called automatically by detect-client.sh)

# Guard: when sourced, save/restore shell options
if [[ "${BASH_SOURCE[0]}" != "$0" ]]; then
    _dcmd_oldopts=$(set +o)
    trap 'eval "$_dcmd_oldopts"; unset _dcmd_oldopts' RETURN
fi
set -euo pipefail

DOTFILES="${DOTFILES:-$HOME/dotfiles}"
CMD_DIR="${CMD_DIR:-$HOME/cmd}"
WORKING_DIR="$DOTFILES/working"
OUTPUT_FILE="$WORKING_DIR/active-client.md"

_dcmd_client="${1:-}"

# Bail if cmd repo doesn't exist — graceful no-op
[[ -d "$CMD_DIR" ]] || return 0 2>/dev/null || exit 0

# Bail if no active client
[[ -n "$_dcmd_client" ]] || return 0 2>/dev/null || exit 0

# Read cmd-venture field from client.instructions.md frontmatter
_dcmd_client_file="$DOTFILES/clients/$_dcmd_client/client.instructions.md"
[[ -f "$_dcmd_client_file" ]] || return 0 2>/dev/null || exit 0

_dcmd_venture=""
while IFS= read -r line; do
    if [[ "$line" =~ ^cmd-venture:[[:space:]]*(.+)$ ]]; then
        _dcmd_venture="${BASH_REMATCH[1]}"
        _dcmd_venture="${_dcmd_venture%%[[:space:]]}"
        _dcmd_venture="${_dcmd_venture%%\"}"
        _dcmd_venture="${_dcmd_venture##\"}"
        break
    fi
    # Stop reading after frontmatter closes
    [[ "$line" == "---" ]] && [[ -n "$_dcmd_venture" || "$REPLY" -gt 1 ]] && break
done < "$_dcmd_client_file"

# Bail if no cmd-venture mapping
[[ -n "$_dcmd_venture" ]] || return 0 2>/dev/null || exit 0

# Bail if the venture directory doesn't exist in cmd
_dcmd_venture_dir="$CMD_DIR/ventures/$_dcmd_venture"
[[ -d "$_dcmd_venture_dir" ]] || return 0 2>/dev/null || exit 0

# Append cmd context to active-client.md
{
    printf '\n## cmd — Venture Context\n\n'
    printf 'Active venture: `%s`\n\n' "$_dcmd_venture"

    if [[ -f "$_dcmd_venture_dir/README.md" ]]; then
        printf '@%s/ventures/%s/README.md\n' "$CMD_DIR" "$_dcmd_venture"
    fi
    if [[ -f "$_dcmd_venture_dir/decisions.md" ]]; then
        printf '@%s/ventures/%s/decisions.md\n' "$CMD_DIR" "$_dcmd_venture"
    fi

    # Always include strategy context
    if [[ -f "$CMD_DIR/strategy/objectives.md" ]]; then
        printf '\n### Strategic Context\n\n'
        printf '@%s/strategy/objectives.md\n' "$CMD_DIR"
        printf '@%s/strategy/rocks.md\n' "$CMD_DIR"
    fi
} >> "$OUTPUT_FILE"

unset _dcmd_client _dcmd_venture _dcmd_venture_dir _dcmd_client_file
