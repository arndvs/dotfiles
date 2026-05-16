---
name: error-audit
description: Audit errors across Claude Code session transcripts. Scans ~/.claude/projects/*.jsonl for 7 error classes (tool_error, validation_error, permission_denial, hook_block, bash_fail, retry_storm, read_before_edit), clusters by root-cause signature, and surfaces top N with suggested remediation tiers. Use when the user says "error audit", "errors across sessions", "system health errors", or "/error-audit".
---

# Error Audit

Output "Read Error Audit skill." to chat to acknowledge you read this file.

Scan every Claude Code session transcript for errors, cluster by root cause, surface the top offenders with suggested remediations.

---

## When to invoke

- Periodically (every 5-10 sessions) as a health check
- When the user notices "this keeps happening"
- After a session with 3+ retry loops on the same error
- When proposing a new hook or rule (to justify it with data)

---

## Usage

```bash
# Default: all sessions, top 20 clusters, human output
python3 error-audit.py

# Last 30 days only
python3 error-audit.py --since 30

# Show fewer clusters
python3 error-audit.py --top 10

# Machine-readable (for piping into other tools)
python3 error-audit.py --json

# Override the projects dir (useful for testing)
python3 error-audit.py --projects-dir /path/to/projects

# Override or disable suppressions
python3 error-audit.py --suppressions-path /path/to/suppressions.md
python3 error-audit.py --no-suppressions
python3 error-audit.py --show-suppressed
```

## Steps (when invoking via `/error-audit`)

1. Run `python3 <skill-path>/error-audit.py` with any arguments the user provided.
2. Display the output to the user exactly as printed (includes colour-coded counts and suggested remediation tiers).
3. For the top 3 clusters, propose a concrete action:
   - **Tier 1** (settings allowlist): show the exact `~/.claude/settings.json` entry to add, but do NOT auto-apply — user must review Bash allowlist changes.
   - **Tier 2** (hook or script fix): locate the hook/script and propose the edit.
   - **Tier 3** (instruction/memory): draft the feedback or mechanism memory entry.
4. Do NOT auto-apply any remediation. This skill surfaces and proposes; the user decides.

## Error Classes

| Class | Signal | Example |
|-------|--------|---------|
| `tool_error` | `is_error:true` on a tool result (excluding denials) | Read/Write/Edit failures |
| `validation_error` | `InputValidationError` in tool result | Wrong parameter types |
| `permission_denial` | "The user doesn't want to proceed" | Bash command rejected |
| `hook_block` | `hook_failure` attachment type | git-workflow-gate blocks |
| `bash_fail` | Non-zero `exitCode` on Bash attachment | Command failures |
| `retry_storm` | 3+ consecutive `overloaded_error` records | API overload |
| `read_before_edit` | "File has not been read yet" | Edit without prior Read |

## Remediation Tiers

| Tier | Fix type | Example |
|------|----------|---------|
| 1 | Settings allowlist | Add `Bash(cmd:*)` to allow list (review first) |
| 2 | Hook or script fix | Tune a hook to exclude a known-good pattern |
| 3 | Instruction/memory | Add behavioral memory covering the failure mode |

## Configuration

| Env var | Purpose | Default |
|---|---|---|
| `CLAUDE_ERROR_AUDIT_SUPPRESSIONS` | Suppressions file path | `<skill-dir>/suppressions.md` |

## Suppressions

The `suppressions.md` file (ships alongside `error-audit.py`) marks known "working-as-designed" cluster keys. Default human output hides them; `--show-suppressed` re-includes them; `--json` always includes them with a `suppressed: true|false` field.

## Fallback Method (when Python is unavailable)

If `python3` is not available, fall back to manual analysis:

### Phase 1 — Gather error data

```bash
# Recent fix commits
git log --oneline --since="2 weeks ago" --grep="fix" --grep="revert" | head -30

# Find recent session files
find ~/.claude/projects/ -name "*.jsonl" -mtime -14 2>/dev/null | head -10

# HUD events
if [[ -f "$HOME/dotfiles/working/events.jsonl" ]]; then
  grep -i "error\|fail\|block" "$HOME/dotfiles/working/events.jsonl" | tail -30
fi
```

### Phase 2 — Classify

Group errors into: Tooling, Convention, Environment, Architecture, External.

### Phase 3 — Score

Frequency × Cost × Fixability. Minimum 3 occurrences before calling "systemic."

### Phase 4 — Recommend

One specific action per pattern: new hook, new rule, architecture fix, documentation, or ignore.

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
