---
name: plan-archive
description: Use after merging a PR or during periodic cleanup to archive plan-mode files by linking them to merged PRs.
---

# Plan Archive

Archives `~/.claude/plans/*.md` files by matching them to merged PRs via
file-overlap analysis, then moves them into organized directories with
metadata linking back to the PR, Linear tickets, and commits.

## When to Use

- After merging a PR: archive the plans it consumed
- Periodically: backfill to clean up accumulated plan files
- Before auditing: see what active plans exist and flag orphans

## Modes

### Audit (read-only)

List all active plans with last-modified dates. Good for seeing what's
accumulated.

```bash
python3 skills/plan-archive/plan-archive.py --mode=audit
```

### Archive one PR (dry-run by default)

Match plans to a specific merged PR and archive the bundle:

```bash
# Dry-run — see what would move
python3 skills/plan-archive/plan-archive.py --mode=archive-pr --pr=42

# Execute — actually move files
python3 skills/plan-archive/plan-archive.py --mode=archive-pr --pr=42 --execute
```

### Backfill (scan recent merged PRs)

Scan all merged PRs within a window and archive matching plans:

```bash
# Dry-run — see what would be archived
python3 skills/plan-archive/plan-archive.py --mode=backfill --since=30d

# Execute
python3 skills/plan-archive/plan-archive.py --mode=backfill --since=2w --execute
```

## Output

Archived plans go to `~/.claude/plans/archive/by-pr/PR-<num>-<branch-slug>/`
with a `_meta.yaml` containing:

- PR number, URL, title, branch, merge date, merge SHA
- Linear ticket references (CC-NNN pattern)
- List of archived plan filenames
- Cross-references to other PRs that matched the same plans

## Options

| Flag | Description |
|------|-------------|
| `--mode` | `audit`, `archive-pr`, or `backfill` (required) |
| `--pr` | PR number (required for `archive-pr`) |
| `--since` | Time window for backfill: `30d`, `2w`, `12h` (default: `30d`) |
| `--execute` | Actually move files (default: dry-run) |
| `--repo` | Override GitHub repo (default: cwd's repo) |
| `--plans-dir` | Override plans directory (default: `~/.claude/plans`) |
| `--limit` | Max PRs to fetch for backfill (default: 200) |

## How Plan Matching Works

1. Fetches the PR's diff file list via `gh pr diff --name-only`
2. Parses each plan's `## Files` section for declared file paths
3. Normalizes paths to repo-relative form
4. Matches plans with >= 1 file overlap with the PR diff
5. Plans are assigned to the earliest-merged PR that claims them (no double-archive)
