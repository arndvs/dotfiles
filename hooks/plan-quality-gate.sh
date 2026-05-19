#!/usr/bin/env bash
# FAIL_MODE: open
# plan-quality-gate.sh — PreToolUse hook: validate plan structure before scaffolding.
#
# Receives Claude Code PreToolUse JSON on stdin (matcher: Bash).
#
# Phase 1: When the command creates directories or scaffolds projects (mkdir,
#   npx create-, npm init, etc.), checks if a plan file exists at the git root.
#   If found, validates required sections and code-touching indicators.
#   Emits a checklist summary. Never blocks — warns only.
#
# Fail-open: non-git directories and missing tools silently pass.

set -euo pipefail
trap 'exit 0' ERR  # fail-open: any error → allow

if ! command -v jq &>/dev/null; then
    exit 0
fi

INPUT=$(cat)

# cd into the hook event's working directory
EVENT_CWD=$(echo "$INPUT" | jq -r '.cwd // empty')
if [[ -n "$EVENT_CWD" ]]; then
    cd "$EVENT_CWD" || exit 0  # fail-open
fi

TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name // empty')
[[ "$TOOL_NAME" == "Bash" ]] || exit 0

COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty')
[[ -n "$COMMAND" ]] || exit 0

# Only trigger on scaffolding/creation patterns (anchored to command boundaries)
SCAFFOLD_PATTERN='(^|;|&&|\|\|?|\|)[[:space:]]*(mkdir|npx[[:space:]]+create-[^[:space:]]+|npm init|yarn create|pnpm create|cookiecutter|degit|git clone)([[:space:]]|$)'
if ! echo "$COMMAND" | grep -qE "$SCAFFOLD_PATTERN"; then
    exit 0
fi

# Must be inside a git repo
GIT_ROOT=$(git rev-parse --show-toplevel 2>/dev/null) || exit 0

# --- Find plan file ---
PLAN_FILE=""
for candidate in PLAN.md plan.md .plan.md docs/PLAN.md docs/plan.md; do
    if [[ -f "$GIT_ROOT/$candidate" ]]; then
        PLAN_FILE="$GIT_ROOT/$candidate"
        break
    fi
done

# Also check ~/.claude/plans/ for the most recently modified plan
PLANS_DIR="$HOME/.claude/plans"
if [[ -z "$PLAN_FILE" && -d "$PLANS_DIR" ]]; then
    PLAN_FILE=$(ls -t "$PLANS_DIR"/*.md 2>/dev/null | head -1) || true
fi

if [[ -z "$PLAN_FILE" || ! -f "$PLAN_FILE" ]]; then
    # No plan found — emit info warning (never blocks)
    MSG="⚠️ No plan file found (PLAN.md, docs/PLAN.md, ~/.claude/plans/). Consider documenting your approach before scaffolding."
    jq -cn --arg msg "$MSG" '{"hookSpecificOutput":{"additionalContext":$msg}}' >&2
    exit 0
fi

# --- Read plan content ---
PLAN_TEXT=$(cat "$PLAN_FILE") || exit 0

# --- Read required sections from .ctrlshft config or use defaults ---
# Config key: plan_required_sections (comma-separated)
_config_val() {
    local key="$1" default="$2"
    local config_file="$GIT_ROOT/.ctrlshft"
    if [[ -f "$config_file" ]] && command -v grep &>/dev/null; then
        local val
        val=$(grep -E "^${key}:" "$config_file" 2>/dev/null | head -1 | sed 's/^[^:]*:[[:space:]]*//')
        if [[ -n "$val" ]]; then
            echo "$val"
            return
        fi
    fi
    echo "$default"
}

REQUIRED_SECTIONS=$(_config_val "plan_required_sections" "Context,Implementation,Test,Verification,Files")

# --- Section check helper ---
# Returns 0 if heading exists with at least one non-empty content line
_section_has_content() {
    local heading_pattern="$1"
    local in_section=false
    local found_content=false
    while IFS= read -r line; do
        if [[ "$in_section" == "true" ]]; then
            # Next heading at same level (##) → section ended; ### subsections are valid content
            if echo "$line" | grep -qE '^##[[:space:]]' && ! echo "$line" | grep -qiE "$heading_pattern"; then
                break
            fi
            # Non-empty, non-heading line = content (### subsections also count as content)
            if [[ -n "${line// /}" ]] && ! echo "$line" | grep -qE '^##[[:space:]]'; then
                found_content=true
                break
            fi
        fi
        if echo "$line" | grep -qiE "^#{2,3}[[:space:]]+.*${heading_pattern}"; then
            in_section=true
        fi
    done <<< "$PLAN_TEXT"
    [[ "$found_content" == "true" ]]
}

# --- Code-touching detection ---
_is_code_touching() {
    echo "$PLAN_TEXT" | grep -qiE '\.(py|js|ts|sh|json|yaml|yml|toml|bash)\b|scripts/|tests/|Dockerfile|Makefile|\.github/'
}

# --- Build checklist ---
RESULTS=()
FAIL_COUNT=0
WARN_COUNT=0
PASS_COUNT=0

_check() {
    local label="$1" status="$2"
    case "$status" in
        PASS) RESULTS+=("  [PASS] $label"); ((PASS_COUNT++)) ;;
        FAIL) RESULTS+=("  [FAIL] $label -- empty or missing"); ((FAIL_COUNT++)) ;;
        WARN) RESULTS+=("  [WARN] $label"); ((WARN_COUNT++)) ;;
    esac
}

# Check each required section
IFS=',' read -ra SECTIONS <<< "$REQUIRED_SECTIONS"
for section in "${SECTIONS[@]}"; do
    section=$(echo "$section" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
    if _section_has_content "$section"; then
        _check "$section" "PASS"
    else
        _check "$section" "FAIL"
    fi
done

# Code-touching checks (advisory)
if _is_code_touching; then
    if echo "$PLAN_TEXT" | grep -qiE 'changelog'; then
        _check "changelog reference" "PASS"
    else
        _check "changelog reference (code-touching plan)" "WARN"
    fi

    if echo "$PLAN_TEXT" | grep -qiE 'doc(s|umentation)?\s+to\s+(update|create)|doc(s|umentation)?\s+audit|#{2,3}\s+Doc'; then
        _check "docs audit" "PASS"
    else
        _check "docs audit (code-touching plan)" "WARN"
    fi
fi

# --- Format output ---
TOTAL=$((PASS_COUNT + FAIL_COUNT))
HEADER="PLAN REVIEW GATE ($(basename "$PLAN_FILE")):"
if [[ $FAIL_COUNT -gt 0 ]]; then
    SUMMARY="  RESULT: NEEDS ATTENTION ($FAIL_COUNT missing section(s)"
    [[ $WARN_COUNT -gt 0 ]] && SUMMARY+=", $WARN_COUNT advisory"
    SUMMARY+=")"
elif [[ $WARN_COUNT -gt 0 ]]; then
    SUMMARY="  RESULT: PASS ($TOTAL/$TOTAL sections, $WARN_COUNT advisory)"
else
    SUMMARY="  RESULT: PASS ($TOTAL/$TOTAL sections)"
fi

# Build the message
MSG=$(printf '%s\n' "$HEADER" "${RESULTS[@]}" "$SUMMARY")

# Emit as info (never blocks)
jq -cn --arg msg "$MSG" '{"hookSpecificOutput":{"additionalContext":$msg}}' >&2
exit 0
