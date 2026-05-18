---
name: session-close
description: Pre-flight checklist that runs quality gates before ending a coding session.
---

# Session Close (`/check`)

Output "Read Session Close skill." to chat to acknowledge you read this file.

Pre-flight checklist that runs before ending a coding session. Catches common "forgot to..." failures mechanically instead of relying on the model to remember.

---

## When to invoke

- Before ending any session that produced code changes
- When the user says "wrap up", "land the plane", "end session", "check before ending"

---

## Checklist

Run each check in order. Report results as a table at the end.

### 1. Uncommitted changes

```bash
git status --porcelain
```

- **PASS**: empty output (clean working tree)
- **FAIL**: list the uncommitted files and ask user whether to commit or stash

### 2. Secrets accidentally staged

```bash
git diff --cached --name-only | grep -iE '\.env|secret|credential|password|token|apikey|api_key' || true
git diff --cached | grep -iE 'SECRET|PASSWORD|API_KEY|TOKEN|CREDENTIAL|PRIVATE_KEY' | head -5 || true
```

- **PASS**: no sensitive filenames staged, no credential-like patterns in diff content
- **FAIL**: list the matches and ask user to unstage (`git reset HEAD <file>`)

> **Caveat**: this is a shallow heuristic — it catches obvious key names but will miss
> vendor-prefixed secrets (`ANTHROPIC_API_KEY`, `STRIPE_SK_LIVE_...`), format-based
> tokens (`ghp_...`, `sk-...`), and raw secret values. Treat as a "better than nothing"
> gate, not a comprehensive scanner.

### 3. Unpushed commits

```bash
if git rev-parse --abbrev-ref '@{u}' &>/dev/null; then
  git log --oneline @{u}..HEAD 2>/dev/null
else
  echo "NO UPSTREAM"
fi
```

- **PASS**: empty output (nothing unpushed)
- **FAIL**: list the commits and ask user whether to push (user may be mid-rebase or on a WIP branch)
- **WARN**: no upstream configured — local commits may not be tracked

### 4. PR exists for branch (GitHub only)

```bash
BRANCH=$(git branch --show-current)
# Skip if on a base branch
# NOTE: if the project uses .ctrlshft protected_branches, keep this
# list in sync. The hook reads .ctrlshft; this skill does not (yet).
if [[ "$BRANCH" =~ ^(main|master|dev|develop)$ ]]; then
  echo "SKIP: on base branch"
elif ! command -v gh &>/dev/null; then
  echo "SKIP: gh CLI not installed"
else
  gh pr list --head "$BRANCH" --state open --json number,url --jq '.[0]'
fi
```

- **PASS**: PR exists (show number + URL)
- **SKIP**: on a base branch, or `gh` CLI not available
- **FAIL**: no PR — create one or remind user

### 5. Type check (if TypeScript project)

```bash
# Auto-detect
if [[ -f "tsconfig.json" ]]; then
  TSC_OUTPUT=$(npx tsc --noEmit 2>&1); TSC_EXIT=$?
  echo "$TSC_OUTPUT" | tail -5
  # Use $TSC_EXIT for pass/fail — piping to tail loses the original exit code
fi
```

- **PASS**: TSC_EXIT == 0
- **SKIP**: no tsconfig.json
- **FAIL**: show errors, ask user whether to fix

### 6. Tests (if test runner detected)

Auto-detect from package.json, composer.json, Makefile, pyproject.toml:

```bash
if [[ -f "package.json" ]] && grep -q '"test"' package.json; then
  # Timeout after 120s to avoid blocking on slow e2e suites
  # Use GNU timeout if available, fall back to running without timeout on macOS
  if command -v timeout &>/dev/null; then
    TEST_OUTPUT=$(timeout 120 npm test -- --passWithNoTests 2>&1) && TEST_EXIT=$? || TEST_EXIT=$?
  else
    TEST_OUTPUT=$(npm test -- --passWithNoTests 2>&1) && TEST_EXIT=$? || TEST_EXIT=$?
  fi
  echo "$TEST_OUTPUT" | tail -20
  # Use $TEST_EXIT for pass/fail (124 = timeout)
fi
```

- **PASS**: TEST_EXIT == 0
- **SKIP**: no test runner detected
- **FAIL**: show failures, ask user whether to fix
- **TIMEOUT**: TEST_EXIT == 124 — tests exceeded 120s, report as non-blocking warning

### 7. Lint / format (if detected)

```bash
if [[ -f "package.json" ]] && grep -q '"lint"' package.json; then
  LINT_OUTPUT=$(npm run lint 2>&1); LINT_EXIT=$?
  echo "$LINT_OUTPUT" | tail -10
  # Use $LINT_EXIT for pass/fail
fi
```

- **PASS**: LINT_EXIT == 0
- **SKIP**: no linter detected
- **FAIL**: show issues (non-blocking — report only)

### 8. Drift check

```bash
if [[ -f "$HOME/dotfiles/bin/drift-detect.sh" ]]; then
  bash "$HOME/dotfiles/bin/drift-detect.sh" 2>&1
fi
```

- **PASS**: no drift
- **SKIP**: drift-detect.sh not found
- **FAIL**: list drifted files (non-blocking — report only)

### 9. Stash check

```bash
STASH_COUNT=$(git stash list | wc -l)
```

- **PASS**: 0 stashes
- **WARN**: N stashes exist — remind user to review

---

## Report Format

After running all checks, output a summary table:

```
## Session Close Report

| Check | Result |
|-------|--------|
| Uncommitted changes | ✅ Clean |
| Secrets staged | ✅ Clean |
| Unpushed commits | ✅ Pushed |
| PR exists | ✅ #74 |
| Type check | ✅ Pass |
| Tests | ⏭️ Skipped |
| Lint | ✅ Pass |
| Drift check | ⚠️ 2 files drifted |
| Stashes | ✅ None |

**Overall: READY** (or **BLOCKED: N issues to resolve**)
```

Use these symbols:
- ✅ = pass
- ❌ = fail (blocking)
- ⚠️ = warn (non-blocking)
- ⏭️ = skipped (not applicable)

---

## Blocking vs Non-Blocking

**Blocking** (must resolve before ending):
- Uncommitted changes
- Secrets accidentally staged
- Unpushed commits

**Non-blocking** (report but don't force resolution):
- No PR
- Type errors
- Test failures
- Lint issues
- Drift
- Stashes

The user always has final say. If they say "end anyway", comply — but make sure they saw the report.

---

## Integration with Handoff

If the session is ending due to context pressure, after the report:

1. Write remaining work to `working/<topic>.md`
2. Provide the pickup command for the next session (e.g. `@working/<topic>.md --pickup <summary> --context <key points> --next-steps <specific tasks> --references <links> --files <list of relevant files> --tools <list of relevant tools> --status <current blockers or progress> --priority <high/medium/low> --skill <relevant skills>`)
3. Follow the handoff protocol from `handoff.instructions.md`
