"""Unit tests for hooks/plan-review-phase2.py + lib/plan_files_lib.py.

Lifted from claude-mechanisms-tools/tests/test_plan_review_gate.py.
Adapted for ctrlshft repo layout and standalone Phase 2 hook.

Tests cover:
- is_pr_create_command (CC-175 shlex tokenization)
- parse_head_branch (CC-174 --head/-H parsing)
- extract_plan_files + normalize_to_repo_relative (shared lib)
- phase2_check (diff comparison logic)
- format_phase2_checklist (output formatting)
- find_best_plan_for_diff (CC-80 best-match selection)
- Hook entry point (subprocess integration)

Run: python3 -m unittest discover -s test/python -p "test_*.py" -v
"""

import json
import os

# Pin REPO_PREFIXES for tests — fixtures use ~/myOS/ and /Users/christophe/myOS/ literals.
os.environ["CLAUDE_PLAN_REPO_PREFIXES"] = "~/myOS/,/Users/christophe/myOS/"

import importlib.util
import subprocess
import sys
import tempfile
import textwrap
import unittest
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent.parent
GATE_SCRIPT = REPO_ROOT / "hooks" / "plan-review-phase2.py"
CWD = str(REPO_ROOT)

# --- Import the hook module for direct testing ---
_spec = importlib.util.spec_from_file_location(
    "plan_review_phase2",
    str(GATE_SCRIPT),
)
prp = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(prp)

# --- Import plan_files_lib for direct testing ---
_lib_spec = importlib.util.spec_from_file_location(
    "plan_files_lib",
    str(REPO_ROOT / "lib" / "plan_files_lib.py"),
)
pfl = importlib.util.module_from_spec(_lib_spec)
_lib_spec.loader.exec_module(pfl)


# --- Test fixtures ---

COMPLETE_PLAN = textwrap.dedent("""\
    # Plan: Test Plan

    ## Context

    This is a test plan.

    ## Files to create/modify

    1. **`~/myOS/scripts/foo.py`** (new)
    2. **`~/myOS/docs/changelog.md`** (modify)
    3. **`~/myOS/docs/session-learnings.md`** (modify)

    ## Tests

    1. test_foo -- basic test

    ## Verification

    1. Run tests
""")


def run_gate(hook_input, timeout=10):
    """Run the Phase 2 gate script via subprocess."""
    result = subprocess.run(
        [sys.executable, str(GATE_SCRIPT)],
        input=json.dumps(hook_input),
        capture_output=True,
        text=True,
        timeout=timeout,
        cwd=CWD,
    )
    return result.stdout.strip(), result.stderr.strip(), result.returncode


def parse_output(stdout):
    if not stdout:
        return None
    try:
        return json.loads(stdout)
    except json.JSONDecodeError:
        return None


def get_decision(output):
    if not output:
        return None
    return output.get("hookSpecificOutput", {}).get("permissionDecision")


def get_context(output):
    if not output:
        return ""
    return output.get("hookSpecificOutput", {}).get("additionalContext", "")


# ============================================================
# is_pr_create_command (CC-175)
# ============================================================

class TestIsPrCreateCommand(unittest.TestCase):
    """CC-175: token-aware match prevents false positives on quoted text."""

    # --- Positive (gate should fire) ---

    def test_plain_pr_create(self):
        self.assertTrue(prp.is_pr_create_command("gh pr create --title x"))

    def test_plain_pr_edit(self):
        self.assertTrue(prp.is_pr_create_command("gh pr edit 5 --body y"))

    def test_chained_with_cd(self):
        self.assertTrue(prp.is_pr_create_command("cd /tmp && gh pr create --title x"))

    def test_env_var_prefix(self):
        self.assertTrue(prp.is_pr_create_command("EDITOR=vim gh pr create"))

    def test_equals_form_args(self):
        self.assertTrue(prp.is_pr_create_command("gh pr create --title=x --body=y"))

    # --- Negative (gate should NOT fire) ---

    def test_phrase_in_quoted_body(self):
        self.assertFalse(prp.is_pr_create_command(
            'git commit -m "discusses gh pr create in body"'
        ))

    def test_phrase_in_echo(self):
        self.assertFalse(prp.is_pr_create_command('echo "gh pr create"'))

    def test_wrong_subcommand(self):
        self.assertFalse(prp.is_pr_create_command("gh pr list"))

    def test_incomplete_gh_pr(self):
        self.assertFalse(prp.is_pr_create_command("gh pr"))

    # --- Edge cases ---

    def test_empty_string(self):
        self.assertFalse(prp.is_pr_create_command(""))

    def test_none(self):
        self.assertFalse(prp.is_pr_create_command(None))

    def test_malformed_quotes_falls_back_to_substring(self):
        self.assertTrue(prp.is_pr_create_command(
            'gh pr create --title "missing close'
        ))


