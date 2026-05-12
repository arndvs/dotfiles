#!/usr/bin/env bash
# FAIL_MODE: open
# stale-branches.sh — SessionStart hook: report stale/merged branches.
#
# Fires at session start. Lists branches that have been merged into the
# default branch or haven't been updated in 14+ days. Outputs an info
# digest suggesting cleanup. Capped at 10 branches to avoid noise.
# Fail-open: network issues or non-git repos silently pass.

set -euo pipefail

# Consume stdin (required by hook protocol)
cat > /dev/null

# Skip if not in a git repo
if ! git rev-parse --is-inside-work-tree &>/dev/null; then
    exit 0
fi

# Detect default branch
DEFAULT_BRANCH=""
for candidate in main master dev; do
    if git rev-parse --verify "origin/$candidate" &>/dev/null; then
        DEFAULT_BRANCH="$candidate"
        break
    fi
done
[[ -z "$DEFAULT_BRANCH" ]] && exit 0

# Portable timeout (macOS may lack timeout)
_timeout() {
    if command -v timeout &>/dev/null; then
        timeout "$@"
    else
        "${@:2}"
    fi
}

# Fetch to ensure we have latest remote state (timeout 10s, fail silently)
_timeout 10 git fetch origin "$DEFAULT_BRANCH" --quiet 2>/dev/null || true

STALE_BRANCHES=()

# Find local branches merged into default (exact match filter, not substring)
while IFS= read -r branch; do
    branch=$(echo "$branch" | xargs)  # trim whitespace
    [[ -z "$branch" ]] && continue
    [[ "$branch" == "$DEFAULT_BRANCH" ]] && continue
    [[ "$branch" == "dev" ]] && continue
    STALE_BRANCHES+=("$branch (merged)")
done < <(git branch --merged "origin/$DEFAULT_BRANCH" 2>/dev/null | grep -v '^\*' | grep -vxF "  $DEFAULT_BRANCH")

# Find branches with no commits in 14+ days
CUTOFF=$(date -d "14 days ago" +%s 2>/dev/null || date -v-14d +%s 2>/dev/null || echo "")
if [[ -n "$CUTOFF" ]]; then
    while IFS= read -r branch; do
        branch=$(echo "$branch" | xargs)
        [[ -z "$branch" ]] && continue
        [[ "$branch" == "$DEFAULT_BRANCH" ]] && continue
        [[ "$branch" == "dev" ]] && continue

        # Skip if already in the list
        already_listed=false
        for existing in "${STALE_BRANCHES[@]+"${STALE_BRANCHES[@]}"}"; do
            if [[ "$existing" == "$branch (merged)" ]]; then
                already_listed=true
                break
            fi
        done
        [[ "$already_listed" == "true" ]] && continue

        # Check last commit date
        last_commit=$(git log -1 --format=%ct "$branch" 2>/dev/null || echo "")
        if [[ -n "$last_commit" && "$last_commit" -lt "$CUTOFF" ]]; then
            STALE_BRANCHES+=("$branch (stale >14d)")
        fi
    done < <(git branch 2>/dev/null | grep -v '^\*' | grep -vxF "  $DEFAULT_BRANCH")
fi

# Nothing to report
if [[ ${#STALE_BRANCHES[@]} -eq 0 ]]; then
    exit 0
fi

# Cap at 10
TOTAL=${#STALE_BRANCHES[@]}
DISPLAY=("${STALE_BRANCHES[@]:0:10}")
BRANCHES_LIST=$(printf '%s, ' "${DISPLAY[@]}")
BRANCHES_LIST=${BRANCHES_LIST%, }  # trim trailing comma

MSG="🌿 Found $TOTAL stale/merged branch(es): $BRANCHES_LIST."
if [[ $TOTAL -gt 10 ]]; then
    MSG="$MSG (showing 10 of $TOTAL)"
fi
MSG="$MSG Consider: git branch -d <branch>"

# JSON-safe output via jq (if available), else plain-text fallback
if command -v jq &>/dev/null; then
    jq -cn --arg msg "$MSG" '{"hookSpecificOutput":{"additionalContext":$msg}}' >&2
else
    echo "{\"hookSpecificOutput\":{\"additionalContext\":\"Stale branches detected. Run: git branch --merged\"}}" >&2
fi
exit 0
