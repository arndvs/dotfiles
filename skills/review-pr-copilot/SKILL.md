---
name: review-pr-copilot
description: "Address GitHub Copilot review comments on the active PR by triaging into confidence tiers, fixing in atomic commits, resolving threads, and re-requesting review."
---

# Review PR — Copilot

Output "Read Review PR Copilot skill." to chat to acknowledge you read this file.

## When to use

Use whenever Copilot has left review comments on a pull request and the user wants to address them. Trigger phrases: "fix the PR comments", "address Copilot review", "clean up review feedback", "fix Copilot's comments", "address PR feedback", "re-request review". Also trigger proactively when the active PR has unresolved Copilot review threads and the user asks to commit or ship.

This skill is a **thin orchestrator**. It does not reimplement comment fetching or commit logic — those live in:

- The `atomic-commits` skill — branch hygiene, conventional commits, ship mode
- The GitHub MCP — `mcp_github_pull_request_read`, `mcp_github_add_reply_to_pull_request_comment`, `mcp_github_add_issue_comment`, `mcp_github_pull_request_review_write` (method `resolve_thread`), `mcp_github_request_copilot_review`
- The VS Code GitHub PR extension — `github-pull-request_currentActivePullRequest` (required for thread node IDs)

These are **hard dependencies**, with one nuance:

