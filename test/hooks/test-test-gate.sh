#!/usr/bin/env bash
# test-test-gate.sh — Tests for hooks/test-gate.sh
#
# Run: bash test/hooks/test-test-gate.sh

set -euo pipefail
cd "$(git rev-parse --show-toplevel 2>/dev/null || echo "$(dirname "$0")/../..")"
source "test/hooks/test-helpers.sh"

HOOK="hooks/test-gate.sh"

echo "=== test-gate.sh tests ==="
echo ""

# --- Skip cases ---

# Non-git-commit commands should be allowed
run_hook "$HOOK" "$(make_pretooluse_json 'echo hello')"
assert_allow "skip: non-git command"

run_hook "$HOOK" "$(make_pretooluse_json 'git push origin main')"
assert_allow "skip: git push (not commit)"

run_hook "$HOOK" "$(make_pretooluse_json 'git status')"
assert_allow "skip: git status"

# Amend commits should be skipped
run_hook "$HOOK" "$(make_pretooluse_json 'git commit --amend --no-edit')"
assert_allow "skip: git commit --amend"

# Empty command
run_hook "$HOOK" "$(make_pretooluse_json '')"
assert_allow "skip: empty command"

# --- CWD with no package.json ---

BARE_DIR=$(mktemp -d)
TMP_REPOS+=("$BARE_DIR")

run_hook "$HOOK" "$(make_pretooluse_json 'git commit -m "test"' "$BARE_DIR")"
assert_allow "skip: no package.json in cwd"

# --- CWD with package.json but no test script ---

NO_TEST_DIR=$(mktemp -d)
TMP_REPOS+=("$NO_TEST_DIR")
echo '{"scripts":{}}' > "$NO_TEST_DIR/package.json"
git -C "$NO_TEST_DIR" init -b main --quiet 2>/dev/null
git -C "$NO_TEST_DIR" config user.email "test@test.com"
git -C "$NO_TEST_DIR" config user.name "Test"
git -C "$NO_TEST_DIR" add . && git -C "$NO_TEST_DIR" commit -m "init" --quiet 2>/dev/null

run_hook "$HOOK" "$(make_pretooluse_json 'git commit -m "test"' "$NO_TEST_DIR")"
assert_allow "skip: no test script in package.json"

# --- CWD with test script but no testable files modified ---

NO_TS_DIR=$(make_tmp_repo)
echo '{"scripts":{"test":"echo ok"}}' > "$NO_TS_DIR/package.json"
echo "# readme" > "$NO_TS_DIR/README.md"
git -C "$NO_TS_DIR" add . && git -C "$NO_TS_DIR" commit -m "add pkg" --quiet 2>/dev/null
# Modify only a non-testable file
echo "update" >> "$NO_TS_DIR/README.md"
git -C "$NO_TS_DIR" add .

run_hook "$HOOK" "$(make_pretooluse_json 'git commit -m "docs"' "$NO_TS_DIR")"
assert_allow "skip: no testable (.ts/.js) files modified"

# --- Deny: tests fail ---

FAIL_DIR=$(make_tmp_repo)
echo '{"scripts":{"test":"exit 1"}}' > "$FAIL_DIR/package.json"
echo "export const x = 1;" > "$FAIL_DIR/index.ts"
git -C "$FAIL_DIR" add . && git -C "$FAIL_DIR" commit -m "add pkg" --quiet 2>/dev/null
# Stage a .ts file change
echo "export const x = 2;" > "$FAIL_DIR/index.ts"
git -C "$FAIL_DIR" add .

run_hook "$HOOK" "$(make_pretooluse_json 'git commit -m "feat: change"' "$FAIL_DIR")"
assert_deny "deny: tests fail" "tests failed"

# --amend inside a quoted commit message should NOT skip (not a real flag)
run_hook "$HOOK" "$(make_pretooluse_json 'git commit -m "mention --amend in message"' "$FAIL_DIR")"
assert_deny "deny: --amend inside quoted message is not real flag" "tests failed"

# --- Allow: tests pass ---

PASS_DIR=$(make_tmp_repo)
echo '{"scripts":{"test":"exit 0"}}' > "$PASS_DIR/package.json"
echo "export const y = 1;" > "$PASS_DIR/index.ts"
git -C "$PASS_DIR" add . && git -C "$PASS_DIR" commit -m "add pkg" --quiet 2>/dev/null
# Stage a .ts file change
echo "export const y = 2;" > "$PASS_DIR/index.ts"
git -C "$PASS_DIR" add .

run_hook "$HOOK" "$(make_pretooluse_json 'git commit -m "feat: update"' "$PASS_DIR")"
assert_allow "allow: tests pass"

# --- Chained commands with git commit ---

run_hook "$HOOK" "$(make_pretooluse_json 'git add . && git commit -m "test"' "$PASS_DIR")"
assert_allow "allow: chained git add && git commit (tests pass)"

# --- Git with global options should still be intercepted ---

run_hook "$HOOK" "$(make_pretooluse_json 'git -c user.name=Test commit -m "feat: x"' "$FAIL_DIR")"
assert_deny "deny: git -c option commit (tests fail)" "tests failed"

run_hook "$HOOK" "$(make_pretooluse_json 'git --no-pager commit -m "feat: x"' "$FAIL_DIR")"
assert_deny "deny: git --no-pager commit (tests fail)" "tests failed"

# --- Bare git commit (no flags) ---

run_hook "$HOOK" "$(make_pretooluse_json 'git commit' "$FAIL_DIR")"
assert_deny "deny: bare git commit (tests fail)" "tests failed"

run_hook "$HOOK" "$(make_pretooluse_json 'git commit' "$PASS_DIR")"
assert_allow "allow: bare git commit (tests pass)"

# --- Report ---

report
