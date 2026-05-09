---
name: review-pr-copilot
description: "End-to-end loop for addressing GitHub Copilot review comments on the active PR: fetch Copilot-only feedback, fix in atomic commits, resolve threads, push, and re-request Copilot review. Use when asked to 'fix the PR comments', 'address Copilot review', 'clean up review feedback', 'fix Copilot comments', 'address PR feedback', or whenever a Copilot review exists on the current PR and the user wants to act on it."
---

# Review PR — Copilot

Output "Read Review PR Copilot skill." to chat to acknowledge you read this file.

## When to use

Use whenever Copilot has left review comments on a pull request and the user wants to address them. Trigger phrases: "fix the PR comments", "address Copilot review", "clean up review feedback", "fix Copilot's comments", "re-request review". Also trigger proactively when the active PR has unresolved Copilot review threads and the user asks to commit or ship.

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

### 2. Summarize and confirm

Print a numbered list before touching code:

```
PR #<N> — <X> open Copilot comments
  1. <file>:<line> — <one-line summary>
  2. ...
```

Ask the user to confirm or exclude any items. **Do not proceed without confirmation** if more than 3 comments — silent batch fixes are how regressions ship.

### 3. Plan slices

Group comments into atomic slices (one logical fix per commit). Surface the plan as a table:

| Slice | Files | Commit message |
|---|---|---|
| 1 | `src/auth/token.ts` | `fix(auth): handle null user in token refresh` |
| 2 | `src/api/*.ts` | `fix(api): propagate errors instead of swallowing` |

Wait for user approval.

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

After each commit pushes, resolve the corresponding Copilot threads via `mcp_github_resolveReviewThread`. Map comment IDs to thread IDs from step 1.

If a fix only partially addresses a thread, leave it open and note it in the final summary.

### 6. Push + re-request review

After the final slice, hand off to **atomic-commits** (Ship mode) for rebase + push.

Then call `mcp_github_request_copilot_review` on the PR. If it fails, surface the PR URL so the user can re-request manually.

### 7. Summary report

```
PR #<N> — Copilot review addressed

Comments fixed:    <X> / <total>
Commits:           <N>
Threads resolved:  <X>
Review re-requested: yes | manual

Commits:
  <sha[:7]>  <message>
  ...

Skipped / deferred:
  - <comment summary> — <reason>
```

---

## Edge cases

- **No Copilot review found** — say so, offer to address all reviewer comments instead (defer to `address-pr-comments`)
- **Comment on deleted/renamed file** — surface to user, don't guess
- **Vague comment** ("consider refactoring") — show your interpretation + proposed fix, get approval per-comment
- **Stale comment** (file changed since) — re-read current file, rebase the fix mentally, flag if the comment no longer applies
- **MCP tool naming differs** — use `tool_search` to find the actual GitHub MCP tools available; common variants: `get_pull_request`, `pull_request_read`, `mcp_github_pull_request_read`

---

## Guardrails

- Never fix things Copilot didn't flag in the same commits — file a follow-up note instead
- Never force-push without confirmation
- Never auto-resolve a thread you didn't fully address
- Stop and ask if a fix would break public API, change types broadly, or modify test assertions