# ============================================================
# parse_head_branch (CC-174)
# ============================================================

class TestParseHeadBranch(unittest.TestCase):
    """CC-174: parse --head value from gh pr create command."""

    def test_long_form_with_space(self):
        cmd = "gh pr create --base main --head feat/foo --title 'x'"
        self.assertEqual(prp.parse_head_branch(cmd), "feat/foo")

    def test_short_form_with_space(self):
        cmd = "gh pr create -B main -H feat/foo -t 'x'"
        self.assertEqual(prp.parse_head_branch(cmd), "feat/foo")

    def test_equals_form(self):
        cmd = "gh pr create --head=feat/foo --base=main"
        self.assertEqual(prp.parse_head_branch(cmd), "feat/foo")

    def test_no_head(self):
        cmd = "gh pr create --base main --title 'x'"
        self.assertIsNone(prp.parse_head_branch(cmd))

    def test_empty_command(self):
        self.assertIsNone(prp.parse_head_branch(""))

    def test_none_command(self):
        self.assertIsNone(prp.parse_head_branch(None))

    def test_branch_with_slashes_and_hyphens(self):
        cmd = "gh pr create --head fix/cc-174-plan-gate-head-branch"
        self.assertEqual(prp.parse_head_branch(cmd), "fix/cc-174-plan-gate-head-branch")

    def test_head_value_appears_in_branch_substring(self):
        cmd = "gh pr create --head feat/main-fixes --base main"
        self.assertEqual(prp.parse_head_branch(cmd), "feat/main-fixes")


# ============================================================
# File extraction (shared lib)
# ============================================================

class TestFileExtraction(unittest.TestCase):
    """Phase 2: file path extraction from ## Files section."""

    def test_prose_path_extraction(self):
        repo_files, external, conditional = pfl.extract_plan_files(COMPLETE_PLAN)
        self.assertIn("~/myOS/scripts/foo.py", repo_files)
        self.assertIn("~/myOS/docs/changelog.md", repo_files)

    def test_run_prefix_skipped(self):
        plan = textwrap.dedent("""\
            ## Files to create/modify

            1. **`~/myOS/scripts/foo.py`** (new)
            2. **Run:** `scripts/install-skills.sh`
        """)
        repo_files, _, _ = pfl.extract_plan_files(plan)
        self.assertEqual(len(repo_files), 1)
        self.assertIn("~/myOS/scripts/foo.py", repo_files)

    def test_conditional_file_detected(self):
        plan = textwrap.dedent("""\
            ## Files to create/modify

            1. **`~/myOS/scripts/foo.py`** (new)
            2. **`~/myOS/scripts/bar.py`** (if date logic extracted)
        """)
        repo_files, _, conditional = pfl.extract_plan_files(plan)
        self.assertEqual(len(repo_files), 1)
        self.assertEqual(len(conditional), 1)

    def test_external_path_detected(self):
        plan = textwrap.dedent("""\
            ## Files to create/modify

            1. **`~/myOS/scripts/foo.py`** (new)
            2. **`~/.claude/settings.json`** (modify)
        """)
        repo_files, external, _ = pfl.extract_plan_files(plan)
        self.assertEqual(len(repo_files), 1)
        self.assertEqual(len(external), 1)
        self.assertIn("~/.claude/settings.json", external)

    def test_no_files_section(self):
        plan = "## Context\n\nSome plan without files section."
        repo_files, external, conditional = pfl.extract_plan_files(plan)
        self.assertEqual(repo_files, [])
        self.assertEqual(external, [])
        self.assertEqual(conditional, [])


