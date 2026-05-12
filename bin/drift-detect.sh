#!/usr/bin/env bash
# drift-detect.sh — Check if bootstrap targets have diverged from source.
#
# Usage:
#   bash ~/dotfiles/bin/drift-detect.sh          # check all targets
#   bash ~/dotfiles/bin/drift-detect.sh --fix    # re-run bootstrap to fix drift
#
# Compares symlinked/copied files in ~/.claude/ and ~/.copilot/ against their
# source in ~/dotfiles/. Reports any files that have been modified directly in
# the target (violating source-of-truth convention).

set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/_lib.sh"

FIX=false
DRIFT_COUNT=0

for arg in "$@"; do
    case "$arg" in
        --fix) FIX=true ;;
    esac
done

# ── Targets to check ─────────────────────────────────────────────────────────

declare -A TARGETS=(
    ["$HOME/.claude/settings.json"]="hooks/settings-hooks.json"
    ["$HOME/.claude/CLAUDE.md"]="CLAUDE.md"
)

# Check hook scripts (all .sh files in hooks/ should be symlinked to ~/.claude/hooks/)
if [[ -d "$HOME/.claude/hooks" ]]; then
    for src in hooks/*.sh; do
        [[ -f "$src" ]] || continue
        basename=$(basename "$src")
        TARGETS["$HOME/.claude/hooks/$basename"]="$src"
    done
fi

# ── Drift detection ──────────────────────────────────────────────────────────

DOTFILES_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

for target in "${!TARGETS[@]}"; do
    src_rel="${TARGETS[$target]}"
    src_abs="$DOTFILES_ROOT/$src_rel"

    # Skip if source doesn't exist
    if [[ ! -f "$src_abs" ]]; then
        continue
    fi

    # Skip if target doesn't exist (not yet bootstrapped)
    if [[ ! -e "$target" ]]; then
        continue
    fi

    # If target is a symlink, check it points to the right place
    if [[ -L "$target" ]]; then
        link_target=$(readlink -f "$target" 2>/dev/null || readlink "$target")
        expected=$(readlink -f "$src_abs" 2>/dev/null || echo "$src_abs")
        if [[ "$link_target" != "$expected" ]]; then
            yellow "DRIFT (symlink): $target → $link_target (expected $src_abs)"
            DRIFT_COUNT=$((DRIFT_COUNT + 1))
        fi
    else
        # Regular file — compare contents
        if ! diff -q "$src_abs" "$target" &>/dev/null; then
            yellow "DRIFT (content): $target differs from $src_rel"
            DRIFT_COUNT=$((DRIFT_COUNT + 1))
        fi
    fi
done

# ── Report ────────────────────────────────────────────────────────────────────

if [[ $DRIFT_COUNT -eq 0 ]]; then
    green "✓ No drift detected. All targets match source."
    exit 0
fi

echo ""
yellow "Found $DRIFT_COUNT file(s) with drift."

if [[ "$FIX" == "true" ]]; then
    echo ""
    echo "Running bootstrap to fix drift..."
    bash "$DOTFILES_ROOT/bin/bootstrap.sh"
    green "✓ Bootstrap complete. Drift should be resolved."
else
    echo ""
    echo "Run with --fix to re-bootstrap, or manually:"
    echo "  bash ~/dotfiles/bin/bootstrap.sh"
fi

exit 1
