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
#   4 — Block git reset --hard (destructive — loses uncommitted changes)
#   5 — Block git clean -f (irreversible removal of untracked files)
#   6 — Warn on interactive rebase of pushed commits
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
# Match git as a command — after ^, ;, &&, ||, |, or shell control
# keywords that introduce command lists such as then/do/else (not bare
# whitespace, which would false-positive on "echo git status").
# Also matches shell wrappers: sudo git, command git, builtin git, env git.
# sudo -u root, env -u VARNAME, env --unset=VARNAME, FOO=bar) before the
# wrapped command. The regex allows optional non-flag tokens after each
# flag so the engine backtracks to correctly match the target command.
# GNU-style long options with inline =value (--opt=val) are also consumed.
WRAPPER_PREFIX='(sudo([[:space:]]+-[-a-zA-Z0-9]+(=[^[:space:]]+)?([[:space:]]+[^-[:space:]][^[:space:]]*)?)*[[:space:]]+|command[[:space:]]+|builtin[[:space:]]+|env([[:space:]]+-[-a-zA-Z0-9]+(=[^[:space:]]+)?([[:space:]]+[^-[:space:]=][^[:space:]]*)?)*([[:space:]]+[A-Za-z_][A-Za-z0-9_]*=[^[:space:]]*)*[[:space:]]+)*'
if ! echo "$COMMAND" | grep -qE '((^|;|&&|\|\||\|)[[:space:]]*|(^|[[:space:]])(then|do|else)[[:space:]]+)([A-Za-z_][A-Za-z0-9_]*=[^[:space:]]*[[:space:]]+)*'"$WRAPPER_PREFIX"'git[[:space:]]'; then
    exit 0
fi

# --- Helper: portable timeout (macOS may lack timeout) ---
# When no timeout utility is available, return failure so callers that
# use `if _timeout ...` gracefully skip the bounded operation rather
# than running it unbounded (which could hang a PreToolUse gate).
_timeout() {
    if command -v timeout &>/dev/null; then
        timeout "$@"
    else
        return 1
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

# --- Helper: read boolean config from .ctrlshft ---
_config_bool() {
    local key="$1" default="$2"
    local root
    root=$(_repo_root)
    local config="${root}/.ctrlshft"
    if [[ -n "$root" && -f "$config" ]]; then
        local val
        val=$(awk -v k="$key" '$0 ~ "^" k ":[[:space:]]" { sub(/^[^:]+:[[:space:]]+/, ""); print }' "$config" 2>/dev/null) || true
        case "$val" in
            true|yes|1) echo "true"; return ;;
            false|no|0) echo "false"; return ;;
        esac
    fi
    echo "$default"
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
# Include wrapper prefixes so `sudo -E git --git-dir=...` is also caught.
# Also treat shell control keywords as command boundaries, so
# `if true; then git --git-dir=/other status; fi` is detected.
if echo "$COMMAND" | grep -qE '(^|;|&&|\|\||\||[[:space:]]+(then|do|else))[[:space:]]*([A-Za-z_][A-Za-z0-9_]*=[^[:space:]]*[[:space:]]+)*'"$WRAPPER_PREFIX"'git[^;&|]*(--git-dir(=|[[:space:]]+)|--work-tree(=|[[:space:]]+))'; then
    _deny "🚫 Don't use git --git-dir or --work-tree in commands. Use the tool call's cwd field so git-workflow-gate can validate the correct repository."
fi

# Also block GIT_DIR / GIT_WORK_TREE set as environment variable assignments.
# These env vars achieve the same repo-targeting as the flag forms blocked above.
if echo "$COMMAND" | grep -qE '(^|[[:space:]])(GIT_DIR|GIT_WORK_TREE)='; then
    _deny "🚫 Don't set GIT_DIR or GIT_WORK_TREE as environment variables. Use the tool call's cwd field so git-workflow-gate can validate the correct repository."
fi

