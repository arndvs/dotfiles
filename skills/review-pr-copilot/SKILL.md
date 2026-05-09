---
name: review-pr-copilot
description: "Address GitHub Copilot review comments on the active PR by triaging into confidence tiers, fixing in atomic commits, resolving threads, and re-requesting review."
---

# Review PR — Copilot

Output "Read Review PR Copilot skill." to chat to acknowledge you read this file.

## When to use

Use whenever Copilot has left review comments on a pull request and the user wants to address them. Trigger phrases: "address the review comments", "address review", "address copilot review", "fix the PR comments", "clean up review feedback", "address PR feedback", "re-request review", "do another round", "round N". Also trigger proactively when the active PR has unresolved Copilot review threads and the user asks to commit or ship.

**Never ask the user to paste comment bodies into chat.** Fetch them yourself per step 1 — that's the whole point of the skill. The only thing you may ask the user for is `owner/repo#number` if no active PR is detected.

This skill is a **thin orchestrator**. It does not reimplement comment fetching or commit logic — those live in:

- The `atomic-commits` skill — branch hygiene, conventional commits, ship mode
- The GitHub MCP — `mcp_github_pull_request_read`, `mcp_github_add_reply_to_pull_request_comment`, `mcp_github_add_issue_comment`, `mcp_github_pull_request_review_write` (method `resolve_thread`), `mcp_github_request_copilot_review`, `mcp_github_issue_write` (method `create_issue`, used by the HITL-deferrable flow in step 5b). Any of these may be deferred and require `tool_search` to load — see the tool-discovery contract in step 5b before calling.
- The VS Code GitHub PR extension — `github-pull-request_currentActivePullRequest` (required for thread node IDs)

These are **hard dependencies**, with one nuance:

