#!/usr/bin/env python3
# FAIL_MODE: open
"""Plan review gate — Phase 2: PR diff comparison.

PreToolUse hook (Bash matcher). Fires before `gh pr create` or `gh pr edit`.
Compares the plan's ## Files section against the actual git diff to catch
execution gaps — planned files that weren't touched.

Fail-open: any unhandled exception allows with a SKIPPED warning.

Key adaptations from claude-mechanisms-tools/hooks/plan-review-gate.py:
- CC-175: shlex-tokenized `gh pr create` detection (prevents false positives
  from commit messages mentioning the phrase)
- CC-174: --head/-H branch parsing (diff targets the correct branch)
- CC-80: best-match plan selection by diff overlap (not global mtime)

Imports shared utilities from lib/plan_files_lib.py.
"""

import json
import os
import re
import shlex
import subprocess
import sys
from pathlib import Path

# Wire up shared lib
_REPO_ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(_REPO_ROOT / "lib"))
from plan_files_lib import (  # noqa: E402
    extract_plan_files,
    find_best_plan_for_diff,
    normalize_to_repo_relative,
)


def info(message):
    """Output informational context (non-blocking) and exit."""
    print(json.dumps({
        "hookSpecificOutput": {
            "hookEventName": "PreToolUse",
            "additionalContext": message,
        }
    }), file=sys.stderr)
    sys.exit(0)


def allow():
    """Allow silently."""
    sys.exit(0)


_ENV_ASSIGNMENT_RE = re.compile(r"^[A-Za-z_][A-Za-z0-9_]*=.*$")

_PR_CREATE_BOUNDARY_RE = re.compile(
    r"(^|;|\|\||&&|\|)\s*(?:[A-Za-z_][A-Za-z0-9_]*=\S+\s+)*gh\s+pr\s+(?:create|edit)(?=\s|$)"
)


def _matches_pr_create_at_segment_start(tokens, start_index):
    """Return True iff a command segment starting at start_index begins with `gh pr create|edit`."""
    i = start_index
    while i < len(tokens) and _ENV_ASSIGNMENT_RE.match(tokens[i]):
        i += 1
    return (
        i + 2 < len(tokens)
        and tokens[i] == "gh"
        and tokens[i + 1] == "pr"
        and tokens[i + 2] in ("create", "edit")
    )


def is_pr_create_command(command):
    """Return True iff the Bash command actually invokes `gh pr create` or `gh pr edit`.

    Matches only at shell command boundaries (start of the command, or after
    `;`, `&&`, `||`, `|`), optionally preceded by environment-variable
    assignments. Quoted strings and other arguments remain opaque tokens and
    cannot trigger a false positive. Falls back to a boundary-aware regex on
    shlex parse error. CC-175.
    """
    if not command:
        return False
    try:
        lexer = shlex.shlex(command, posix=True, punctuation_chars="|&;")
        lexer.whitespace_split = True
        lexer.commenters = ""
        tokens = list(lexer)
    except ValueError:
        return bool(_PR_CREATE_BOUNDARY_RE.search(command))

    # Merge doubled punctuation (&&, ||) into single tokens
    merged: list[str] = []
    i = 0
    while i < len(tokens):
        tok = tokens[i]
        if tok in ("&", "|") and i + 1 < len(tokens) and tokens[i + 1] == tok:
            merged.append(tok + tok)
            i += 2
            continue
        merged.append(tok)
        i += 1

    segment_start = True
    for i, tok in enumerate(merged):
        if tok in (";", "&&", "||", "|"):
            segment_start = True
            continue
        if segment_start:
            if _matches_pr_create_at_segment_start(merged, i):
                return True
            segment_start = False
    return False


def parse_head_branch(command):
    """Extract the value of --head / -H / --head=<branch> from a gh command.

    Uses shlex tokenization so values embedded inside --body or --title
    quotes are never matched. Falls back to regex on shlex parse error.
    CC-174.
    """
    if not command:
        return None
    try:
        tokens = shlex.split(command, comments=False, posix=True)
    except ValueError:
        # Fall back to regex on parse error (fail-open)
        eq_match = re.search(r"--head=(\S+)", command)
        if eq_match:
            return eq_match.group(1)
        return None
    for i, tok in enumerate(tokens):
        if tok.startswith("--head="):
            return tok.split("=", 1)[1] or None
        if tok in ("--head", "-H") and i + 1 < len(tokens):
            return tokens[i + 1]
    return None


