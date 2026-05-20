---
name: session-close
description: Pre-flight checklist that runs quality gates before ending a coding session.
---

# Session Close (`/check`)

Output "Read Session Close skill." to chat to acknowledge you read this file.

Audit this session before we close it. Answer with evidence, not assertions.

The first job is to **scope this audit to this session only**. Items from other sessions, future tracker-tracked work, or out-of-scope user tasks must NOT block close.

---

## When to invoke

- Before ending any session that produced code changes
- When the user says "wrap up", "land the plane", "end session", "check before ending"

---

## 0. Session Manifest (derive scope FIRST, before any audit)

Before running sections 1–5 below, derive what is in-session. Anything outside this manifest is out-of-session and NEVER blocks close — it lands in Section B at most.

Build the manifest from chat-context (this conversation), not git alone:

- **PRs opened this session** — every `gh pr create` you ran (track from your tool calls)
- **Commits authored this session** — `git log --author="$(git config user.email)" --since=4h`
- **Issues filed this session** — every issue tracker create call (capture the IDs from the responses)
- **Memory / context files touched this session** — `git log --since=4h -- <memory-dir>/` filtered to your commits
- **Files edited this session** — your Edit/Write tool calls in this conversation

Render as a one-line summary at the top of the audit: `Session manifest: N PRs, M commits, K tickets (...), J memory files, I files edited.`

If the manifest is empty (purely a read-only / chat session with no writes), Section A is empty by definition; skip directly to ✅ Ready.

---

## 1–5. Quality Checks (with section emoji)

**Per-section status emoji — reflects Section A items only.** A section with only Section B context is ✅. Prefix each section heading with one of:
- ✅ clean / nothing in-session needed / all in-session done
- ⚠️ attention — in-session ambiguity you can't resolve (genuinely blocked by user)
- ❌ blocker — in-session unfinished work, uncommitted in-scope edits, in-scope errors

### 1. Changes landed

```bash
git status --porcelain
git log --oneline @{u}.. 2>/dev/null || git log --oneline -5
```

Check: Are all in-session changes committed? Any stray uncommitted in-scope edits? Anything staged/unpushed that should be?

### 2. Secrets check

```bash
git diff --cached --name-only | grep -iE '\.env|secret|credential|password|token|apikey|api_key' || true
git diff --cached | grep -iE 'SECRET|PASSWORD|API_KEY|TOKEN|CREDENTIAL|PRIVATE_KEY' | head -5 || true
```

Check: No sensitive filenames staged, no credential-like patterns in diff content.

> **Caveat**: shallow heuristic — catches obvious key names but will miss vendor-prefixed secrets, format-based tokens, or raw secret values.

### 3. PR exists (GitHub only)

```bash
BRANCH=$(git branch --show-current)
if [[ "$BRANCH" =~ ^(main|master|dev|develop)$ ]]; then
  echo "SKIP: on base branch"
elif ! command -v gh &>/dev/null; then
  echo "SKIP: gh CLI not installed"
else
  gh pr list --head "$BRANCH" --state open --json number,url --jq '.[0]'
fi
```

### 4. Quality gates

Run each if detected. Report pass/fail/skip per gate.

```bash
# Type check (TypeScript)
if [[ -f "tsconfig.json" ]]; then
  TSC_OUTPUT=$(npx tsc --noEmit 2>&1); TSC_EXIT=$?
  echo "$TSC_OUTPUT" | tail -5
fi

# Tests
if [[ -f "package.json" ]] && grep -q '"test"' package.json; then
  if command -v timeout &>/dev/null; then
    TEST_OUTPUT=$(timeout 120 npm test -- --passWithNoTests 2>&1) && TEST_EXIT=$? || TEST_EXIT=$?
  else
    TEST_OUTPUT=$(npm test -- --passWithNoTests 2>&1) && TEST_EXIT=$? || TEST_EXIT=$?
  fi
  echo "$TEST_OUTPUT" | tail -20
fi

# Lint
if [[ -f "package.json" ]] && grep -q '"lint"' package.json; then
  LINT_OUTPUT=$(npm run lint 2>&1); LINT_EXIT=$?
  echo "$LINT_OUTPUT" | tail -10
fi
```

