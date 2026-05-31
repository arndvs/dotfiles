#!/usr/bin/env bash
# _lib.sh — Shared utilities for bin/ scripts.
#
# Source this file from other scripts:
#   source "$(dirname "${BASH_SOURCE[0]}")/_lib.sh"
#
# Provides: green, yellow, red, detect_os, find_python, find_venv_python,
#           ensure_symlink
#
# NOTE: load-secrets.sh intentionally does NOT source this file because
# it's loaded from .bashrc/.zshrc and must remain self-contained.

# ── Colors ────────────────────────────────────────────────────────────────────
green()  { printf '\033[32m%s\033[0m\n' "$*"; }
yellow() { printf '\033[33m%s\033[0m\n' "$*"; }
red()    { printf '\033[31m%s\033[0m\n' "$*"; }

# ── OS detection ──────────────────────────────────────────────────────────────
# Returns: "windows", "linux", "macos", or "unknown"
detect_os() {
    case "$(uname -s)" in
        MINGW*|MSYS*|CYGWIN*) echo "windows" ;;
        Linux*)               echo "linux"   ;;
        Darwin*)              echo "macos"   ;;
        *)                    echo "unknown" ;;
    esac
}

# ── Python discovery ──────────────────────────────────────────────────────────
# Sets PYTHON to the best available Python binary (venv first, then system).
# Requires VENV_DIR to be set. Returns 1 if no Python found.
find_python() {
    PYTHON=""
    if [[ -f "$VENV_DIR/Scripts/python.exe" ]] && [[ "$OSTYPE" != linux* ]]; then
        PYTHON="$VENV_DIR/Scripts/python.exe"
    elif [[ -f "$VENV_DIR/bin/python" ]]; then
        PYTHON="$VENV_DIR/bin/python"
    else
        local cmd
        for cmd in python3 python; do
            if "$cmd" --version &>/dev/null; then
                PYTHON="$cmd"
                break
            fi
        done
    fi
    [[ -n "$PYTHON" ]]
}

# ── Venv Python lookup ────────────────────────────────────────────────────────
# Sets _venv_python to the venv's Python binary path, or empty if not found.
# Requires VENV_DIR to be set.
find_venv_python() {
    _venv_python=""
    if [[ -f "$VENV_DIR/Scripts/python.exe" ]] && [[ "$OSTYPE" != linux* ]]; then
        _venv_python="$VENV_DIR/Scripts/python.exe"
    elif [[ -f "$VENV_DIR/bin/python" ]]; then
        _venv_python="$VENV_DIR/bin/python"
    fi
}

# ── Directory symlink helper ──────────────────────────────────────────────────
# ensure_symlink SOURCE TARGET LABEL
#   SOURCE — the dotfiles directory to link from (e.g. "$DOTFILES/skills")
#   TARGET — the consumer location           (e.g. "$HOME/.claude/skills")
#   LABEL  — human-readable name for logging (e.g. "~/.claude/skills")
#
# Behaviour:
#   1. Already a correct symlink → skip (yellow)
#   2. Stale symlink → repoint (green)
#   3. Real directory exists → remove and replace with symlink (green)
#      On Windows, if symlink fails, delete-then-copy (never copy-into)
#   4. Nothing exists → create symlink (green)
#      On Windows fallback: delete-then-copy
#
# Sets _fail=1 on unrecoverable errors.
ensure_symlink() {
    local source="$1" target="$2" label="$3"
    local _os="${OS:-$(detect_os)}"

    if [[ -L "$target" ]]; then
        local _current
        _current=$(readlink "$target")
        if [[ "$_current" == "$source" ]]; then
            yellow "  $label is already symlinked correctly — skipping"
            return 0
        else
            ln -sf "$source" "$target"
            green "  Fixed stale symlink at $label (was $_current)"
            return 0
        fi
    fi

    # Real directory exists — replace it
    if [[ -d "$target" ]]; then
        yellow "  $label exists as a real directory — replacing with symlink"
        rm -rf "$target"
    fi

    # Create symlink (or copy on Windows)
    ln -sf "$source" "$target"
    if [[ -L "$target" ]]; then
        green "  Symlinked $label -> $source"
    elif [[ "$_os" == "windows" ]]; then
        # Symlink failed on Windows — delete-then-copy (never copy-into)
        rm -rf "$target" 2>/dev/null
        cp -r "$source" "$target"
        if [[ -d "$target" ]]; then
            yellow "  Copied $label (Windows: directory symlinks require Developer Mode)"
        else
            red "  Failed to copy $label — check permissions"
            _fail=1
        fi
    else
        red "  Symlink creation failed for $label — check permissions"
        _fail=1
    fi
}