# -C is positional: global 'git -C <path>' vs subcommand option 'git commit -C HEAD'.
# Only block when -C appears in the global-options slot (before the subcommand).
# Global options are flag-like tokens (starting with -); the subcommand is the first
# non-flag word after 'git'. Skip non-C flags (and their optional values) to reach -C.
if echo "$COMMAND" | grep -qE '(^|;|&&|\|\||\||[[:space:]]+(then|do|else))[[:space:]]*([A-Za-z_][A-Za-z0-9_]*=[^[:space:]]*[[:space:]]+)*'"$WRAPPER_PREFIX"'git([[:space:]]+-[^C[:space:]][^[:space:]]*([[:space:]]+[^-[:space:]][^[:space:]]*)?)*[[:space:]]+-C[[:space:]]'; then
    _deny "🚫 Don't use git -C in commands. Use the tool call's cwd field so git-workflow-gate can validate the correct repository."
fi

# --- Pattern: optional git global options (e.g. --no-pager, -c key=val) ---
# Dangerous repo-targeting flags (-C/--git-dir/--work-tree) are already
# denied above, so any remaining global options between git and the
# subcommand are safe to pass through.
# Matches: short flags with optional value (-c user.name=x), long flags (--no-pager)
GIT_OPTS='([[:space:]]+(-[a-zA-Z]([[:space:]]+[^-[:space:]][^[:space:]]*)?|--[a-z][a-z-]*(=[^[:space:]]+)?))*'

# --- Pattern: command-boundary-anchored git (for per-gate checks) ---
# Anchors to shell command boundaries (^, ;, &&, ||, |) and shell control
# keywords (then/do/else) so that quoted git commands don't match.
# Uses the same WRAPPER_PREFIX as the initial detector for consistency.
CMD_GIT="((^|;|&&|\\|\\||\\|)[[:space:]]*|(^|[[:space:]])(then|do|else)[[:space:]]+)([A-Za-z_][A-Za-z0-9_]*=[^[:space:]]*[[:space:]]+)*${WRAPPER_PREFIX}git"

# ============================================================
# GATE 0: Block cd + git command chains (&&, ;, or ||)
# ============================================================
# Agent should use the cwd parameter instead of cd && git.
# Catches cd anywhere before a later git in the same chain,
# not just immediately adjacent (e.g. cd /repo && true && git commit).
# Anchored to command boundaries so 'echo cd /tmp' doesn't false-positive.
if echo "$COMMAND" | grep -qE '(^|;|&&|\|\||\||[[:space:]]+(then|do|else))[[:space:]]*cd[[:space:]]+("[^"]*"|'\''[^'\'']*'\''|[^[:space:];|&]+)' && \
   echo "$COMMAND" | grep -qE '(^|;|&&|\|\||\||[[:space:]]+(then|do|else))[[:space:]]*cd[[:space:]].*([;&]|\|\||&&).*git[[:space:]]'; then
    _deny "🚫 Don't chain cd && git commands. Use the cwd parameter on the tool call instead — cd chains leak shell state."
fi