def _default_branch(repo_root):
    """Detect a valid base branch for diffing. Returns None when no candidate exists."""
    def _git_ok(args):
        try:
            r = subprocess.run(
                ["git", *args],
                capture_output=True, text=True, cwd=repo_root, timeout=5
            )
            return r if r.returncode == 0 else None
        except (subprocess.TimeoutExpired, FileNotFoundError):
            return None

    # 1. origin/HEAD symbolic ref
    r = _git_ok(["symbolic-ref", "refs/remotes/origin/HEAD"])
    if r:
        ref = r.stdout.strip().replace("refs/remotes/origin/", "")
        if _git_ok(["rev-parse", "--verify", f"{ref}^{{commit}}"]):
            return ref

    # 2. Current branch's upstream
    r = _git_ok(["rev-parse", "--abbrev-ref", "--symbolic-full-name", "@{upstream}"])
    if r:
        upstream = r.stdout.strip()
        if _git_ok(["rev-parse", "--verify", f"{upstream}^{{commit}}"]):
            return upstream

    # 3. Common default branch names (local and remote)
    for candidate in ("main", "master", "origin/main", "origin/master"):
        if _git_ok(["rev-parse", "--verify", f"{candidate}^{{commit}}"]):
            return candidate

    return None


def get_diff_files(cwd, head_ref=None):
    """Compute the set of changed files for the diff target relative to the default branch.

    When head_ref is provided, diff against that branch only (CC-174).
    When None, fall back to HEAD plus unstaged/staged/untracked from cwd.

    Returns (diff_files: set[str], skip_reason: str|None).
    """
    try:
        result = subprocess.run(
            ["git", "rev-parse", "--show-toplevel"],
            capture_output=True, text=True, cwd=cwd, timeout=5
        )
        if result.returncode != 0:
            return set(), "not in a git repo -- skipping file audit"
        repo_root = result.stdout.strip()
    except (subprocess.TimeoutExpired, FileNotFoundError):
        return set(), "git not available -- skipping file audit"

    diff_target = head_ref if head_ref else "HEAD"

    # Validate head_ref resolves; skip with warning if user-specified ref is invalid.
    if head_ref:
        try:
            check = subprocess.run(
                ["git", "rev-parse", "--verify", f"{head_ref}^{{commit}}"],
                capture_output=True, text=True, cwd=repo_root, timeout=5
            )
            if check.returncode != 0:
                return set(), (
                    f"--head ref '{head_ref}' does not resolve to a local commit "
                    "-- skipping file audit (fork syntax or missing remote?)"
                )
        except (subprocess.TimeoutExpired, FileNotFoundError):
            return set(), (
                f"--head ref '{head_ref}' could not be verified "
                "-- skipping file audit"
            )

    # Merge base
    default_branch = _default_branch(repo_root)
    if default_branch is None:
        return set(), "no default branch detected -- skipping file audit"
    # If the ref already contains a remote prefix (e.g. origin/main, upstream/main),
    # use it as-is; only prefix origin/ for plain local branch names (main, master).
    origin_ref = default_branch if "/" in default_branch else f"origin/{default_branch}"
    # Fall back to local default branch if origin remote-tracking ref is missing
    try:
        subprocess.run(
            ["git", "rev-parse", "--verify", origin_ref],
            capture_output=True, text=True, cwd=repo_root, timeout=5,
            check=True
        )
        base_ref = origin_ref
    except (subprocess.CalledProcessError, subprocess.TimeoutExpired,
            FileNotFoundError):
        base_ref = default_branch
    try:
        result = subprocess.run(
            ["git", "merge-base", diff_target, base_ref],
            capture_output=True, text=True, cwd=repo_root, timeout=5
        )
        base = result.stdout.strip() if result.returncode == 0 else base_ref
    except (subprocess.TimeoutExpired, FileNotFoundError):
        base = base_ref

    # Committed diff
    try:
        result = subprocess.run(
            ["git", "diff", "--name-only", f"{base}...{diff_target}"],
            capture_output=True, text=True, cwd=repo_root, timeout=10
        )
        if result.returncode != 0:
            return set(), "git diff failed -- skipping file audit"
        diff_files = set(result.stdout.strip().split("\n")) if result.stdout.strip() else set()
    except (subprocess.TimeoutExpired, FileNotFoundError):
        return set(), "git diff failed -- skipping file audit"

    # Best-effort: unstaged, staged, untracked (skip when head_ref is explicit).
    if head_ref is None:
        for args in (["diff", "--name-only", "HEAD"],
                     ["diff", "--name-only", "--cached"],
                     ["ls-files", "--others", "--exclude-standard"]):
            try:
                result = subprocess.run(
                    ["git"] + args,
                    capture_output=True, text=True, cwd=repo_root, timeout=5
                )
                if result.returncode == 0 and result.stdout.strip():
                    diff_files.update(result.stdout.strip().split("\n"))
            except (subprocess.TimeoutExpired, FileNotFoundError):
                pass

    return diff_files, None


