#!/usr/bin/env bash
# validate-symlinks.sh — Verify consumer paths point back to ~/dotfiles.
#
# On Linux/macOS, consumer paths must be symlinks to dotfiles sources.
# On Windows, fallback copies are allowed, but content must match source.
#
# Exit code: 0 when all checks pass, 1 when any required check fails.

set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/_lib.sh"

DOTFILES="$HOME/dotfiles"
CLAUDE_DIR="$HOME/.claude"
COPILOT_DIR="$HOME/.copilot"
AGENTS_DIR="$HOME/.agents"
OS="$(detect_os)"
_ci_mode=0

_fail=0
_warn=0

for arg in "$@"; do
    case "$arg" in
        --ci)  _ci_mode=1 ;;
        --afk) ;;  # accepted by validate-env.sh; ignore here
        *)
            red "Unknown option: $arg"
            red "Usage: bash ~/dotfiles/bin/validate-symlinks.sh [--ci]"
            exit 1
            ;;
    esac
done

check_link_or_windows_copy() { 
    local source="$1"
    local target="$2"
    local label="$3"

    if [[ -L "$target" ]]; then
        local current
        current="$(readlink "$target")"
        if [[ "$current" == "$source" ]]; then
            green "  ✓ $label symlink is correct"
        else
            red "  ✗ $label points to $current (expected $source)"
            _fail=1
        fi
        return
    fi

    if [[ "$OS" != "windows" ]]; then
        red "  ✗ $label is not a symlink (expected -> $source)"
        _fail=1
        return
    fi

    if [[ ! -e "$target" ]]; then
        red "  ✗ $label is missing"
        _fail=1
        return
    fi

    if [[ -d "$source" && -d "$target" ]]; then
        if diff -qr "$source" "$target" >/dev/null 2>&1; then
            yellow "  ~ $label is a Windows fallback copy (content matches)"
            _warn=1
        else
            red "  ✗ $label fallback copy has drifted from $source"
            _fail=1
        fi
    elif [[ -f "$source" && -f "$target" ]]; then
        if cmp -s "$source" "$target"; then
            yellow "  ~ $label is a Windows fallback copy (content matches)"
            _warn=1
        else
            red "  ✗ $label fallback copy has drifted from $source"
            _fail=1
        fi
    else
        red "  ✗ $label type mismatch (source and target differ in kind)"
        _fail=1
    fi
}

check_nested_duplication() {
    local path="$1"
    local label="$2"

    if [[ -e "$path" ]]; then
        red "  ✗ Nested duplication detected: $label"
        _fail=1
    else
        green "  ✓ No nested duplication at $label"
    fi
}

check_no_disable_model_flag() {
    local search_root="$1"

    if grep -Rin --include="SKILL.md" "disable-model-invocation" "$search_root" >/dev/null 2>&1; then
        yellow "  ~ Found deprecated 'disable-model-invocation' flag in skills (warn-only)"
        grep -Rin --include="SKILL.md" "disable-model-invocation" "$search_root" | sed "s|^$search_root/|    - |"
        _warn=1
    else
        green "  ✓ No deprecated 'disable-model-invocation' flags detected"
    fi
}

echo "Symlink / Consumer Integrity:"

if [[ $_ci_mode -eq 1 ]]; then
    yellow "  ~ Running in --ci mode (static checks only; consumer path checks skipped)"
else
    check_link_or_windows_copy "$DOTFILES/CLAUDE.md" "$CLAUDE_DIR/CLAUDE.md" "~/.claude/CLAUDE.md"
    check_link_or_windows_copy "$DOTFILES/skills" "$CLAUDE_DIR/skills" "~/.claude/skills"
    check_link_or_windows_copy "$DOTFILES/agents" "$CLAUDE_DIR/agents" "~/.claude/agents"
    check_link_or_windows_copy "$DOTFILES/rules" "$CLAUDE_DIR/rules" "~/.claude/rules"
    check_link_or_windows_copy "$DOTFILES/skills" "$COPILOT_DIR/skills" "~/.copilot/skills"
    check_link_or_windows_copy "$DOTFILES/skills" "$AGENTS_DIR/skills" "~/.agents/skills"

    # CLI entry points
    check_link_or_windows_copy "$DOTFILES/bin/ctrl" "$HOME/.local/bin/ctrl" "~/.local/bin/ctrl"
    check_link_or_windows_copy "$DOTFILES/shft/shft" "$HOME/.local/bin/shft" "~/.local/bin/shft"
fi

echo "Static Policy Checks:"
check_nested_duplication "$DOTFILES/rules/rules" "~/dotfiles/rules/rules"
check_nested_duplication "$DOTFILES/agents/agents" "~/dotfiles/agents/agents"

if [[ $_ci_mode -eq 0 ]]; then
    check_nested_duplication "$CLAUDE_DIR/rules/rules" "~/.claude/rules/rules"
    check_nested_duplication "$CLAUDE_DIR/agents/agents" "~/.claude/agents/agents"
fi

check_no_disable_model_flag "$DOTFILES/skills"

if [[ $_fail -eq 0 ]] && [[ $_warn -eq 0 ]]; then
    green "  ✓ Consumer integrity is healthy"
elif [[ $_fail -eq 0 ]]; then
    yellow "  ~ Consumer integrity passed with warnings"
fi

exit $_fail
