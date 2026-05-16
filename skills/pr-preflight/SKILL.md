---
name: pr-preflight
description: Exhaustive pre-PR audit that front-runs code review tools by catching the same issues Copilot/reviewers find iteratively, across any stack.
---

# PR Preflight (`/preflight`)

Output "Read PR Preflight skill." to chat to acknowledge you read this file.

Run this before every PR open or update. The goal is a review where the automated reviewer finds nothing, because you found it first.

This skill is diff-aware: it knows what changed, audits those files completely (not just the diff lines), and looks for the same classes of issue that iterative review tools catch one-at-a-time.

---

## When to invoke

- Before `gh pr create` or before pushing a PR update
- When asked to "preflight", "pre-PR check", "prep for review"
- After fixing review comments, before re-requesting review

---

## Phase 1 — Understand the Change

Before anything else, map what this PR actually touches.

```bash
# What branch and base?
git branch --show-current
git log --oneline main..HEAD 2>/dev/null || git log --oneline HEAD~5..HEAD

# What files changed?
git diff --name-only main..HEAD 2>/dev/null || git diff --name-only HEAD~1..HEAD

# Full diff (for context)
git diff main..HEAD 2>/dev/null || git diff HEAD~1..HEAD
```

From this, answer:
- What is this PR trying to do? (1 sentence)
- Which files were added, modified, deleted?
- Which files were NOT changed but may be affected? (imports, callers, tests)

**Do not skip this step.** Every later phase uses this map.

---

## Phase 2 — Stack Detection and Tool Audit

Detect what's present and run the right tools. Do not run tools for stacks that aren't here.

```bash
# Detect stack
ls package.json tsconfig.json pyproject.toml Cargo.toml go.mod \
   Makefile *.sh hooks/ 2>/dev/null | sort

# Node / TypeScript / React
if [[ -f package.json ]]; then
  echo "=== TypeScript ===" && npx tsc --noEmit 2>&1; tsc_exit=$?; echo "(exit $tsc_exit)" | tail -20
  echo "=== Lint ===" && npm run lint 2>&1; lint_exit=$?; echo "(exit $lint_exit)" | tail -20
  echo "=== Tests ===" && npm test -- --passWithNoTests 2>&1; test_exit=$?; echo "(exit $test_exit)" | tail -30
fi

# Bash
if find . -name '*.sh' -not -path '*/.git/*' | grep -q .; then
  command -v shellcheck &>/dev/null && \
    find . -name '*.sh' -not -path '*/.git/*' | \
    xargs shellcheck --severity=warning 2>&1 || \
    echo "SKIP: shellcheck not installed"
fi

# Python
if [[ -f pyproject.toml ]] || find . -name '*.py' -not -path '*/.git/*' | grep -q .; then
  command -v ruff &>/dev/null && ruff check . 2>&1 | tail -20 || true
  command -v mypy &>/dev/null && mypy . 2>&1 | tail -20 || true
fi
```

**Every tool failure is blocking.** Do not proceed past Phase 2 with red type errors, failing tests, or shellcheck errors. Fix those first — reviewers will find them and they create noise that hides real feedback.

---

## Phase 3 — Full-File Audit of Changed Files

This is the phase that replaces iterative review cycles.

For each file that changed (from Phase 1), read the **entire file** — not just the diff. Reviewers see the whole file. You need to see what they see.

Apply the full codebase-audit categories to each changed file:

### Security & Bypass Gaps
- Any new pattern-matching logic (regex, grep, guards): run the bypass matrix
  - Does it handle `sudo -E`, `env -i`, `--ignore-environment`?
  - Does it handle chained commands (`;`, `&&`, `||`)?
  - Does it false-positive on quoted/echoed forms?
- Any new credential handling: is it logged, printed, or passed in a way that exposes it?
- Any new input that touches the filesystem: path traversal possible?
- Any new network call: authenticated? timeout bounded?

### Logic Errors
- Does the new code do what the PR description says it does?
- Are there off-by-one errors, wrong comparison operators, inverted conditions?
- Are error paths handled or silently swallowed?

### Consistency with the rest of the file
- Does the new code use the same patterns as the existing code in that file?
- If the file defines a shared variable/constant for a pattern, does the new code use it — or inline its own copy?
- If the file has an established error-handling style, does the new code match it?