# ============================================================
# Path normalization (shared lib)
# ============================================================

class TestPathNormalization(unittest.TestCase):
    """Phase 2: path normalization to repo-relative."""

    def test_tilde_myos_prefix(self):
        result = pfl.normalize_to_repo_relative("~/myOS/scripts/foo.py")
        self.assertEqual(result, "scripts/foo.py")

    def test_absolute_path(self):
        result = pfl.normalize_to_repo_relative("/Users/christophe/myOS/scripts/foo.py")
        self.assertEqual(result, "scripts/foo.py")

    def test_relative_path(self):
        result = pfl.normalize_to_repo_relative("scripts/foo.py")
        self.assertEqual(result, "scripts/foo.py")


# ============================================================
# find_best_plan_for_diff (CC-80)
# ============================================================

class TestFindPlanForDiff(unittest.TestCase):
    """CC-80: pick plan by best diff overlap, not global mtime."""

    PLAN_A = textwrap.dedent("""\
        # Plan: session A
        ## Files
        - `~/myOS/scripts/foo.py`
        - `~/myOS/tests/test_foo.py`
    """)

    PLAN_B = textwrap.dedent("""\
        # Plan: session B
        ## Files
        - `~/myOS/docs/changelog.md`
        - `~/myOS/docs/session-learnings.md`
    """)

    PLAN_C = textwrap.dedent("""\
        # Plan: session C (partial overlap)
        ## Files
        - `~/myOS/scripts/foo.py`
        - `~/myOS/scripts/bar.py`
    """)

    def test_picks_best_overlap(self):
        with tempfile.TemporaryDirectory() as tmpdir:
            tmp = Path(tmpdir)
            (tmp / "a.md").write_text(self.PLAN_A)
            (tmp / "b.md").write_text(self.PLAN_B)
            (tmp / "c.md").write_text(self.PLAN_C)
            diff = {"docs/changelog.md", "docs/session-learnings.md", "scripts/foo.py"}
            result = pfl.find_best_plan_for_diff(diff, plans_dir=tmp)
            self.assertIsNotNone(result)
            self.assertEqual(result.name, "b.md")

    def test_no_overlap_returns_none(self):
        with tempfile.TemporaryDirectory() as tmpdir:
            tmp = Path(tmpdir)
            (tmp / "a.md").write_text(self.PLAN_A)
            (tmp / "b.md").write_text(self.PLAN_B)
            diff = {"README.md"}
            result = pfl.find_best_plan_for_diff(diff, plans_dir=tmp)
            self.assertIsNone(result)

    def test_ties_break_on_mtime(self):
        with tempfile.TemporaryDirectory() as tmpdir:
            tmp = Path(tmpdir)
            older = tmp / "older.md"
            older.write_text(self.PLAN_A)
            import time
            time.sleep(0.05)
            newer = tmp / "newer.md"
            newer.write_text(self.PLAN_A)
            diff = {"scripts/foo.py"}
            result = pfl.find_best_plan_for_diff(diff, plans_dir=tmp)
            self.assertIsNotNone(result)
            self.assertEqual(result.name, "newer.md")

    def test_empty_plans_dir(self):
        with tempfile.TemporaryDirectory() as tmpdir:
            result = pfl.find_best_plan_for_diff({"a.py"}, plans_dir=Path(tmpdir))
            self.assertIsNone(result)

    def test_missing_plans_dir(self):
        result = pfl.find_best_plan_for_diff({"a.py"}, plans_dir=Path("/nonexistent/path"))
        self.assertIsNone(result)

    def test_plan_without_files_section_skipped(self):
        with tempfile.TemporaryDirectory() as tmpdir:
            tmp = Path(tmpdir)
            (tmp / "no-files.md").write_text("# Plan with no files section\n\nJust prose.\n")
            (tmp / "has-files.md").write_text(self.PLAN_B)
            diff = {"docs/changelog.md"}
            result = pfl.find_best_plan_for_diff(diff, plans_dir=tmp)
            self.assertIsNotNone(result)
            self.assertEqual(result.name, "has-files.md")

    def test_regression_cc80_cross_session_leak(self):
        """CC-80 repro: session A's plan must not block session B's PR."""
        with tempfile.TemporaryDirectory() as tmpdir:
            tmp = Path(tmpdir)
            session_a = tmp / "session-a.md"
            session_a.write_text(textwrap.dedent("""\
                # Plan: interview coach work
                ## Files
                - `~/myOS/content/drafts/interview-coach-contribution/negotiation-protocol-draft.md`
                - `~/myOS/content/drafts/interview-coach-contribution/outline.md`
            """))
            import time
            time.sleep(0.05)
            session_b = tmp / "session-b.md"
            session_b.write_text(textwrap.dedent("""\
                # Plan: dispatcher fix
                ## Files
                - `~/myOS/scripts/open-for-review.py`
            """))
            diff = {"scripts/open-for-review.py"}

            # Swap mtimes so session-a is newest (old behavior would pick it)
            a_mtime = session_a.stat().st_mtime
            b_mtime = session_b.stat().st_mtime
            os.utime(session_a, (b_mtime, b_mtime))
            os.utime(session_b, (a_mtime, a_mtime))

            result = pfl.find_best_plan_for_diff(diff, plans_dir=tmp)
            self.assertIsNotNone(result)
            self.assertEqual(result.name, "session-b.md",
                             "CC-80 regression: picked newest plan instead of best-overlap plan")


