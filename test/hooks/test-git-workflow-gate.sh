#!/usr/bin/env bash
# test-git-workflow-gate.sh — Tests for hooks/git-workflow-gate.sh
#
# Run: bash test/hooks/test-git-workflow-gate.sh
#
# NOTE: These tests run the hook in isolation by feeding it JSON stdin.
# Tests that require a real git repo (dirty tree, branch checks) create
# temp repos. Network-dependent checks (frozen-branch, behind-origin)
# are not tested here.

set -euo pipefail
cd "$(git rev-parse --show-toplevel 2>/dev/null || echo "$(dirname "$0")/../..")"
source "test/hooks/test-helpers.sh"

HOOK="hooks/git-workflow-gate.sh"

echo "=== git-workflow-gate.sh tests ==="
echo ""

# ============================================================
# GATE 0: cd-chain detection
# ============================================================

echo "--- Gate 0: cd-chain block ---"

REPO=$(make_tmp_repo)

run_hook "$HOOK" "$(make_pretooluse_json 'cd /tmp/repo && git commit -m "test"' "$REPO")"
assert_deny "cd && git commit chain" "cd.*chain"

run_hook "$HOOK" "$(make_pretooluse_json 'cd /tmp/repo ; git push' "$REPO")"
assert_deny "cd ; git push chain" "cd.*chain"

run_hook "$HOOK" "$(make_pretooluse_json 'git status' "$REPO")"
assert_allow "bare git status (no cd chain)"

# ============================================================
# GATE 1: commit to protected branch + conventional message
# ============================================================

echo ""
echo "--- Gate 1: commit to main + message validation ---"

# Create a temp repo on main branch
REPO=$(make_tmp_repo)

run_hook "$HOOK" "$(make_pretooluse_json 'git commit -m "feat: add feature"' "$REPO")"
assert_deny "commit on main branch" "Cannot commit directly"

# Switch to feature branch for message validation tests
git -C "$REPO" checkout -b feat/test --quiet 2>/dev/null

run_hook "$HOOK" "$(make_pretooluse_json 'git commit -m "feat: valid message"' "$REPO")"
assert_allow "conventional commit message on feature branch"

run_hook "$HOOK" "$(make_pretooluse_json 'git commit -m "bad message no prefix"' "$REPO")"
assert_deny "non-conventional commit message" "conventional"

run_hook "$HOOK" "$(make_pretooluse_json 'git commit -m "fix(scope): scoped message"' "$REPO")"
assert_allow "scoped conventional message"

# ============================================================
# GATE 2: push safety (force-push)
# ============================================================

echo ""
echo "--- Gate 2: push safety ---"

REPO=$(make_tmp_repo)

run_hook "$HOOK" "$(make_pretooluse_json 'git push --force' "$REPO")"
assert_deny "git push --force" "force.*lease"

run_hook "$HOOK" "$(make_pretooluse_json 'git push -f' "$REPO")"
assert_deny "git push -f" "force.*lease"

run_hook "$HOOK" "$(make_pretooluse_json 'git push --force-with-lease' "$REPO")"
assert_allow "git push --force-with-lease"

run_hook "$HOOK" "$(make_pretooluse_json 'git push origin +HEAD:main' "$REPO")"
assert_deny "git push +refspec" "force"

run_hook "$HOOK" "$(make_pretooluse_json 'git push origin main' "$REPO")"
assert_allow "git push origin main (normal)"

# ============================================================
# GATE 3: dirty-tree switch
# ============================================================

echo ""
echo "--- Gate 3: dirty-tree branch switch ---"

REPO=$(make_tmp_repo)
git -C "$REPO" checkout -b feat/a --quiet 2>/dev/null
echo "dirty" >> "$REPO/README.md"

run_hook "$HOOK" "$(make_pretooluse_json 'git checkout main' "$REPO")"
assert_deny "checkout with dirty tree" "uncommitted"

run_hook "$HOOK" "$(make_pretooluse_json 'git checkout -b feat/new' "$REPO")"
assert_allow "checkout -b (create branch, not switch)"

run_hook "$HOOK" "$(make_pretooluse_json 'git switch -c feat/new2' "$REPO")"
assert_allow "switch -c (create branch, not switch)"

# ============================================================
# GATE 4: git reset --hard
# ============================================================

echo ""
echo "--- Gate 4: git reset --hard ---"

REPO=$(make_tmp_repo)

run_hook "$HOOK" "$(make_pretooluse_json 'git reset --hard HEAD~3' "$REPO")"
assert_deny "git reset --hard HEAD~3" "reset.*hard"

run_hook "$HOOK" "$(make_pretooluse_json 'git reset --soft HEAD~1' "$REPO")"
assert_allow "git reset --soft (not hard)"