- **GitHub MCP** is required. If unavailable, surface that to the user and stop.
- **VS Code PR extension** is required for **full-fidelity execution** (specifically, thread node IDs needed by step 5's `resolve_thread`). If unavailable, the skill may run in **degraded mode** via raw MCP after the user supplies `owner/repo#number`, but it must warn the user that thread resolution will not happen — only acknowledgment replies.

Do not attempt to substitute raw `gh` CLI calls or git plumbing; the resolve-thread and request-review flows use GraphQL node IDs that are not exposed by the CLI.

---

## Workflow

### 0. Pre-flight checks

All checks below are PR-scoped, so begin step 0 by fetching the PR context: call `github-pull-request_currentActivePullRequest` (or, in degraded mode, prompt the user for `owner/repo#number` and use `mcp_github_pull_request_read`). Once you have a PR number, verify the run is worth starting:

- **Round counter** — track Copilot review rounds in this skill's session state, keyed by PR number. Default cap: **3 rounds per PR**. After round 3, stop and surface to the user — further rounds usually mean subjective comments that need a human to break the tie.
- **Round-cap override contract** — if the user explicitly authorizes continuing past the cap (e.g. "do another round", "keep going"), record the override on that round and **every subsequent round's pre-flight line must include `(cap=<cap> overridden by user on round <R_override>)`** (where `<cap>` is the current cap value, e.g. `3`, and `<R_override>` is the round number when the user authorized the override). This makes it auditable from the PR comment thread that the cap was exceeded by consent, not by drift. PR #50 dogfooded this — round 5 posted only a bare round count with no override marker, so a reviewer landing on the PR could not tell whether the cap had been breached or whether the cap simply didn't exist.
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
| **HITL** | < 40 | **Do not fix in this PR.** Tier into HITL-deferrable (file an issue, resolve thread) or HITL-blocking (leave open) per step 5b. |

**HITL is for subjective fixes, not large ones.** The tier is decided by *ambiguity*, not by *effort*:

- ✅ HITL: "consider refactoring this module" (no concrete target — ambiguous)
- ✅ HITL: "rethink the error model here" (taste call — ambiguous)
- ❌ HITL: "add tests for this new adapter" — that's **Confirm-tier**, deferrable to a follow-up issue but the approach is clear
- ❌ HITL: "rename `foo` to `bar` across 5 files" — that's **Confirm-tier**, large but mechanical
- ❌ HITL: "extract this into a shared util" with a named target — **Confirm-tier**, scope is defined

If a comment has a clear approach but you don't want to do it now, the answer is the **HITL-deferrable** flow in step 5b (file an issue). Do not push it into HITL-blocking just to skip the work.

**Forced-Confirm keywords.** If the comment uses any of the following, the floor is **Confirm tier** regardless of arithmetic — these signal a behavior or contract change that needs explicit approval before committing, even if the change *looks* mechanical:

- `refactor:` / "refactor this"
- "align" / "normalize" / "standardize" (across files)
- "semantics" / "behavior" / "contract"
- "signature" / "return type" / "parameter type" change
- "error semantics" / "error model" / "throw" → "return" or vice versa
- "rename" of an exported symbol or public API

PR #50 commit `c6c4bed` autofixed an "align error semantics" ask without a Confirm prompt — it was a behavior change masked as a refactor. Auto tier was wrong; the keyword should have forced Confirm.

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

### 5b. HITL comments — file an issue, don't strand the thread

HITL has two sub-tiers. Pick one before replying:

- **HITL-deferrable** — the comment scores < 40 due to ambiguity signals, but after analysis you can articulate a concrete approach (e.g. "rethink error boundaries" → you identify 3 specific catch blocks to restructure; "consider a caching layer" → you can name the exact module and strategy). File a GitHub issue, post a "filed as #N" reply, **resolve the thread**.
- **HITL-blocking** — the *approach* itself is ambiguous and needs human judgment to even define (e.g. "consider refactoring this module" with no concrete target). Post the legacy reply, **leave the thread open**.

If you're tempted to call something HITL-deferrable just because it would be a lot of work, re-read step 2 — that's a Confirm-tier ask, not HITL. HITL exists for ambiguity, not effort.

**Show your work.** Print the signal arithmetic for HITL just like Auto/Confirm — never just declare a confidence number.

#### HITL-deferrable flow

1. **Create a GitHub issue** via `mcp_github_issue_write` (method `create_issue`). If the tool is not loaded, run `tool_search` for "create github issue" first; if no issue-creation tool is available, **stop and surface to the user** — the HITL-deferrable flow requires a durable issue, so falling back to a bare PR-thread reply would re-introduce the PR #50 round-5 stranded-thread failure mode. Do not silently downgrade to HITL-blocking.

   - **Title:** `<scope>: <one-line summary> (from PR #<N> Copilot review)`
   - **Labels:** best-effort — first use `tool_search` to find an available GitHub label-lookup tool (e.g. `get_label` / `list_labels`); if one is loaded, look up `copilot-review` and `hitl-deferred` and include only labels that already exist. If no label tool is available or the labels are missing, **omit labels entirely** — do not create labels without authorization, and do not let label resolution block issue creation.
   - **Body:**

     ```markdown
     **Parent PR:** #<N>
     **Source comment:** <html_url of the PR comment>
     **File:** `<path>:<line>`
     **Confidence:** <score> = <signal arithmetic>

     ## Interpretation

     <one sentence>

     ## Proposed approach

     - <bullet>
     - <bullet>

     ## Blockers / questions

     - <what makes this non-trivial>

     ## Context for shft

     Files to read:
     - `<path>` — <why>

     Acceptance criteria:
     - [ ] <testable outcome>

     Feedback loops:
     - `<command>`
     ```

2. **Post the thread reply** via `mcp_github_add_reply_to_pull_request_comment`:

   ```
   Filed as #<issue-number> for follow-up — not blocking this PR.

   Confidence: <score> = <arithmetic>
   Interpretation: <one sentence>
   Proposed approach:
   - <bullet>
   - <bullet>
   ```

3. **Resolve the thread** via `mcp_github_pull_request_review_write` (method `resolve_thread`). The work is now tracked in the issue — the reviewer can either accept the deferral or comment on the issue to challenge it. **Degraded mode** — if thread IDs are not available (e.g. the VS Code PR extension is not loaded and `gh api graphql` is not installed), skip resolution, note "thread not auto-resolved (degraded mode)" in the reply and the summary, and continue. The issue is the durable artifact; resolution is best-effort.

#### HITL-blocking flow

Post a reply on the thread with this shape and **do not** resolve, **do not** file an issue, **do not** commit a speculative fix:

```
Flagging for human review.

Confidence: <score> = <arithmetic>
My interpretation: <one sentence>

Why this is HITL-blocking (not deferrable): <what makes the approach itself ambiguous>

Reply with guidance and I'll address in a follow-up commit.
```

**Failure modes caught in dogfooding:**

- **PR #50 round 5** posted `(confidence: 10)` with no arithmetic, then deferred a normal test-coverage ask into HITL using effort-based reasoning ("bundling risks another re-review round"). Both wrong: the score must show signals, and "this is a lot of work" is not a HITL signal — file an issue and move on.
- **PR #50 round 5** also stranded the deferral in a PR thread that nobody came back to. The HITL-deferrable flow above prevents that — the issue is the durable artifact.

### 6. Push + re-request review

After the final slice, hand off to **atomic-commits** (Ship mode) for rebase + push.

Then call `mcp_github_request_copilot_review` on the PR. If it fails, surface the PR URL so the user can re-request manually.

### 7. Summary report

Post the summary in two places: chat (for the user) **and** as a top-level PR comment via `mcp_github_add_issue_comment` (for the next reviewer — human or bot — who lacks chat history). **Post on every round, not just the last** — each round's summary gives the next reviewer the per-round paper trail. Use the same block in both:

```
PR #<N> — Copilot review addressed (round <R>)

Pre-flight: round <R>/<cap> | CI <green|red|pending> | pending review <yes|no>[ | (cap=<cap> overridden by user on round <R_override>)]
Triage:            Auto <X>  |  Confirm <Y>  |  HITL-deferrable <Zd>  |  HITL-blocking <Zb>
Comments fixed:    <X+Y> / <total>
Issues filed:      <Zd> (HITL-deferrable)
Threads resolved:  <X+Y+Zd−Zd_degraded>
Threads not auto-resolved: <Zd_degraded> (HITL-deferrable, degraded mode — issue filed but thread ID unavailable)
Threads left open: <Zb> (HITL-blocking)
Commits:           <C>
Review re-requested: yes | manual | no (cap reached)

Commits:
  <sha[:7]>  <message>
  ...

Awaiting human (HITL):
  - #<comment-id> <file>:<line> — <one-line summary>  [confidence: <score>]
  ...

Skipped / deferred:
  - <comment summary> — <reason>
```

Omit the `Threads not auto-resolved` line entirely when `Zd_degraded == 0` (i.e. all HITL-deferrable threads were resolved normally). Only include it when degraded mode prevented thread resolution.

Skip the PR comment only if `X+Y+Zd+Zb == 0` AND no pre-flight check fired — i.e. the round was a true no-op. Otherwise post, even on rounds where you only filed issues or only triaged.

The bracketed `(cap=<cap> overridden by user on round <R_override>)` segment in the pre-flight line is **mandatory** on every round after the user authorizes continuing past the cap (per §0). Omit the bracketed segment on rounds 1 through `<cap>`. This is the only sanctioned place to record the override — do not bury it in chat.

**Failure mode caught in dogfooding (PR #50):** ran 5 rounds, only round 5 posted a PR-comment summary. The intermediate rounds left no paper trail — a reviewer landing on the PR mid-flow couldn't tell what had been triaged, fixed, or deferred without scrolling commit-by-commit.

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
