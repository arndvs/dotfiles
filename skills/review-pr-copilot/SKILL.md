---
name: review-pr-copilot
description: "Address GitHub Copilot review comments on the active PR by triaging into confidence tiers, fixing in atomic commits, resolving threads, and re-requesting review."
---

# Review PR — Copilot

Output "Read Review PR Copilot skill." to chat to acknowledge you read this file.

## When to use

Use whenever Copilot has left review comments on a pull request and the user wants to address them. Trigger phrases: "fix the PR comments", "address Copilot review", "clean up review feedback", "fix Copilot's comments", "address PR feedback", "re-request review". Also trigger proactively when the active PR has unresolved Copilot review threads and the user asks to commit or ship.

This skill is a **thin orchestrator**. It does not reimplement comment fetching or commit logic — those live in:

- VS Code's built-in `address-pr-comments` skill — fetches and applies fixes
- The `atomic-commits` skill — branch hygiene, conventional commits, ship mode
- The GitHub MCP — `mcp_github_pull_request_read`, `mcp_github_resolveReviewThread`, `mcp_github_request_copilot_review`

If any of those are unavailable, fall back to the inline steps below.

---

## Workflow

### 1. Identify the PR + Copilot reviewer

Use `github-pull-request_currentActivePullRequest` to detect the active PR. If none, ask the user for `owner/repo#number`.

Fetch reviews via `mcp_github_pull_request_read` (method `getReviews`) and isolate Copilot:
- `user.type == "Bot"` AND `user.login` matches `copilot-pull-request-reviewer[bot]` or contains `copilot`

Fetch inline comments and filter to that user. Skip threads where `isResolved == true` or `outdated == true`.

### 2. Score each comment + triage

Score every comment 0–100 using observable signals, not vibes:

**Positive signals** (add):
- `+20` Comment is specific — cites exact line and exact change
- `+25` Fix is mechanical — rename, add guard, add type, fix typo, add missing await
- `+15` Touches ≤1 file and ≤10 lines
- `+15` Touched code has test coverage
- `+10` No public API / exported type signature change
- `+15` Copilot quoted the existing code or proposed a concrete replacement

**Negative signals** (subtract):
- `-20` Touches a shared util, type, schema, or hook used in 3+ places
- `-25` Vague language: "consider", "might want to", "could", "perhaps", "in some cases"
- `-15` Cross-file or cross-module change
- `-20` Modifies test assertions or fixtures (risk: masking the bug)
- `-15` Changes error-handling semantics (swallow ↔ throw, sync ↔ async)
- `-10` File changed since the comment was posted (stale context)

Start at 50, apply signals, clamp 0–100.

**Tiers + policy:**

| Tier | Score | Action |
|---|---|---|
| **Auto** | ≥ 75 | Fix, commit, resolve thread — no prompt. Reported in final summary. |
| **Confirm** | 40–74 | Show diff preview + one-line approval prompt per comment before commit. |
| **HITL** | < 40 | **Do not fix.** Post a reply on the thread with your interpretation and a proposed approach as a question. Leave the thread open. |

Print the triage table before any action:

```
PR #<N> — <X> open Copilot comments

  Auto    (≥75):
    1. src/auth/token.ts:42      [88]  add null guard on user
    2. src/api/fetch.ts:17       [82]  fix typo in error message
  Confirm (40–74):
    3. src/utils/parse.ts:103    [62]  extract repeated regex
  HITL    (<40):
    4. src/store/index.ts:1      [28]  "consider refactoring this module"
```

User can override the policy for the session: "auto everything", "confirm everything", "be conservative" (raise thresholds), or list specific comment numbers to re-tier.

### 3. Plan slices

Group **Auto + Confirm** comments into atomic slices (one logical fix per commit). HITL comments are excluded from slicing — they get thread replies instead. Surface the plan as a table:

| Slice | Files | Commit message |
|---|---|---|
| 1 | `src/auth/token.ts` | `fix(auth): handle null user in token refresh` |
| 2 | `src/api/*.ts` | `fix(api): propagate errors instead of swallowing` |

**Approval gates per tier** (no global gate — the triage table in step 2 is the only session-wide checkpoint):
- **Auto slices** — proceed immediately after printing the plan
- **Confirm slices** — show diff preview and prompt for one-line approval *per comment* before the commit
- **HITL** — never reach this step

### 4. Apply + commit each slice

For each slice:

1. Read affected files (±30 lines context minimum)
2. Apply the fix — **only what Copilot flagged**. Note unrelated issues separately; do not include in these commits
3. Run quality gates if the project defines them (typecheck, lint, tests for touched files)
4. Hand off to the **atomic-commits** skill (Commit mode) — it owns branch + message format

Commit body format:

```
<type>(<scope>): <description>

Addresses Copilot review on PR #<N>:
- <file>:<line> — "<short quote of the comment>"
```

### 5. Resolve threads

After each commit pushes, resolve the corresponding Copilot threads via `mcp_github_resolveReviewThread` — **only for Auto and Confirm tier fixes that fully addressed the comment**.

If a fix only partially addresses a thread, leave it open and note it in the final summary.

### 5b. Reply to HITL comments

For every HITL-tier comment, post a reply on the thread via `mcp_github_add_reply_to_pull_request_comment` with this shape:

```
Flagging for human review (confidence: <score>).

My interpretation: <one sentence>

Proposed approach: <2–3 bullets>

Blockers / questions:
- <what makes this ambiguous>
- <what I'd need to know to proceed>

Reply with guidance and I'll address in a follow-up commit.
```

Do **not** resolve the thread. Do **not** commit a speculative fix.

### 6. Push + re-request review

After the final slice, hand off to **atomic-commits** (Ship mode) for rebase + push.

Then call `mcp_github_request_copilot_review` on the PR. If it fails, surface the PR URL so the user can re-request manually.

### 7. Summary report

```
PR #<N> — Copilot review addressed

Triage:            Auto <X>  |  Confirm <Y>  |  HITL <Z>
Comments fixed:    <X+Y> / <total>
HITL replies:      <Z>
Commits:           <N>
Threads resolved:  <X+Y>
Review re-requested: yes | manual

Commits:
  <sha[:7]>  <message>
  ...

Awaiting human (HITL):
  - #<comment-id> <file>:<line> — <one-line summary>  [confidence: <score>]
  ...

Skipped / deferred:
  - <comment summary> — <reason>
```

---

## Edge cases

- **No Copilot review found** — say so, offer to address all reviewer comments instead (defer to `address-pr-comments`)
- **Comment on deleted/renamed file** — surface to user, don't guess
- **Vague comment** ("consider refactoring") — the `-25` vague-language signal will normally drop these into HITL; reply on the thread per step 5b. Only fix if the user explicitly re-tiers it to Auto/Confirm with a concrete approach.
- **Stale comment** (file changed since) — re-read current file, rebase the fix mentally, flag if the comment no longer applies
- **MCP tool naming differs** — use `tool_search` to find the actual GitHub MCP tools available; common variants: `get_pull_request`, `pull_request_read`, `mcp_github_pull_request_read`

---

## Guardrails

- Never fix things Copilot didn't flag in the same commits — file a follow-up note instead
- Never force-push without confirmation
- Never auto-resolve a thread you didn't fully address
- Stop and ask if a fix would break public API, change types broadly, or modify test assertions
