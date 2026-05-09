---
name: compliance-audit
description: "Auto-invoke after any do-work, tdd, systematic-debugging, or review-pr-copilot task completes to review the diff against active rules and skills, flag violations, update the skill if a gap is found, and close the loop between 'rule was loaded' and 'rule was followed'."
---

# Compliance Audit

Output "Read Compliance Audit skill." to chat to acknowledge you read this file.

Runs after a task completes. Reviews the actual diff against the rules and skills that were active during the session. Flags violations explicitly. Updates the skill if the gap is structural.

This skill exists because "Read X" confirms a rule was loaded into context — not that it was followed. The compliance audit closes that gap.

---

## When to invoke

Auto-invoke after:

- `/do-work` completes and produces a commit
- `/tdd` completes a red-green-refactor cycle
- `systematic-debugging` produces a fix
- `review-pr-copilot` finishes a round (catches self-initiated changes bundled into Copilot-comment commits — see PR #68 dogfood)

Can also be invoked manually: `/compliance-audit` to review the most recent commit against active context.

---

## Method

### Phase 1 — Gather active context

Before reviewing the diff, establish what rules and skills were in scope.

```bash
# What contexts were active during this session?
echo $ACTIVE_CONTEXTS

# What rule files are currently loaded?
ls ~/dotfiles/rules/

# What skills were explicitly invoked?
# (check the session transcript for "Read X" outputs)
```

Produce a list:

- Active instruction files (from `$ACTIVE_CONTEXTS`)
- Rules files loaded (from `rules/` matching active contexts)
- Skills explicitly invoked during the session

---

### Phase 2 — Get the diff

```bash
# Most recent commit diff
git diff HEAD~1 HEAD

# Or staged changes if not yet committed
git diff --cached
```

---

### Phase 3 — Rule-by-rule audit

For each active rule and instruction file:

1. State the rule in one line
2. Check the diff for evidence it was followed
3. Flag any violation explicitly

**Output format per rule:**

```
[RULE] global.instructions.md — Surgical Changes
[STATUS] ✓ PASS
[EVIDENCE] Only files mentioned in the task were modified. No reformatting of adjacent code.

[RULE] instructions/nextjs.instructions.md — Server Components by default
[STATUS] ✗ VIOLATION
[EVIDENCE] /app/components/UserCard.tsx added "use client" without justification.
           Server component was appropriate here — no client-side interactivity required.
[SEVERITY] Medium — pattern could spread if uncorrected
```

Severity levels:

- **Critical** — security, data integrity, or architectural violation
- **High** — rule broken in a way that will cause bugs or rework
- **Medium** — rule broken but consequence is quality/consistency, not correctness
- **Low** — minor deviation, likely intentional

---

### Phase 4 — Compliance summary

```
COMPLIANCE SUMMARY
──────────────────
Session: [task description]
Commit: [hash]
Rules checked: [n]
Skills checked: [n]

Results:
  ✓ PASS: [n]
  ✗ VIOLATION: [n]
  ⚠ UNCLEAR: [n]  (rule ambiguous — couldn't verify either way)

Violations:
  [list with severity]

Overall: PASS / FAIL / PARTIAL
```

---

### Phase 5 — Skill update (if structural gap found)

If a violation reveals that the active skill or rule doesn't clearly prohibit the behavior, update the skill inline.

**Decision rule:**

- Violation occurred AND the rule/skill was ambiguous → update the skill
- Violation occurred AND the rule/skill was clear → flag as agent non-compliance, no skill update needed
- No violation but rule was ambiguous → clarify the rule anyway

**Update format:**

```markdown
## ⚠ Known failure mode — [date]

**Situation:** [what happened]
**Rule that should have caught it:** [rule name]
**Why it didn't:** [ambiguity / gap in the wording]
**Fix:** [clarified instruction added below]

---
```

Add the fix directly to the relevant section of the skill or rule, not in a separate "known issues" block at the bottom.

---

### Phase 6 — Log entry

Append to `working/compliance-log.md`:

```markdown
## [date] — [task name] — [PASS/FAIL/PARTIAL]

Commit: [hash]
Active contexts: [list]
Violations: [n] ([severity summary])

[brief description of any violations and disposition]
```

Then push the result to the HUD daemon:

```bash
source ~/dotfiles/bin/write-hud-state.sh
update_hud_compliance <pass_count> <fail_count> <warn_count>
```

For each violation found, also emit individual events:

```bash
write_hud_event "fail" "VIOLATION — <rule_file> — <title> — <severity>"
```

This log becomes the stress test baseline and the honest answer to "has this been tested."

---

## Output

The audit produces:

1. A rule-by-rule compliance report in the session transcript
2. Any skill/rule updates applied inline
3. A log entry in `working/compliance-log.md`

The report goes in the session. The log persists across sessions. Over time the log is the empirical record of compliance rate.

---

## Honesty note

This audit cannot catch everything. It reviews the diff against stated rules — it cannot detect subtle semantic violations (e.g., code that technically compiles but violates the spirit of the architecture). The goal is not perfect verification. It's making violations visible and recoverable rather than silent.

The compliance rate over time is the real metric. A system with documented 85% compliance and a known improvement path is more trustworthy than one that claims 100% with no verification.
