---
name: press1-check
description: Audit which Bash commands required manual approval ("press 1") in Claude Code sessions. Scans JSONL transcripts, classifies risk (HIGH/MEDIUM/LOW), and suggests safe allow-list additions. Use when the user says "press1-check", "press 1 check", "permission audit", or wants to review which commands need allow-listing.
---

# /press1-check — Permission Audit

Output "Read Press1 Check skill." to chat to acknowledge you read this file.

Audit which Bash commands triggered manual approval prompts in Claude Code sessions.

---

## When to invoke

- After sessions with many "press 1 to approve" prompts
- Periodically (every 5-10 sessions) to keep the allow-list current
- When the user says "permission audit" or "press1-check"
- Before proposing new hooks that add Bash commands

---

## How it runs

Two paths:

- **Manual:** type `/press1-check` to force a re-audit. Default mode is *since the last run* (state-tracked at `~/.claude/state/press1-check.json`), so the typical run only surfaces new ground.
- **Auto (optional):** the script supports `--auto-stop-hook` mode designed to be wired as a Claude Code `Stop` hook. 6-hour cooldown. When LOW-risk additions are found, a one-shot summary surfaces in the next session-start priority snapshot.

---

## Usage

```bash
# Since the last run (default, state-tracked)
python3 audit-permissions.py

# Last N days across all project dirs
python3 audit-permissions.py --days 7

# Only the single most recent session
python3 audit-permissions.py --latest-session

# All sessions from the last 24h
python3 audit-permissions.py --all-recent

# All sessions since a date
python3 audit-permissions.py --since 2026-04-10

# Specific session (prefix match OK)
python3 audit-permissions.py <session-id>
```

---

## Steps (when invoking via `/press1-check`)

1. Run `python3 <skill-path>/audit-permissions.py` with any arguments the user provided. Default audits since `~/.claude/state/press1-check.json#last_run_ts` (bootstraps to last 3 days when state is missing).
2. Display the output to the user exactly as printed (includes color-coded risk levels).
3. If LOW-risk suggestions appear, add them to `~/.claude/settings.json` (read-only commands are safe). Skip env-var-prefix suggestions like `Bash(WT=*)` — they don't generalize.
4. Do NOT auto-add MEDIUM or HIGH risk commands without explicit approval.
5. After editing `~/.claude/settings.json`, re-run the audit and report before/after counts so the user sees the coverage delta.
6. Each successful interactive run updates the state file — the next run is automatically scoped to "since now."

---

## Risk Classification

| Risk | Color | Policy | Example |
|------|-------|--------|---------|
| **HIGH** | Red | Keep gated — destructive or hard to reverse | `rm`, `sudo`, `git reset --hard`, `DROP TABLE` |
| **MEDIUM** | Yellow | Review case-by-case — side effects outside local repo | `gh pr create`, `curl`, `docker`, `pip install` |
| **LOW** | Green | Safe to allow-list — read-only or local-only | `cat`, `ls`, `grep`, `wc` |

---

## Constraints

- Never auto-add MEDIUM or HIGH risk commands
- The script never auto-applies changes — it surfaces and proposes
- State-tracked incremental runs prevent audit fatigue
- Subagent awareness: detects `*/subagents/*.jsonl` and tags findings