# ============================================================
# phase2_check
# ============================================================

class TestPhase2Check(unittest.TestCase):
    """Phase 2 diff comparison logic."""

    def test_all_files_in_diff_passes(self):
        diff_files = {"scripts/foo.py", "docs/changelog.md", "docs/session-learnings.md"}
        passed, missing, warnings = prp.phase2_check(COMPLETE_PLAN, CWD, diff_files=diff_files)
        self.assertTrue(passed)
        self.assertEqual(missing, [])

    def test_missing_file_fails(self):
        diff_files = {"docs/changelog.md", "docs/session-learnings.md"}
        passed, missing, _ = prp.phase2_check(COMPLETE_PLAN, CWD, diff_files=diff_files)
        self.assertFalse(passed)
        self.assertEqual(len(missing), 1)

    def test_no_files_section_passes(self):
        plan = "## Context\n\nSome plan without files section."
        passed, missing, warnings = prp.phase2_check(plan, CWD, diff_files=set())
        self.assertTrue(passed)

    def test_external_files_warn(self):
        plan = textwrap.dedent("""\
            ## Files to create/modify

            1. **`~/myOS/scripts/foo.py`** (new)
            2. **`~/.claude/settings.json`** (modify)
        """)
        diff_files = {"scripts/foo.py"}
        passed, missing, warnings = prp.phase2_check(plan, CWD, diff_files=diff_files)
        self.assertTrue(passed)
        self.assertTrue(any("external" in w for w in warnings))


# ============================================================
# Checklist formatting
# ============================================================

class TestPhase2Formatting(unittest.TestCase):
    """Phase 2 checklist output formatting."""

    def test_all_pass_format(self):
        msg = prp.format_phase2_checklist(COMPLETE_PLAN, [], [])
        self.assertIn("PRE-PR AUDIT:", msg)
        self.assertIn("[PASS]", msg)
        self.assertIn("RESULT: PASS", msg)
        self.assertNotIn("[FAIL]", msg)

    def test_missing_file_format(self):
        msg = prp.format_phase2_checklist(
            COMPLETE_PLAN,
            ["~/myOS/scripts/foo.py"],
            []
        )
        self.assertIn("[FAIL] scripts/foo.py -- not in diff", msg)
        self.assertIn("RESULT: FAIL", msg)

    def test_external_warn_format(self):
        plan = textwrap.dedent("""\
            ## Files to create/modify

            1. **`~/myOS/scripts/foo.py`** (new)
            2. **`~/.claude/settings.json`** (modify)
        """)
        msg = prp.format_phase2_checklist(plan, [], ["~/.claude/settings.json (external -- verify manually)"])
        self.assertIn("[WARN] ~/.claude/settings.json (external -- verify manually)", msg)

    def test_conditional_skip_format(self):
        plan = textwrap.dedent("""\
            ## Files to create/modify

            1. **`~/myOS/scripts/foo.py`** (new)
            2. **`~/myOS/scripts/bar.py`** (if needed)
        """)
        msg = prp.format_phase2_checklist(plan, [], [])
        self.assertIn("[SKIP]", msg)
        self.assertIn("(conditional)", msg)

    def test_no_files_format(self):
        plan = "## Context\n\nSome plan without files section."
        msg = prp.format_phase2_checklist(plan, [], [])
        self.assertIn("RESULT: PASS (0/0 repo files in diff)", msg)