# ============================================================
# GATE 1: Block commit to protected branch + validate message
#         (only validates -m inline messages; editor/file-based
#          commits pass through — see README § Commit Message Validation)
# ============================================================
if echo "$COMMAND" | grep -qE "${CMD_GIT}${GIT_OPTS}[[:space:]]+commit([[:space:]]|\$)"; then
    # Check current branch
    local_branch=$(git branch --show-current 2>/dev/null || echo "")
    protected=$(_protected_branches)

    if [[ -n "$local_branch" ]] && echo "$local_branch" | grep -qxE "$protected"; then
        _deny "🚫 Cannot commit directly to '$local_branch'. Create a feature branch first: git checkout -b ai/<type>/<description>"
    fi

    # Check if the command switches to a protected branch BEFORE committing.
    # e.g. `git switch main && git commit -m "fix: x"` — the commit targets main
    # after the switch, but the hook only sees the pre-switch branch above.
    # Only deny when the switch appears before the commit in the command string,
    # so `git commit -m "feat: x" && git switch main` is allowed (commit runs first
    # on the current feature branch).
    if echo "$COMMAND" | grep -qE "(^|;|&&|\|\||\|)[[:space:]]*([A-Za-z_][A-Za-z0-9_]*=[^[:space:]]*[[:space:]]+)*${WRAPPER_PREFIX}git${GIT_OPTS}[[:space:]]+(checkout|switch)([[:space:]]+-[^[:space:]]+)*[[:space:]]+(${protected})([[:space:]]|;|&&|\|\||\||$).*${CMD_GIT}${GIT_OPTS}[[:space:]]+commit([[:space:]]|$)"; then
        _deny "🚫 Cannot switch to a protected branch and commit in the same command. Use separate tool calls so the commit gate can verify the target branch."
    fi

    # Validate commit message format (only if -m/--message flag present)
    # Handles: -m "msg", -m 'msg', -m"msg", --message="msg", --message "msg"
    # Validates EACH git commit segment independently to catch chained bypasses
    # (e.g. git commit -m "feat: x" && git commit -m "updated stuff").
    while IFS= read -r _commit_seg; do
        _commit_seg=$(echo "$_commit_seg" | sed 's/^[[:space:]]*//')
        [[ -z "$_commit_seg" ]] && continue
        # Only check segments that actually contain a git commit command
        if ! echo "$_commit_seg" | grep -qE 'git([[:space:]]+(-[a-zA-Z]([[:space:]]+[^-[:space:]][^[:space:]]*)?|--[a-z][a-z-]*(=[^[:space:]]+)?))*[[:space:]]+commit([[:space:]]|$)'; then
            continue
        fi
        if echo "$_commit_seg" | grep -qE "[[:space:]](-m[[:space:]]|-m[\"']|--message[=[:space:]])"; then
            # Extract FIRST -m/--message value from this segment.
            # grep -oE returns matches left-to-right; head -1 takes the first (= subject line).
            # || true: grep exits 1 when no match; suppress to avoid ERR trap with -Eeuo pipefail.
            # Use separate patterns for double-quoted and single-quoted messages to avoid
            # mismatched delimiter truncation (e.g. -m "fix: 'quoted' value").
            first_match=$(echo "$_commit_seg" | grep -oE "(-m[[:space:]]*|--message[=[:space:]]*)\"[^\"]*\"" | head -1) || true
            if [[ -z "$first_match" ]]; then
                first_match=$(echo "$_commit_seg" | grep -oE "(-m[[:space:]]*|--message[=[:space:]]*)'[^']*'" | head -1) || true
            fi
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
    done <<< "$(echo "$COMMAND" | sed 's/&&/\n/g; s/;/\n/g; s/||/\n/g')"
fi