- **GitHub MCP** is required. If unavailable, surface that to the user and stop.
- **VS Code PR extension** is required for **full-fidelity execution** (specifically, thread node IDs needed by step 5's `resolve_thread`). If unavailable, the skill may run in **degraded mode** via raw MCP after the user supplies `owner/repo#number`, but it must warn the user that thread resolution will not happen — only acknowledgment replies.

Do not attempt to substitute raw `gh` CLI calls or git plumbing; the resolve-thread and request-review flows use GraphQL node IDs that are not exposed by the CLI.

---

## Workflow

### 0. Pre-flight checks

All three checks below are PR-scoped, so begin step 0 by fetching the PR context: call `github-pull-request_currentActivePullRequest` (or, in degraded mode, prompt the user for `owner/repo#number` and use `mcp_github_pull_request_read`). Once you have a PR number, verify the run is worth starting:

- **Round counter** — track Copilot review rounds in this skill's session state, keyed by PR number. Default cap: **3 rounds per PR**. After round 3, stop and surface to the user — further rounds usually mean subjective comments that need a human to break the tie.
- **CI status** — call `mcp_github_pull_request_read` (method `get_status_checks`) on the PR, or read `currentActivePullRequest.statusCheckRollup`. If checks are failing, ask the user before proceeding — fixing review nits while CI is red wastes a re-review cycle.
- **Pending review** — inspect the PR's reviews; if Copilot has a review in `PENDING` state (not yet submitted), stop. Re-running this skill will produce no comments and waste a `request_copilot_review` call.

If any check fails, surface the reason and ask before continuing. Step 1 then completes the rest of PR identification (filtering reviews to Copilot, building the `commentId → threadId` map).

### 1. Identify the PR + Copilot reviewer

Use `github-pull-request_currentActivePullRequest` (PR extension, not raw MCP) to detect the active PR — **this tool returns thread node IDs in `reviewThreads[].id`** which are required for resolving threads in step 5. The raw MCP `pull_request_read` with `get_review_comments` returns comment metadata but not GraphQL thread IDs.

If `currentActivePullRequest` is unavailable or returns no PR, ask the user for `owner/repo#number`, then fall back to `mcp_github_pull_request_read` (method `get_review_comments`) — but warn the user that step 5 will only post acknowledgments and cannot programmatically resolve threads in this mode.

Filter reviews to Copilot:
- Primary: `user.type == "Bot"` — canonical signal
- Secondary: `user.login` matches one of `copilot-pull-request-reviewer[bot]`, `copilot-swe-agent`, `github-copilot[bot]`, or contains `copilot`
- The login varies by Copilot variant (review bot, SWE agent, future variants); rely on `user.type == "Bot"` first and the login pattern only to disambiguate from other bots

Skip threads where `isResolved == true` or `isOutdated == true`. **Build a map of `commentId → threadId`** from the response so step 5 can resolve the right thread per fix.

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

**Show your work.** For every comment, print the signal arithmetic before the score — never just declare a number. List every applicable signal you considered; if no signals apply on one side, say so explicitly (e.g. `no negative signals applied`). If you cannot explain the arithmetic at all, you are vibing; stop and re-read the comment. Do not invent signals just to show one on each side.

Print the triage table before any action, with the math visible:

```
PR #<N> — <X> open Copilot comments

  Auto    (≥75):
    1. src/auth/token.ts:42      [50 +25 mechanical +20 specific +15 ≤10 lines −10 stale = 100]  add null guard on user
    2. src/api/fetch.ts:17       [50 +25 mechanical +20 specific +15 ≤10 lines = 100 → clamped]  fix typo in error message
  Confirm (40–74):
    3. src/utils/parse.ts:103    [50 +20 specific −10 stale +15 ≤10 lines −15 cross-file = 60]  extract repeated regex
  HITL    (<40):
    4. src/store/index.ts:1      [50 −25 vague −20 shared util = 5 → clamped]  "consider refactoring this module"
```

**Failure mode caught in dogfooding (PR #68):** every comment reported as "100" with no arithmetic. If your output looks like that, the scoring step was skipped — restart from this section.

User can override the policy for the session: "auto everything", "confirm everything", "be conservative" (raise thresholds), or list specific comment numbers to re-tier.

### 3. Plan slices

Group **Auto + Confirm** comments into atomic slices. HITL comments are excluded from slicing — they get thread replies instead.

**Slicing rule** (resolves the atomic-vs-bundle question dogfood surfaced):

- **Multi-file PR** — one slice per file or per logical scope (e.g. `src/auth/*`). One commit per slice.
- **Single-file PR** — bundle by *intent*, not per-comment. If 3 Copilot comments all touch `SKILL.md` and all correct factual errors → one commit. If they touch different concerns (one fixes a typo, one rewrites a section) → split.
- **Never split a single Copilot comment across commits.** A comment is the smallest atomic unit.

Surface the plan as a table:

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

### 5. Acknowledge + resolve threads

After each commit is pushed, for every Copilot thread fully addressed by an Auto or Confirm fix:

1. **Post an acknowledgment reply** via `mcp_github_add_reply_to_pull_request_comment` with this shape:

   ```
   Fixed in <sha[:7]>: <one-line summary of the change>.
   ```

   This leaves a paper trail in the thread before it closes — reviewers (human or bot) can see what was done without diffing against the PR.

2. **Resolve the thread** via `mcp_github_pull_request_review_write` (method `resolve_thread`, `threadId` from step 1).

If a fix only partially addresses a thread, post the acknowledgment but **do not resolve** — leave the thread open and note it in the final summary.

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

Post the summary in two places: chat (for the user) **and** as a top-level PR comment via `mcp_github_add_issue_comment` (for the next reviewer — human or bot — who lacks chat history). Use the same block in both:

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

Skip the PR comment if `X+Y == 0` (nothing changed) — leaves no noise.

---

## Edge cases

- **No Copilot review found** — say so, ask the user whether to address human reviewer comments (this skill is Copilot-scoped; for general review handling use VS Code's built-in `address-pr-comments` separately)
- **Comment on deleted/renamed file** — surface to user, don't guess
- **Vague comment** ("consider refactoring") — the `-25` vague-language signal will normally drop these into HITL; reply on the thread per step 5b. Only fix if the user explicitly re-tiers it to Auto/Confirm with a concrete approach.
- **Stale comment** (file changed since) — re-read current file, rebase the fix mentally, flag if the comment no longer applies
- **MCP tool naming differs** — use `tool_search` to find the actual GitHub MCP tools available; common variants: `get_pull_request`, `pull_request_read`, `mcp_github_pull_request_read`
- **"Outdated" ≠ "Resolved" in the GitHub UI** — when your fix changes the line a comment was anchored to, GitHub labels the thread `Outdated` in the conversation tab and collapses it. This is independent of resolution. A thread can be both Outdated *and* Resolved; the UI only surfaces "Outdated". Verify resolution via `currentActivePullRequest` `reviewThreads[].isResolved`, or expand the thread in the **Files changed** tab to see the green ✅ Resolved badge. If a user reports "the threads aren't resolved", check the data, not the conversation tab.

---

## Guardrails

- Never fix things Copilot didn't flag in the same commits — file a follow-up note instead
- Never force-push without confirmation
- Never auto-resolve a thread you didn't fully address
- Stop and ask if a fix would break public API, change types broadly, or modify test assertions

## Escape hatch — skill bug discovered mid-flow

If you notice this skill itself is wrong while running it (e.g. a tool name is stale, a step is contradictory, an MCP returns unexpected shape):

1. **Stop.** Do not bundle the skill fix into a Copilot-comment commit — this violates the "only what Copilot flagged" guardrail above.
2. Surface the bug in chat with a one-line summary and the failure mode you hit.
3. Ask the user whether to (a) finish the current Copilot round first then patch the skill, or (b) patch the skill now in a separate commit and resume.
4. Whichever path the user picks, the skill fix lands in its own commit with `fix(skills):` scope and references the dogfood failure.

**Failure mode caught in dogfooding (PR #68):** mid-round, the agent identified two skill bugs (wrong tool name, missing acknowledgment step) and shipped them as slices 3 and 4 of a Copilot-comment series, polluting the commit history and bypassing the guardrail.
