Load the `review-pr-copilot` skill from `~/dotfiles/skills/review-pr-copilot/SKILL.md` and run it end-to-end on the active PR. **Do not ask the user to paste comments** — fetch them yourself.

Trigger phrases (any of these should invoke this command, even without the slash):
- "address the review comments"
- "address review"
- "address copilot review"
- "fix the PR comments"
- "do another round"
- "round N" (continue past cap with override per skill §0)

## Execution shape — invoke the skill in five named phases

The skill's workflow already implements all of this; surface the phase headers in chat so the user sees the mental model. Do **not** invent a parallel workflow — the skill is the source of truth for tier rules, arithmetic, HITL flow, and PR-comment summary format.

### 1. Ultrathink — pre-flight (skill §0)

- Fetch the active PR via `github-pull-request_currentActivePullRequest`. If the cache looks stale (returns 0 unresolved threads but the PR clearly has open comments), fall back to `gh api graphql` for `reviewThreads` — see PR #69 round-2 dogfood note.
- Print the pre-flight line: `Pre-flight: round <N>/<cap> | CI <green|red|pending> | pending review <yes|no>`. Include `(cap=3 overridden by user on round <N>)` if applicable.
- Bail if CI is red, a review is pending, or round cap reached without override.

### 2. Deep explore — read the comments + their context (skill §1)

- Pull every unresolved Copilot thread via `mcp_github_pull_request_read` (method `get_review_comments`) plus the GraphQL `reviewThreads` query for thread node IDs.
- For each comment, read the surrounding code in the file the comment targets — never triage on the comment text alone.

### 3. Deep reason — score with arithmetic (skill §2)

- For every comment, print the signal arithmetic before declaring a score. Never just say "confidence: N".
- Apply the forced-Confirm keyword floor (`refactor:`, align/normalize, semantics, signature, error semantics, rename of public API).
- Apply the HITL ambiguity-vs-effort test — large-but-objective work is Confirm-tier, not HITL.

### 4. Architect — group fixes into atomic commits (skill §3–4)

- Print the triage table (Auto / Confirm / HITL-deferrable / HITL-blocking) before any action.
- Group Auto fixes into atomic commits by **intent**, one commit per logical change. Do not bundle unrelated fixes.
- For Confirm tier, prompt the user with the diff preview before committing.
- For HITL-deferrable, draft the issue body using the skill §5b template.

### 5. Do work — apply, ack, resolve, summarize (skill §5–7)

- Apply Auto fixes, push commits.
- For each addressed thread: post an ack reply with the arithmetic, then resolve the thread.
- For HITL-deferrable: file a GitHub issue, post "Filed as #N" reply, resolve the thread.
- For HITL-blocking: post the blocking-reason reply, leave open.
- Post the per-round summary as a top-level PR comment (skill §7 template) — **every round, not just the last**.
- Re-request Copilot review via `mcp_github_request_copilot_review`.

## Tool-discovery contract

If a needed MCP tool is not loaded (e.g. `mcp_github_request_copilot_review`, `mcp_github_get_label`), use `tool_search` to discover it before calling. Do not assume any github MCP tool is pre-loaded.

$ARGUMENTS