# ============================================================
# GATE 2: Block push safety violations
# ============================================================
if echo "$COMMAND" | grep -qE "${CMD_GIT}${GIT_OPTS}[[:space:]]+push([[:space:]]|\$)"; then
    # Extract ALL git push segments, anchored to command boundaries.
    # Split on command separators first to avoid false-positives on quoted
    # text (e.g. echo "git push --force" wouldn't match as a real command).
    ALL_PUSH_SEGS=""
    while IFS= read -r _seg; do
        _seg=$(echo "$_seg" | sed 's/^[[:space:]]*//')
        [[ -z "$_seg" ]] && continue
        # Strip leading shell control keywords so anchored check works on
        # segments like "then git push --force" after splitting on ;/&&/||.
        _seg=$(echo "$_seg" | sed -E 's/^(then|do|else)[[:space:]]+//')
        # Skip segments where git isn't the actual command (e.g. echo "git push")
        if ! echo "$_seg" | grep -qE '^([A-Za-z_][A-Za-z0-9_]*=[^[:space:]]*[[:space:]]+)*'"$WRAPPER_PREFIX"'git[[:space:]]'; then
            continue
        fi
        _match=$(echo "$_seg" | grep -oE 'git([[:space:]]+(-[a-zA-Z]([[:space:]]+[^-[:space:]][^[:space:]]*)?|--[a-z][a-z-]*(=[^[:space:]]+)?))*[[:space:]]+push([[:space:]]+[^;&|][^;&|]*)*' || true)
        [[ -n "$_match" ]] && ALL_PUSH_SEGS="${ALL_PUSH_SEGS}${_match}"$'\n'
    done <<< "$(echo "$COMMAND" | sed 's/;/\n/g; s/&&/\n/g; s/||/\n/g')"
    while IFS= read -r PUSH_SEG; do
        [[ -z "$PUSH_SEG" ]] && continue

        # Block force-push without --force-with-lease (handles --force, -f, combined short flags like -fu, and +refspec)
        if echo "$PUSH_SEG" | grep -qE '[[:space:]](--force|-f|-[a-zA-Z]*f[a-zA-Z]*)([[:space:]]|$)' && ! echo "$PUSH_SEG" | grep -qE '[[:space:]]--force-with-lease'; then
            _deny "🚫 Force-push without --force-with-lease is dangerous. Use --force-with-lease to protect against overwriting others' work."
        fi

        # Block +refspec force-update (e.g. git push origin +HEAD:main)
        if echo "$PUSH_SEG" | grep -qE '[[:space:]]\+[^[:space:]]+' && ! echo "$PUSH_SEG" | grep -qE '[[:space:]]--force-with-lease'; then
            _deny "🚫 Refspec prefixed with '+' forces the update. Use --force-with-lease instead of +refspec."
        fi
    done <<< "$ALL_PUSH_SEGS"

    # Check if behind origin (only if configured — opt-in via .ctrlshft)
    # Network calls inside a pre-flight gate add latency and can fail on
    # corporate proxies. Default: off. Enable with `pre_push_fetch: true`.
    if [[ "$(_config_bool pre_push_fetch false)" == "true" ]]; then
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
fi

# ============================================================
# GATE 3: Block branch switch with dirty working tree
# ============================================================
if echo "$COMMAND" | grep -qE "${CMD_GIT}${GIT_OPTS}[[:space:]]+(checkout|switch)[[:space:]]"; then
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

# ============================================================
# GATES 4–6: Destructive operation checks
# ============================================================
# Warning-only gates (4, 6) must not exit before blocking gates (5).
# Collect warnings and emit them after all blocking gates have run.
PENDING_WARN=""

# GATE 4: Block git reset --hard (destructive)
# reset --hard HEAD (no ~N) is a common "discard working tree" idiom,
# roughly equivalent to `git checkout -- .`. Warn instead of block.
# reset --hard with a different target (HEAD~N, a SHA, a branch) rewrites
# history and is genuinely dangerous — block those.
if echo "$COMMAND" | grep -qE "${CMD_GIT}${GIT_OPTS}[[:space:]]+reset([[:space:]]|\$)"; then
    if echo "$COMMAND" | grep -qE '[[:space:]]--hard([[:space:]]|$)'; then
        # Split on command boundaries so quoted text (e.g. echo "git reset --hard")
        # stays within its segment and doesn't trigger a false positive.
        ALL_RESET_SEGS=$(echo "$COMMAND" | sed 's/&&/\n/g; s/;/\n/g; s/||/\n/g')
        while IFS= read -r RESET_SEG; do
            RESET_SEG=$(echo "$RESET_SEG" | sed 's/^[[:space:]]*//')
            [[ -z "$RESET_SEG" ]] && continue
            # Only inspect segments that actually contain a reset command
            if ! echo "$RESET_SEG" | grep -qE "${CMD_GIT}${GIT_OPTS}[[:space:]]+reset([[:space:]]|$)"; then
                continue
            fi
            if ! echo "$RESET_SEG" | grep -qE '[[:space:]]--hard([[:space:]]|$)'; then
                continue
            fi
            # Extract the reset target, skipping any options (--quiet, -q, etc.) between --hard and the target.
            # Strip everything up to and including --hard, then skip flag-like tokens to find the target.
            after_hard=$(echo "$RESET_SEG" | sed 's/.*--hard//' | sed 's/^[[:space:]]*//')
            reset_target=""
            for _tok in $after_hard; do
                if [[ "$_tok" == -* ]]; then
                    continue  # skip options like --quiet, -q
                fi
                reset_target="$_tok"
                break
            done
            if [[ -z "$reset_target" || "$reset_target" == "HEAD" || "$reset_target" == "@" ]]; then
                PENDING_WARN="⚠️ git reset --hard HEAD discards all uncommitted changes. Consider git stash if you might need them later."
            else
                _deny "🚫 git reset --hard (to a non-HEAD target) rewrites history irreversibly. Use git stash or git reset --soft instead."
            fi
        done <<< "$ALL_RESET_SEGS"
    fi