# ============================================================
# Hook entry point (subprocess)
# ============================================================

class TestHookEntryPoint(unittest.TestCase):
    """System tests: full subprocess invocation."""

    def test_non_pr_command_is_silent(self):
        stdout, _, code = run_gate({
            "tool_name": "Bash",
            "tool_input": {"command": "git status"},
            "cwd": CWD,
        })
        self.assertEqual(code, 0)
        self.assertEqual(stdout, "")

    def test_empty_stdin(self):
        result = subprocess.run(
            [sys.executable, str(GATE_SCRIPT)],
            input="",
            capture_output=True,
            text=True,
            timeout=10,
        )
        self.assertEqual(result.returncode, 0)
        self.assertEqual(result.stdout.strip(), "")

    def test_invalid_json(self):
        result = subprocess.run(
            [sys.executable, str(GATE_SCRIPT)],
            input="not json at all",
            capture_output=True,
            text=True,
            timeout=10,
        )
        self.assertEqual(result.returncode, 0)
        self.assertEqual(result.stdout.strip(), "")

    def test_pr_create_triggers_phase2(self):
        """gh pr create in a git repo should trigger Phase 2 logic."""
        stdout, _, code = run_gate({
            "tool_name": "Bash",
            "tool_input": {"command": "gh pr create --title test"},
            "cwd": CWD,
        })
        self.assertEqual(code, 0)
        # Should either find a plan and check, or skip with a message
        if stdout:
            output = parse_output(stdout)
            ctx = get_context(output)
            decision = get_decision(output)
            # Either skipped (no plan) or checked
            self.assertTrue(
                "SKIPPED" in ctx or "AUDIT" in ctx or decision == "deny",
                f"Unexpected output: {stdout}"
            )


# ============================================================
# H3 heading support
# ============================================================

class TestH3HeadingSupport(unittest.TestCase):
    """Test that h3 (###) headings are recognized for file extraction."""

    H3_PLAN = textwrap.dedent("""\
        # Plan: H3 Test

        ## Context

        Some context.

        ## Implementation

        ### Files to create/modify

        **Code:**

        1. **`~/myOS/scripts/plan-review-gate.py`** (new)

        **Spec doc:**

        2. **`~/myOS/docs/plan-review-gate.md`** (new)

        **Bundled docs:**

        3. **`~/myOS/docs/changelog.md`** (modify)
        4. **`~/myOS/docs/session-learnings.md`** (modify)

        ### Tests

        1. test_foo -- basic test

        ## Verification

        1. Run tests
    """)

    def test_h3_files_section_extracted(self):
        repo_files, _, _ = pfl.extract_plan_files(self.H3_PLAN)
        self.assertIn("~/myOS/scripts/plan-review-gate.py", repo_files)
        self.assertIn("~/myOS/docs/plan-review-gate.md", repo_files)
        self.assertIn("~/myOS/docs/changelog.md", repo_files)
        self.assertIn("~/myOS/docs/session-learnings.md", repo_files)
        self.assertEqual(len(repo_files), 4)

    def test_h3_files_stops_at_tests_section(self):
        repo_files, _, _ = pfl.extract_plan_files(self.H3_PLAN)
        self.assertNotIn("test_foo", str(repo_files))


if __name__ == "__main__":
    unittest.main()
