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
#   2 — Block push when behind origin + block force-push without --force-with-lease
#   3 — Block branch switch with dirty working tree
#
# Config: reads `.ctrlshft` YAML at repo root for commit_types override.
# Fail-closed: any unhandled error outputs deny JSON.

set -euo pipefail

# --- Fail-closed trap: any error = deny ---
trap '_fail_closed' ERR
_fail_closed() {
    echo '{"hookSpecificOutput":{"permissionDecision":"deny","permissionDecisionReason":"git-workflow-gate: internal error (fail-closed). Please report this."}}' >&2
    exit 2
}

# --- Dependencies ---
if ! command -v jq &>/dev/null; then
    exit 0  # jq required — skip gracefully if missing
fi

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty')

# Skip if no command (non-Bash tool calls pass through)
[[ -z "$COMMAND" ]] && exit 0

# Only process git commands
if ! echo "$COMMAND" | grep -qE '(^|\s|;|&&|\|)\s*git\s'; then
    exit 0
fi

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
        # Simple grep-based parsing: extract commit_types array values
        local types
        types=$(grep -A 20 'commit_types:' "$config" 2>/dev/null \
            | grep -oP '^\s*-\s*\K\w+' \
            | tr '\n' '|' \
            | sed 's/|$//')
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
        branches=$(grep -A 20 'protected_branches:' "$config" 2>/dev/null \
            | grep -oP '^\s*-\s*\K\w+' \
            | tr '\n' '|' \
            | sed 's/|$//')
        if [[ -n "$branches" ]]; then
            echo "$branches"
            return
        fi
    fi

    echo "main|master"
}

# --- Helper: deny output ---
_deny() {
    local reason="$1"
    echo "{\"hookSpecificOutput\":{\"permissionDecision\":\"deny\",\"permissionDecisionReason\":\"$reason\"}}" >&2
    exit 2
}

# --- Helper: warn output (allow with context) ---
_warn() {
    local msg="$1"
    echo "{\"hookSpecificOutput\":{\"additionalContext\":\"$msg\"}}" >&2
    exit 0
}

# ============================================================
# GATE 0: Block cd + git command chains
# ============================================================
# Agent should use the cwd parameter instead of cd && git
if echo "$COMMAND" | grep -qE 'cd\s+[^\s;]+\s*&&\s*git\s'; then
    _deny "🚫 Don't chain cd && git commands. Use the cwd parameter on the tool call instead — cd chains leak shell state."
fi

# ============================================================
# GATE 1: Block commit to protected branch + validate message
# ============================================================
if echo "$COMMAND" | grep -qE 'git\s+commit'; then
    # Check current branch
    local_branch=$(git branch --show-current 2>/dev/null || echo "")
    protected=$(_protected_branches)

    if [[ -n "$local_branch" ]] && echo "$local_branch" | grep -qxE "$protected"; then
        _deny "🚫 Cannot commit directly to '$local_branch'. Create a feature branch first: git checkout -b ai/<type>/<description>"
    fi

    # Validate commit message format (only if -m flag present)
    if echo "$COMMAND" | grep -qE '\s-m\s'; then
        # Extract message — handles both -m "msg" and -m 'msg'
        msg=$(echo "$COMMAND" | sed -n "s/.*-m[[:space:]]*[\"']\([^\"']*\)[\"'].*/\1/p")

        if [[ -n "$msg" ]]; then
            types=$(_commit_types)
            # Pattern: type(scope): description  OR  type: description
            if ! echo "$msg" | grep -qE "^($types)(\([a-z0-9._-]+\))?: .+"; then
                _deny "🚫 Commit message doesn't follow conventional format. Expected: <type>(<scope>): <description>. Allowed types: ${types//|/, }"
            fi
        fi
    fi
fi

# ============================================================
# GATE 2: Block push safety violations
# ============================================================
if echo "$COMMAND" | grep -qE 'git\s+push'; then
    # Block force-push without --force-with-lease
    if echo "$COMMAND" | grep -qE '\s--force\s|\s-f\s' && ! echo "$COMMAND" | grep -qE '\s--force-with-lease'; then
        _deny "🚫 Force-push without --force-with-lease is dangerous. Use --force-with-lease to protect against overwriting others' work."
    fi

    # Check if behind origin (only if we can reach remote)
    local_branch=$(git branch --show-current 2>/dev/null || echo "")
    if [[ -n "$local_branch" ]]; then
        # Fetch silently to check if behind (timeout after 5s to not block on network issues)
        if timeout 5 git fetch origin "$local_branch" --dry-run 2>/dev/null; then
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
if echo "$COMMAND" | grep -qE 'git\s+(checkout|switch)\s'; then
    # Skip if it's a file restore (checkout -- file) or new branch creation (-b/-c)
    if echo "$COMMAND" | grep -qE '(checkout\s+--\s|checkout\s+-b\s|switch\s+-c\s|switch\s+--create\s)'; then
        exit 0
    fi

    # Check for dirty working tree
    if [[ -n $(git status --porcelain 2>/dev/null) ]]; then
        # Allow if only untracked files (no modified/staged)
        if git status --porcelain 2>/dev/null | grep -qE '^[^?]'; then
            _deny "🚫 Working tree has uncommitted changes. Commit or stash before switching branches."
        fi
    fi
fi

# --- All gates passed ---
exit 0