### Consistency with other changed files
- If the same pattern appears in multiple changed files, are they identical?
- If a shared utility was modified, do all callers still work?
- If a config was changed, do all files that read it handle the new shape?

### Dead and unreachable code
- Any new function that is never called?
- Any new import that is never used?
- Any branch that can never be reached given the surrounding conditions?

### Test coverage
- Is there a test for the new behavior?
- Is there a test for the error/failure path?
- If a guard or policy was added: is the bypass case tested (not just the happy path)?

---

## Phase 4 — Diff-Specific Review

Now look at only what changed, with fresh eyes.

```bash
git diff main..HEAD 2>/dev/null || git diff HEAD~1..HEAD
```

For each hunk in the diff:

**Does the change make sense in isolation?**
Read each `+` line. Could a reviewer misunderstand what it does? If yes, it needs a comment — not because comments are required, but because confusion causes review threads.

**Are there leftover artifacts?**
- Debug `console.log`, `echo`, `print` statements
- TODO/FIXME comments that should have been resolved
- Commented-out code that should be deleted
- Hardcoded values that should be constants or config

**Are there missing pieces?**
- A function added but no tests?
- A new config key added but not documented in any README or schema?
- A hook added but not registered in `settings.json`?
- A new error condition handled but not covered in the error reporting?

**Naming and clarity**
- Does the variable/function name accurately describe what it does?
- Would a reviewer need to ask what a name means?

---

## Phase 5 — Reviewer Simulation

Read the PR as if you are the reviewer seeing it for the first time. Ask exactly the questions a good reviewer would ask.

For **every changed file**, ask:

1. "What is this file supposed to do, and does this change help it do that?"
2. "Is there a simpler way to accomplish the same thing?"
3. "What happens when this fails or receives unexpected input?"
4. "Is this consistent with how similar things are done elsewhere in the codebase?"
5. "If I were on-call and this broke at 2am, would I be able to understand it?"

For **the PR as a whole**, ask:

1. "Does this PR do exactly one thing, or has scope crept in?"
2. "Is there anything in here that should be a separate PR?"
3. "What would make me ask for changes — and is that thing present?"

If you find yourself answering any of these with "well, it depends" or "kind of" — that's a finding.

---

## Phase 6 — Pre-Push Checklist

Run the mechanical checks that are easy to miss.

```bash
# No uncommitted changes sneaking in
git status --porcelain

# No accidentally staged secrets
git diff --cached | grep -iE 'SECRET|PASSWORD|API_KEY|TOKEN|PRIVATE_KEY' | head -5 || true
git diff HEAD | grep -iE 'SECRET|PASSWORD|API_KEY|TOKEN|PRIVATE_KEY' | head -5 || true

# Branch is up to date with base
git fetch origin main 2>/dev/null || true
git log --oneline HEAD..origin/main 2>/dev/null | head -5

# Commit messages are clean
git log --oneline main..HEAD 2>/dev/null || git log --oneline HEAD~5..HEAD
```

---

## Report Format

```
## PR Preflight Report — <branch name>

**Change summary**: <1 sentence>
**Files changed**: N
**Stack**: React/TS | Bash | Python | Mixed

### Phase 2 — Tool Results
| Tool | Result |
|------|--------|
| TypeScript | ✅ No errors |
| ESLint | ✅ No warnings |
| Tests | ✅ 42 passed |
| ShellCheck | ⚠️ 1 warning (non-blocking) |

### Phase 3 — Full-File Issues
<findings in codebase-audit format: [file:line] description>

### Phase 4 — Diff Issues
<findings: debug statements, missing pieces, naming>

### Phase 5 — Reviewer Simulation
<questions a reviewer would ask, with answers>

### Phase 6 — Pre-Push
| Check | Result |
|-------|--------|
| Clean working tree | ✅ |
| No staged secrets | ✅ |
| Up to date with main | ✅ |
| Commit messages | ✅ conventional |

**READY FOR REVIEW** (or **BLOCKED: fix N issues first**)
```

---

## The Rule

**Never request a review without running this first.**

The iterative review cycle (fix → push → review → fix → push → review) happens because review is being used as a quality gate. It is not a quality gate — it is a second opinion. Your quality gate is this preflight.

If this finds nothing and the tool checks pass, Copilot will find nothing either. If Copilot still finds something after a clean preflight, add that finding to Phase 3 or 4 so it gets caught next time.
