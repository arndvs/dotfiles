#!/usr/bin/env python3
# FAIL_MODE: open
"""Feedback memory gate for Claude Code hooks.

PostToolUse hook (Write matcher). Fires after a feedback memory file is written.
If the content describes a bug but has no issue tracker reference, warns Claude
to create one.

Non-feedback-memory writes exit immediately (fast path).

Lifted from claude-mechanisms-tools/hooks/feedback-memory-gate.py.
Configurable issue prefix via CTRLSHFT_ISSUE_PREFIX env var.
"""

import json
import os
import re
import sys

# Keywords that suggest the feedback memory describes a bug or broken behavior.
# Matched case-insensitively against the file content.
BUG_INDICATORS = [
    r"\bbug\b",
    r"\bbroken\b",
    r"\bfails?\b",
    r"\bfailing\b",
    r"\berror\b",
    r"\bwrong\b",
    r"\bshould .+ instead\b",
    r"\bfix\b",
    r"\bcrash",
    r"\bmissing\b",
    r"\bnever\b.*\bshould\b",
    r"\bdoesn'?t work\b",
    r"\bincorrect\b",
]

BUG_PATTERN = re.compile("|".join(BUG_INDICATORS), re.IGNORECASE)

# Configurable issue prefix. Default: any JIRA/Linear-style XX-NN pattern.
# Set CTRLSHFT_ISSUE_PREFIX=CC to only match CC-NN, or PROJ to match PROJ-NN.
_issue_prefix = os.environ.get("CTRLSHFT_ISSUE_PREFIX", "").strip()
_prefix_pattern = re.escape(_issue_prefix) + r"-" if _issue_prefix else r"[A-Z]+-"
ISSUE_REF_PATTERN = re.compile(
    r"\*\*Linear:\*\*\s*" + _prefix_pattern + r"\d+", re.IGNORECASE
)

FEEDBACK_PATH_PATTERN = re.compile(r"claude-memory/feedback_.*\.md$")


def info(message):
    """Output informational context (non-blocking)."""
    print(json.dumps({
        "hookSpecificOutput": {
            "hookEventName": "PostToolUse",
            "additionalContext": message,
        }
    }))
    sys.exit(0)


def allow():
    """Allow silently (no output)."""
    sys.exit(0)


def main():
    try:
        stdin_data = sys.stdin.read()
        hook_input = json.loads(stdin_data) if stdin_data.strip() else {}
    except json.JSONDecodeError:
        allow()

    tool_input = hook_input.get("tool_input", {})
    file_path = tool_input.get("file_path", "")

    # Fast path: not a feedback memory file
    if not FEEDBACK_PATH_PATTERN.search(file_path):
        allow()

    content = tool_input.get("content", "")

    # Already has an issue tracker reference
    if ISSUE_REF_PATTERN.search(content):
        allow()

    # Check for bug indicators
    if BUG_PATTERN.search(content):
        info(
            "FEEDBACK MEMORY GATE: This feedback memory describes a bug or "
            "broken behavior but has no issue tracker reference. Create an "
            "issue (label: Bug, appropriate project) and add "
            "'**Linear:** PREFIX-NN' to this file."
        )

    # Not bug-like, exit silently
    allow()


if __name__ == "__main__":
    try:
        main()
    except Exception as e:
        # Fail-open: hook errors should not block the user
        sys.stderr.write(f"feedback-memory-gate error: {e}\n")
        sys.exit(0)