### 5. Session hygiene

```bash
# Drift check
if [[ -f "$HOME/dotfiles/bin/drift-detect.sh" ]]; then
  bash "$HOME/dotfiles/bin/drift-detect.sh" 2>&1
fi

# Stash check
STASH_COUNT=$(git stash list | wc -l)

# Learnings — were any non-obvious decisions, gotchas, or insights surfaced?
# If yes, are they captured durably (memory, CLAUDE.md, commit message, doc)?

# Docs — did code/schema/workflow changes need doc updates?
```

---

## 📋 Open Items — TWO sections

**Critical:** every ⚠️ or ❌ from sections 1–5 MUST appear in the right table below. Items don't get to hide in prose.

### Section A — In-session items (blocks close if any row is `tackle now`)

Items mapped to the Session Manifest. These are work this session originated, owns, or must complete.

| # | Item | Status | Action this turn | Owner |
|---|------|--------|------------------|-------|
| 1 | [one-line description] | `done` / `deferred (ticket-ID)` / `tackle now` / `blocked by user` | `none` / specific verb / `none — tracker tracks it` | `Claude` / `<user>` / `external` |

If empty, write: `None — no in-session items.`

**Status definitions:**
- `done` — completed in this session, no follow-up needed
- `deferred (ticket-ID)` — explicitly handed to a tracker ticket for a future session
- `tackle now` — must be resolved this turn. Blocks ✅.
- `blocked by user` — needs a destructive/external/ambiguous decision only the user can make

#### Pre-render: validate PR-merge dependencies

If a Section A row's blocker is a PR merge (text mentions "after PR #N merges" or similar), check the PR's state before rendering:

1. Run `gh pr view <num> --json state,mergedAt` once per referenced PR.
2. If ALL referenced PRs are `MERGED` — dependency is gone, row flips to `tackle now`. Execute the dependent action in the same turn.
3. If ANY referenced PR is `OPEN` or `CLOSED` — dependency holds, row stays `blocked by user`.

### Section B — Adjacent context (NEVER blocks close, informational only)

Items mentioned this session but NOT in the manifest: other sessions' commits, future user tasks, pre-existing tracker tickets, repos/branches you only read.

| # | Item | Why it's not in-session | Action this session |
|---|------|--------------------------|---------------------|
| 1 | [one-line description] | concurrent session / user's task / pre-existing ticket / read-only | `none` |

If empty, write: `None — no adjacent context surfaced.`

`Action this session` is **always `none`** for Section B. If it ever isn't, the row belongs in Section A.

### Proposed actions (Section A only)

For each Section A row that isn't `done`, `deferred`, or `blocked by user`, state in one line what you're about to do and **execute it in the same turn** — don't ask permission for reversible work.

---

## Idempotency rule

If `/check` is re-run later in the same session, items previously marked `deferred (ticket-ID)` and not subsequently touched are **not re-listed**. Once filed and explicitly deferred, they're done from this session's perspective.

---

## Final verdict

Verdict is driven by **Section A only**. Section B never affects the verdict.

- ✅ **Ready to close** — Section A is empty OR every row is `done` or `deferred (ticket-ID)`. Brief summary of what shipped this session.
- ❌ **Not ready** — Section A has at least one `tackle now` row. List those rows + recommended next action for each.
- ⚠️ **Close with caveats** — Section A has a `blocked by user` row (genuine, named ambiguity). NOT for tracker-deferred work. NOT for adjacent context.

Be direct. If something was skipped, say so. The verdict is authoritative — re-running `/check` for the same state produces the same verdict.

---

## Integration with Handoff

If the session is ending due to context pressure, after the report:

1. Write remaining work to `working/<topic>.md`
2. Provide the pickup command for the next session
3. Follow the handoff protocol from `handoff.instructions.md`
