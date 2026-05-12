---
name: session-close
description: "Pre-flight checklist before ending a session. Use when asked to 'check before ending', 'session close', 'pre-flight', 'wrap up', 'land the plane', or 'end session'. Runs quality gates and reports status."
---

# Session Close (`/check`)

Output "Read Session Close skill." to chat to acknowledge you read this file.

Pre-flight checklist that runs before ending a coding session. Catches common "forgot to..." failures mechanically instead of relying on the model to remember.

---

## When to invoke

- Before ending any session that produced code changes
- When the user says "wrap up", "land the plane", "end session", "check before ending"
- Automatically as part of the do-work pipeline after the final commit

---

## Checklist

Run each check in order. Report results as a table at the end.

### 1. Uncommitted changes

```bash
git status --porcelain
```

- **PASS**: empty output (clean working tree)
- **FAIL**: list the uncommitted files and ask user whether to commit or stash

### 2. Unpushed commits

```bash
git log --oneline @{u}..HEAD 2>/dev/null
```

- **PASS**: empty output (nothing unpushed)
- **FAIL**: list the commits and push them

### 3. PR exists for branch

```bash
BRANCH=$(git branch --show-current)
# Skip if on a base branch
if [[ "$BRANCH" =~ ^(main|master|dev|develop)$ ]]; then
  echo "SKIP: on base branch"
else
  gh pr list --head "$BRANCH" --state open --json number,url --jq '.[0]'
fi
```

- **PASS**: PR exists (show number + URL)
- **SKIP**: on a base branch
- **FAIL**: no PR — create one or remind user

### 4. Type check (if TypeScript project)

```bash
# Auto-detect
if [[ -f "tsconfig.json" ]]; then
  npx tsc --noEmit 2>&1 | tail -5
fi
```

- **PASS**: exit 0
- **SKIP**: no tsconfig.json
- **FAIL**: show errors, ask user whether to fix

### 5. Tests (if test runner detected)

Auto-detect from package.json, composer.json, Makefile, pyproject.toml:

```bash
if [[ -f "package.json" ]] && grep -q '"test"' package.json; then
  npm test 2>&1 | tail -20
fi
```

- **PASS**: exit 0
- **SKIP**: no test runner detected
- **FAIL**: show failures, ask user whether to fix

### 6. Lint / format (if detected)

```bash
if [[ -f "package.json" ]] && grep -q '"lint"' package.json; then
  npm run lint 2>&1 | tail -10
fi
```

- **PASS**: exit 0
- **SKIP**: no linter detected
- **FAIL**: show issues (non-blocking — report only)

### 7. Drift check

```bash
if [[ -f "$HOME/dotfiles/bin/drift-detect.sh" ]]; then
  bash "$HOME/dotfiles/bin/drift-detect.sh" 2>&1
fi
```

- **PASS**: no drift
- **SKIP**: drift-detect.sh not found
- **FAIL**: list drifted files (non-blocking — report only)

### 8. Stash check

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
2. Provide the pickup command for the next session
3. Follow the handoff protocol from `handoff.instructions.md`