def phase2_check(plan_text, cwd, diff_files=None):
    """Compare plan's file list against actual git diff.

    Returns (passed: bool, missing: list[str], warnings: list[str]).
    """
    repo_files, external_files, conditional_files = extract_plan_files(plan_text)

    if not repo_files and not external_files and not conditional_files:
        return True, [], ["no files listed in plan's ## Files section"]
    if not repo_files and not external_files:
        return True, [], ["only conditional files listed in plan's ## Files section"]

    if diff_files is None:
        diff_files, skip_reason = get_diff_files(cwd)
        if skip_reason:
            return True, [], [skip_reason]

    # Compare plan files against diff
    missing = []
    for path_str in repo_files:
        relative = normalize_to_repo_relative(path_str)
        if relative not in diff_files:
            missing.append(path_str)

    # External files are advisory only
    warnings = []
    for path_str in external_files:
        warnings.append(f"{path_str} (external -- verify manually)")

    return len(missing) == 0, missing, warnings


def format_phase2_checklist(plan_text, missing, warnings):
    """Format Phase 2 results as a per-file checklist."""
    repo_files, external_files, conditional_files = extract_plan_files(plan_text)
    lines = ["PRE-PR AUDIT:"]

    for path_str in repo_files:
        relative = normalize_to_repo_relative(path_str)
        if path_str in missing:
            lines.append(f"  [FAIL] {relative} -- not in diff")
        else:
            lines.append(f"  [PASS] {relative}")

    for warning in warnings:
        lines.append(f"  [WARN] {warning}")

    for path_str in conditional_files:
        relative = normalize_to_repo_relative(path_str)
        lines.append(f"  [SKIP] {relative} (conditional)")

    fail_count = sum(1 for line in lines if "[FAIL]" in line)
    warn_count = len(warnings)
    total_repo = len(repo_files)

    if fail_count > 0:
        lines.append(f"  RESULT: FAIL ({fail_count} planned file(s) not in diff)")
    else:
        summary = f"  RESULT: PASS ({total_repo}/{total_repo} repo files in diff"
        if warn_count > 0:
            summary += f", {warn_count} external to verify"
        summary += ")"
        lines.append(summary)

    return "\n".join(lines)


def main():
    try:
        stdin_data = sys.stdin.read()
        hook_input = json.loads(stdin_data) if stdin_data.strip() else {}
    except (json.JSONDecodeError, Exception):
        allow()

    tool_input = hook_input.get("tool_input") or hook_input.get("toolInput", {})
    cwd = hook_input.get("cwd", os.getcwd())
    command = tool_input.get("command", "")

    # Only fire on actual gh pr create/edit commands (CC-175)
    if not is_pr_create_command(command):
        allow()

    # Parse --head branch (CC-174)
    head_ref = parse_head_branch(command)

    # Compute diff files
    diff_files, skip_reason = get_diff_files(cwd, head_ref=head_ref)
    if skip_reason:
        info(f"PRE-PR AUDIT: SKIPPED ({skip_reason})")

    # Find best-matching plan by diff overlap (CC-80)
    plan_file = find_best_plan_for_diff(diff_files)
    if not plan_file:
        info(
            "PRE-PR AUDIT: SKIPPED -- no plan in ~/.claude/plans/ overlaps "
            "this diff. Either the PR's changes pre-date any plan, or this "
            "session never filed one. Not blocking."
        )

    try:
        plan_text = plan_file.read_text()
    except Exception as e:
        info(f"PRE-PR AUDIT: SKIPPED (error reading plan {plan_file.name}: {e})")

    passed, missing, warnings = phase2_check(plan_text, cwd, diff_files=diff_files)
    if not passed:
        msg = format_phase2_checklist(plan_text, missing, warnings)
        info(msg)
    elif warnings:
        details = "; ".join(warnings[:5])
        info(f"PRE-PR AUDIT: pass with {len(warnings)} warnings: {details}")
    else:
        allow()


if __name__ == "__main__":
    try:
        main()
    except Exception as e:
        # Fail-open: never block on unexpected errors
        print(json.dumps({
            "hookSpecificOutput": {
                "hookEventName": "PreToolUse",
                "additionalContext": f"PRE-PR AUDIT: SKIPPED (error: {e})",
            }
        }), file=sys.stderr)
        sys.exit(0)
