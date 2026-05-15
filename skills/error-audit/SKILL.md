---
name: error-audit
description: Analyzes cross-session error patterns to surface systemic issues worth automating; invoke after sessions with repeated retry loops or before proposing new hooks.
---

# Error Audit

Output "Read Error Audit skill." to chat to acknowledge you read this file.

Analyzes patterns of repeated errors across recent sessions to surface systemic issues that should become rules, hooks, or architectural fixes rather than per-session patches.

---

## When to invoke

- Periodically (every 5-10 sessions) as a health check
- When the user notices "this keeps happening"
- After a session with 3+ retry loops on the same error
- When proposing a new hook or rule (to justify it with data)

---

## Method

### Phase 1 — Gather error data

Collect error signals from available sources:

#### Source A: Git log (commit messages mentioning fixes)

```bash
# Recent fix commits — patterns of what breaks repeatedly
git log --oneline --since="2 weeks ago" --grep="fix" --grep="revert" | head -30
```

#### Source B: Session transcripts (if available)

Look in `~/.claude/` or session storage for recent transcripts. Search for:
- "Error:", "error:", "failed", "FAIL"
- Retry patterns (same command run 2+ times)
- Tool call failures

```bash
# Find recent session files
find ~/.claude/projects/ -name "*.jsonl" -mtime -14 2>/dev/null | head -10
```

#### Source C: Test failures

```bash
# If test results are logged
git log --oneline --since="2 weeks ago" | grep -i "test\|spec" | head -20
```

#### Source D: HUD events (if available)

```bash
if [[ -f "$HOME/dotfiles/working/events.jsonl" ]]; then
  grep -i "error\|fail\|block" "$HOME/dotfiles/working/events.jsonl" | tail -30
fi
```

### Phase 2 — Classify patterns

Group errors into categories:

| Category | Signal | Example |
|----------|--------|---------|
| **Tooling** | Same CLI command fails repeatedly | `npx tsc` fails due to missing types |
| **Convention** | Same rule violation in multiple sessions | Committing to main directly |
| **Environment** | Setup/config errors | Missing env vars, wrong Node version |
| **Architecture** | Design flaws surfacing as runtime errors | Circular imports, wrong module boundary |
| **External** | Third-party API/service failures | Rate limits, auth expiry |

### Phase 3 — Score and prioritize

For each pattern found, assign:

- **Frequency**: How many sessions did this appear in? (1 = fluke, 3+ = systemic)
- **Cost**: How much time was wasted per occurrence? (minutes of retry loops)
- **Fixability**: Can this become a hook, rule, or architectural fix?

Priority = Frequency × Cost × Fixability

### Phase 4 — Recommend actions

For each high-priority pattern, recommend ONE specific action:

| Action Type | When to use | Example |
|-------------|-------------|---------|
| **New hook** | Repeated mechanical error that can be detected before it happens | "Add a hook that checks Node version on SessionStart" |
| **New rule** | Convention violation that the model keeps forgetting | "Add a rule that requires test file for every new module" |
| **Architecture fix** | Structural issue causing cascading failures | "Extract shared types to a package" |
| **Documentation** | Misunderstanding of how something works | "Document the auth flow in README" |
| **Ignore** | External/transient issue not worth automating | "GH API rate limits during peak hours" |

---

## Report Format

```
## Error Audit Report

**Period**: Last 2 weeks (N sessions analyzed)
**Patterns found**: M

### High Priority

| # | Pattern | Freq | Cost | Action |
|---|---------|------|------|--------|
| 1 | TypeScript path alias misconfigured | 4 sessions | ~10 min each | Rule: verify tsconfig paths on project start |
| 2 | Commit to main without PR | 2 sessions | 5 min each | Hook: ✅ already fixed (git-workflow-gate) |

### Medium Priority
...

### Resolved by existing mechanisms
- [pattern] → resolved by [hook/rule name]

### Recommendations
1. [Specific action with a one-liner justification]
2. ...
```

---

## Integration

After producing recommendations:

1. **If a new hook is recommended**: Use the `hooks/PROPOSAL_TEMPLATE.md` to draft it
2. **If a new rule is recommended**: Create in `rules/` following existing patterns
3. **If resolved**: Update `hooks/COVERAGE_MATRIX.md` to reflect new coverage

---

## Constraints

- Only analyze data that actually exists — do NOT fabricate patterns from thin air
- If session data is unavailable or incomplete, say so explicitly
- Minimum 3 occurrences before calling something "systemic"
- Prefer conservative recommendations — one well-placed hook over five speculative ones
