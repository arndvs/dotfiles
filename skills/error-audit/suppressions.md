# Error-audit suppressions

Cluster keys marked "working as designed". `error-audit.py` hides these from `--human` output by default; `--show-suppressed` re-includes them. `--json` always tags every cluster with a `suppressed: true|false` field so downstream consumers decide policy.

## Format

One cluster_key per line inside the fenced code block below, optionally followed by a tab or 2+ spaces and a one-line reason. Lines starting with `#` are comments and ignored by the parser. Keys are matched **exactly** — a new signature on the same hook still surfaces because it yields a different cluster_key.

The cluster_key format is `class:tool:signature_first_60_chars` (deterministic — strip paths to `<X>`, strip `toolu_*` IDs, strip UUIDs, strip ISO timestamps, collapse whitespace, truncate).

## Suppressions

```
# git-workflow-gate — enforcing branch/rebase/chain-cd discipline. Working as designed.
permission_denial:Bash:cd	chained-cd denial from Gate 0
tool_error:Bash:Uncommitted changes (1 file(s)). Commit or stash before swit	git-workflow-gate catching unstaged work before branch switch
tool_error:Bash:Branch is behind origin/main by 1 commit(s). Run: `git fetch	git-workflow-gate catching stale rebase state

# secret-guard — blocking credential exposure. Working as designed.
hook_block:secret-guard:secret-guard	secret-guard blocking credential leak attempts

# compaction-guard — blocking auto-compaction. Working as designed.
hook_block:compaction-guard:compaction-guard	compaction-guard blocking auto-compaction
```

## Candidates to re-evaluate

Add clusters here when a triage classifies them as `newly-suppressible` but before moving them above. Allows human review before the scanner starts hiding them.

```
# (none yet)
```
