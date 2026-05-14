#!/usr/bin/env bash
# FAIL_MODE: closed
# git-workflow-gate.sh — PreToolUse hook: enforce git workflow safety gates.
#
# Receives Claude Code PreToolUse JSON on stdin (matcher: Bash).
# Exits 2 (block) for dangerous git operations. Exit 0 (allow) on pass.
#
# Gates:
#   0 — Block `cd <dir> && git ...` chains (leaks shell state)
#   1 — Block commit to main/master + enforce conventional commit format
#         (only validates -m inline messages; editor/file-based commits pass through)
#   2 — Block push when behind origin + block force-push without --force-with-lease
#   3 — Block branch switch with dirty working tree
#
# Config: reads `.ctrlshft` YAML at repo root for commit_types and
#         protected_branches overrides.
# Fail-closed: any unhandled error outputs deny JSON.

set -Eeuo pipefail

# --- Fail-closed trap: any error = deny ---
_fail_closed() {
    echo '{"hookSpecificOutput":{"permissionDecision":"deny","permissionDecisionReason":"git-workflow-gate: internal error (fail-closed). Please report this."}}' >&2
    exit 2
}
trap '_fail_closed' ERR

# --- Dependencies ---
if ! command -v jq &>/dev/null; then
    echo '{"hookSpecificOutput":{"permissionDecision":"deny","permissionDecisionReason":"git-workflow-gate: jq is required but not found. Install jq to use git safety gates."}}' >&2
    exit 2
fi

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty')

# Skip if no command (non-Bash tool calls pass through)
[[ -z "$COMMAND" ]] && exit 0

# Only process git commands (POSIX ERE: [[:space:]] not \s)
# Match git as a command — after ^, ;, &&, ||, | (not bare whitespace,
# which would false-positive on "echo git status").
if ! echo "$COMMAND" | grep -qE '(^|;|&&|\|\||\|)[[:space:]]*([A-Za-z_][A-Za-z0-9_]*=[^[:space:]]*[[:space:]]+)*git[[:space:]]'; then
    exit 0
fi

# --- Helper: portable timeout (macOS may lack timeout) ---
_timeout() {
    if command -v timeout &>/dev/null; then
        timeout "$@"
    else
        # Skip timeout wrapper — run command directly
        "${@:2}"
    fi
}

# --- Helper: get repo root (for .ctrlshft config) ---
_repo_root() {
    git rev-parse --show-toplevel 2>/dev/null || echo ""
}