# ============================================================
# GATE 5: git clean -f
# ============================================================

echo ""
echo "--- Gate 5: git clean -f ---"

REPO=$(make_tmp_repo)

run_hook "$HOOK" "$(make_pretooluse_json 'git clean -fd' "$REPO")"
assert_deny "git clean -fd" "clean"

run_hook "$HOOK" "$(make_pretooluse_json 'git clean -n' "$REPO")"
assert_allow "git clean -n (dry run)"

# ============================================================
# cd-C block
# ============================================================

echo ""
echo "--- cd -C flag block ---"

REPO=$(make_tmp_repo)

run_hook "$HOOK" "$(make_pretooluse_json 'git -C /tmp/other push' "$REPO")"
assert_deny "git -C flag" "Don.t use git"

# ============================================================
# GATE 1 (continued): --amend warning
# ============================================================

echo ""
echo "--- Gate 1: --amend warning ---"

REPO=$(make_tmp_repo)
git -C "$REPO" checkout -b feat/amend-test --quiet 2>/dev/null

run_hook "$HOOK" "$(make_pretooluse_json 'git commit --amend -m "feat: updated"' "$REPO")"
assert_warn "commit --amend warns" "amend"

run_hook "$HOOK" "$(make_pretooluse_json 'git commit --amend --no-edit' "$REPO")"
assert_warn "commit --amend --no-edit warns" "amend"

run_hook "$HOOK" "$(make_pretooluse_json 'git commit -m "feat: normal commit"' "$REPO")"
assert_allow "commit without --amend does not warn"

# ============================================================
# GATE 6: Interactive rebase warning
# ============================================================

echo ""
echo "--- Gate 6: interactive rebase warn ---"

REPO=$(make_tmp_repo)
git -C "$REPO" checkout -b feat/rebase-test --quiet 2>/dev/null
# Create a fake remote tracking branch
git -C "$REPO" config "branch.feat/rebase-test.remote" origin
git -C "$REPO" config "branch.feat/rebase-test.merge" refs/heads/feat/rebase-test
# Create an origin/feat/rebase-test ref
git -C "$REPO" update-ref refs/remotes/origin/feat/rebase-test HEAD

run_hook "$HOOK" "$(make_pretooluse_json 'git rebase -i HEAD~3' "$REPO")"
assert_warn "interactive rebase on pushed branch warns" "rebase"

run_hook "$HOOK" "$(make_pretooluse_json 'git rebase --interactive HEAD~2' "$REPO")"
assert_warn "rebase --interactive warns" "rebase"

run_hook "$HOOK" "$(make_pretooluse_json 'git rebase main' "$REPO")"
assert_allow "non-interactive rebase does not warn"

# ============================================================
# PostToolUse: post-commit nag
# ============================================================

echo ""
echo "--- PostToolUse: post-commit nag ---"

POST_COMMIT_HOOK="hooks/git-post-commit.sh"

REPO=$(make_tmp_repo)
git -C "$REPO" checkout -b feat/nag-test --quiet 2>/dev/null
echo "change" >> "$REPO/README.md"
git -C "$REPO" add . && git -C "$REPO" commit -m "feat: test commit" --quiet 2>/dev/null

run_hook "$POST_COMMIT_HOOK" "$(make_posttooluse_json 'git commit -m "feat: test"' "$REPO" 0)"
# No upstream configured → should exit silently
assert_allow "post-commit no upstream → silent"

# PostToolUse: non-commit command → silent
run_hook "$POST_COMMIT_HOOK" "$(make_posttooluse_json 'git status' "$REPO" 0)"
assert_allow "post-commit non-commit command → silent"

# PostToolUse: failed commit → silent
run_hook "$POST_COMMIT_HOOK" "$(make_posttooluse_json 'git commit -m "feat: fail"' "$REPO" 1)"
assert_allow "post-commit failed exit code → silent"

# ============================================================
# PostToolUse: post-push PR nag
# ============================================================

echo ""
echo "--- PostToolUse: post-push nag ---"

POST_PUSH_HOOK="hooks/git-post-push.sh"

REPO=$(make_tmp_repo)

# Non-push command → silent
run_hook "$POST_PUSH_HOOK" "$(make_posttooluse_json 'git status' "$REPO" 0)"
assert_allow "post-push non-push command → silent"

# Failed push → silent
run_hook "$POST_PUSH_HOOK" "$(make_posttooluse_json 'git push' "$REPO" 1)"
assert_allow "post-push failed exit code → silent"

# Push with -C flag → silent (handled by the hook)
run_hook "$POST_PUSH_HOOK" "$(make_posttooluse_json 'git -C /tmp/other push' "$REPO" 0)"
assert_allow "post-push git -C → silent"

report