fi

# ============================================================
# GATE 5: Block git clean -f (irreversible)
# ============================================================
# Only -f/--force triggers deletion — `-d` alone is safe because git
# requires `-f` explicitly (or clean.requireForce=false, which is rare).
# Allow dry-run variants (-n/--dry-run) even when combined with -f,
# since they only preview what would be deleted without removing files.
if echo "$COMMAND" | grep -qE "${CMD_GIT}${GIT_OPTS}[[:space:]]+clean([[:space:]]|\$)"; then
    # Extract each git clean segment independently so flags in unrelated
    # chained commands don't satisfy the dry-run exemption.
    # e.g. `git clean -fd && echo -n done` — the -n is in echo, not clean.
    while IFS= read -r CLEAN_SEG; do
        CLEAN_SEG=$(echo "$CLEAN_SEG" | sed 's/^[[:space:]]*//')
        [[ -z "$CLEAN_SEG" ]] && continue
        if ! echo "$CLEAN_SEG" | grep -qE 'git[^;&|]*clean([[:space:]]|$)'; then
            continue
        fi
        if echo "$CLEAN_SEG" | grep -qE '[[:space:]](-[a-zA-Z]*f[a-zA-Z]*|--force)([[:space:]]|$)'; then
            if ! echo "$CLEAN_SEG" | grep -qE '[[:space:]](-[a-zA-Z]*n[a-zA-Z]*|--dry-run)([[:space:]]|$)'; then
                _deny "🚫 git clean -f irreversibly removes untracked files. Use git clean -n (dry-run) first to review what would be deleted."
            fi
        fi
    done <<< "$(echo "$COMMAND" | sed 's/&&/\n/g; s/;/\n/g; s/||/\n/g')"
fi

# ============================================================
# GATE 6: Warn on interactive rebase of already-pushed commits
# ============================================================
if echo "$COMMAND" | grep -qE "${CMD_GIT}${GIT_OPTS}[[:space:]]+rebase([[:space:]]|\$)"; then
    if echo "$COMMAND" | grep -qE '[[:space:]](-i|--interactive)([[:space:]]|$)'; then
        local_branch=$(git branch --show-current 2>/dev/null || echo "")
        if [[ -n "$local_branch" ]] && git rev-parse --verify "origin/$local_branch" &>/dev/null; then
            msg="⚠️ Interactive rebase on a pushed branch ($local_branch) will rewrite history. You'll need --force-with-lease to push afterward. Proceed with caution."
            if [[ -n "$PENDING_WARN" ]]; then
                PENDING_WARN="${PENDING_WARN} ${msg}"
            else
                PENDING_WARN="$msg"
            fi
        fi
    fi
fi

# Emit deferred warnings (after all blocking gates have run)
if [[ -n "$PENDING_WARN" ]]; then
    _warn "$PENDING_WARN"
fi

# --- All gates passed ---
exit 0