# --- Helper: read commit types from .ctrlshft or use defaults ---
_commit_types() {
    local root
    root=$(_repo_root)
    local config="${root}/.ctrlshft"

    if [[ -n "$root" && -f "$config" ]]; then
        # Awk state-machine parser: start after ^commit_types:, stop at next top-level key
        local types
        types=$(awk '
            /^commit_types:/ { f=1; next }
            f && /^[^[:space:]-]/ { exit }
            f { sub(/^[[:space:]]*-[[:space:]]*/, ""); sub(/^[[:space:]]+/, ""); sub(/[[:space:]]+$/, ""); if (length) print }
        ' "$config" 2>/dev/null | sed 's/[][\\()*+?.{|^$}]/\\&/g' | tr '\n' '|' | sed 's/|$//') || true
        if [[ -n "$types" ]]; then
            echo "$types"
            return
        fi
    fi

    # Defaults: conventional commit types
    echo "feat|fix|refactor|chore|docs|test|perf|ci|build|style|revert"
}

# --- Helper: get protected branches ---
_protected_branches() {
    local root
    root=$(_repo_root)
    local config="${root}/.ctrlshft"

    if [[ -n "$root" && -f "$config" ]]; then
        local branches
        branches=$(awk '
            /^protected_branches:/ { f=1; next }
            f && /^[^[:space:]-]/ { exit }
            f { sub(/^[[:space:]]*-[[:space:]]*/, ""); sub(/^[[:space:]]+/, ""); sub(/[[:space:]]+$/, ""); if (length) print }
        ' "$config" 2>/dev/null | sed 's/[][\\()*+?.{|^$}]/\\&/g' | tr '\n' '|' | sed 's/|$//') || true
        if [[ -n "$branches" ]]; then
            echo "$branches"
            return
        fi
    fi

    echo "main|master"
}

# --- Helper: deny output (JSON-safe via jq) ---
_deny() {
    jq -cn --arg reason "$1" '{"hookSpecificOutput":{"permissionDecision":"deny","permissionDecisionReason":$reason}}' >&2
    exit 2
}

# --- Helper: warn output (allow with context, JSON-safe via jq) ---
_warn() {
    jq -cn --arg msg "$1" '{"hookSpecificOutput":{"additionalContext":$msg}}' >&2
    exit 0
}

# --- cd into the hook event's working directory ---
EVENT_CWD=$(echo "$INPUT" | jq -r '.cwd // empty')
if [[ -n "$EVENT_CWD" ]]; then
    cd "$EVENT_CWD" || _deny "git-workflow-gate: cannot cd to event cwd '$EVENT_CWD'"
fi

# --- Deny git repo override flags; use the tool's cwd instead ---
# This hook performs its safety checks relative to EVENT_CWD. Allowing
# git -C / --git-dir / --work-tree would let the actual command target
# a different repository than the one that was validated.

# --git-dir and --work-tree are unambiguous global-only options — scan anywhere.
if echo "$COMMAND" | grep -qE '(^|;|&&|\|\||\|)[[:space:]]*([A-Za-z_][A-Za-z0-9_]*=[^[:space:]]*[[:space:]]+)*git[^;&|]*(--git-dir(=|[[:space:]]+)|--work-tree(=|[[:space:]]+))'; then
    _deny "🚫 Don't use git --git-dir or --work-tree in commands. Use the tool call's cwd field so git-workflow-gate can validate the correct repository."
fi

# -C is positional: global 'git -C <path>' vs subcommand option 'git commit -C HEAD'.
# Only block when -C appears in the global-options slot (before the subcommand).
# Global options are flag-like tokens (starting with -); the subcommand is the first
# non-flag word after 'git'. Skip non-C flags (and their optional values) to reach -C.
if echo "$COMMAND" | grep -qE '(^|;|&&|\|\||\|)[[:space:]]*([A-Za-z_][A-Za-z0-9_]*=[^[:space:]]*[[:space:]]+)*git([[:space:]]+-[^C[:space:]][^[:space:]]*([[:space:]]+[^-[:space:]][^[:space:]]*)?)*[[:space:]]+-C[[:space:]]'; then
    _deny "🚫 Don't use git -C in commands. Use the tool call's cwd field so git-workflow-gate can validate the correct repository."
fi

# --- Pattern: optional git global options (e.g. --no-pager, -c key=val) ---
# Dangerous repo-targeting flags (-C/--git-dir/--work-tree) are already
# denied above, so any remaining global options between git and the
# subcommand are safe to pass through.
# Matches: short flags with optional value (-c user.name=x), long flags (--no-pager)
GIT_OPTS='([[:space:]]+(-[a-zA-Z]([[:space:]]+[^-[:space:]][^[:space:]]*)?|--[a-z][a-z-]*(=[^[:space:]]+)?))*'

# ============================================================
# GATE 0: Block cd + git command chains (&&  or ;)
# ============================================================
# Agent should use the cwd parameter instead of cd && git
if echo "$COMMAND" | grep -qE 'cd[[:space:]]+("[^"]*"|'\''[^'\'']*'\''|[^[:space:];]+)[[:space:]]*(&&|;)[[:space:]]*([A-Za-z_][A-Za-z0-9_]*=[^[:space:]]+[[:space:]]+)*git[[:space:]]'; then
    _deny "🚫 Don't chain cd && git commands. Use the cwd parameter on the tool call instead — cd chains leak shell state."
fi

# ============================================================
# GATE 1: Block commit to protected branch + validate message
#         (only validates -m inline messages; editor/file-based
#          commits pass through — see README § Commit Message Validation)
# ============================================================
if echo "$COMMAND" | grep -qE "git${GIT_OPTS}[[:space:]]+commit([[:space:]]|\$)"; then
    # Check current branch
    local_branch=$(git branch --show-current 2>/dev/null || echo "")
    protected=$(_protected_branches)

    if [[ -n "$local_branch" ]] && echo "$local_branch" | grep -qxE "$protected"; then
        _deny "🚫 Cannot commit directly to '$local_branch'. Create a feature branch first: git checkout -b ai/<type>/<description>"
    fi

    # Validate commit message format (only if -m/--message flag present)
    # Handles: -m "msg", -m 'msg', -m"msg", --message="msg", --message "msg"
    if echo "$COMMAND" | grep -qE "[[:space:]](-m[[:space:]]|-m[\"']|--message[=[:space:]])"; then
        # Extract FIRST -m/--message value (the commit subject for multi-paragraph commits).
        # grep -oE returns matches left-to-right; head -1 takes the first (= subject line).
        # || true: grep exits 1 when no match; suppress to avoid ERR trap with -Eeuo pipefail.
        first_match=$(echo "$COMMAND" | grep -oE "(-m[[:space:]]*|--message[=[:space:]]*)([\"'])[^\"']*[\"']" | head -1) || true
        msg=""
        if [[ -n "$first_match" ]]; then
            msg=$(echo "$first_match" | sed "s/^-m[[:space:]]*//;s/^--message[=[:space:]]*//;s/^[\"']//;s/[\"']$//")
        fi

        if [[ -n "$msg" ]]; then
            types=$(_commit_types)
            # Pattern: type(scope): description  OR  type: description
            if ! echo "$msg" | grep -qE "^($types)(\([a-z0-9._-]+\))?!?: .+"; then
                _deny "🚫 Commit message doesn't follow conventional format. Expected: <type>(<scope>): <description>. Allowed types: ${types//|/, }"
            fi
        else
            # -m/--message flag present but message could not be parsed (e.g. unquoted: git commit -m updated)
            _deny "🚫 Could not parse commit message. Wrap the message in quotes: git commit -m \"type(scope): description\""
        fi
    fi
fi

# ============================================================
# GATE 2: Block push safety violations
# ============================================================
if echo "$COMMAND" | grep -qE "git${GIT_OPTS}[[:space:]]+push([[:space:]]|\$)"; then
    # Block force-push without --force-with-lease (handles --force, -f, combined short flags like -fu, and +refspec)
    if echo "$COMMAND" | grep -qE '[[:space:]](--force|-f|-[a-zA-Z]*f[a-zA-Z]*)([[:space:]]|$)' && ! echo "$COMMAND" | grep -qE '[[:space:]]--force-with-lease'; then
        _deny "🚫 Force-push without --force-with-lease is dangerous. Use --force-with-lease to protect against overwriting others' work."
    fi

    # Block +refspec force-update (e.g. git push origin +HEAD:main)
    if echo "$COMMAND" | grep -qE '[[:space:]]\+[^[:space:]]+' && ! echo "$COMMAND" | grep -qE '[[:space:]]--force-with-lease'; then
        _deny "🚫 Refspec prefixed with '+' forces the update. Use --force-with-lease instead of +refspec."
    fi

    # Check if behind origin (only if we can reach remote)
    local_branch=$(git branch --show-current 2>/dev/null || echo "")
    if [[ -n "$local_branch" ]]; then
        # Fetch to check if behind (timeout after 5s to not block on network issues)
        if _timeout 5 git fetch origin "$local_branch" --quiet 2>/dev/null; then
            behind=$(git rev-list --count "HEAD..origin/$local_branch" 2>/dev/null || echo "0")
            if [[ "$behind" -gt 0 ]]; then
                _deny "🚫 Local branch is $behind commit(s) behind origin/$local_branch. Run 'git pull --rebase' first."
            fi
        fi
    fi
fi

# ============================================================
# GATE 3: Block branch switch with dirty working tree
# ============================================================
if echo "$COMMAND" | grep -qE "git${GIT_OPTS}[[:space:]]+(checkout|switch)[[:space:]]"; then
    # Mask creation/restore forms so they don't count as bare switches.
    # A chained command like `git checkout -b tmp && git switch main` must still
    # trigger the dirty-tree check for the bare `switch main` portion.
    masked_cmd=$(echo "$COMMAND" | sed \
        -e 's/checkout[[:space:]]*-b[[:space:]]/NEWBRANCH /g' \
        -e 's/checkout[[:space:]]*--[[:space:]]/RESTORE /g' \
        -e 's/switch[[:space:]]*-c[[:space:]]/NEWBRANCH /g' \
        -e 's/switch[[:space:]]*--create[[:space:]]/NEWBRANCH /g')

    if echo "$masked_cmd" | grep -qE '(checkout|switch)[[:space:]]'; then
        # Non-creation checkout/switch remains — check dirty working tree
        if [[ -n "$(git status --porcelain 2>/dev/null)" ]]; then
            # Allow if only untracked files (no modified/staged)
            if git status --porcelain 2>/dev/null | grep -qE '^[^?]'; then
                _deny "🚫 Working tree has uncommitted changes. Commit or stash before switching branches."
            fi
        fi
    fi
fi

# --- All gates passed ---
exit 0
