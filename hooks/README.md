# Hooks

Claude Code lifecycle hooks — shell scripts that fire on tool use and session events.

## How Hooks Work

Claude Code hooks are **JSON configuration** in `~/.claude/settings.json`, not standalone files. Each hook references a shell script that receives JSON on stdin and communicates via exit codes:

- **Exit 0** — allow (tool proceeds / agent stops normally)
- **Exit 2** — block (tool use rejected / agent continues working)

Bootstrap symlinks `hooks/` → `~/.claude/hooks/` and merges the configuration from `settings-hooks.json` into `~/.claude/settings.json`.

## Hooks

| Script | Event | Matcher | Behavior |
|--------|-------|---------|----------|
| `secret-guard.sh` | PreToolUse | Bash | Blocks commands that expose credentials (echo $TOKEN, bare env/printenv, cat secrets/) |
| `migration-guard.sh` | PreToolUse | Bash | Blocks database migration commands targeting non-test databases |
| `git-workflow-gate.sh` | PreToolUse | Bash | Enforces git safety: no commit to main, conventional messages, no force-push, no dirty-tree switch, no cd+git chains |
| `plan-quality-gate.sh` | PreToolUse | Bash | Warns when scaffolding (mkdir, npx create-, etc.) has no plan file; when a plan exists, validates required sections and emits a checklist summary |
| `plan-review-phase2.py` | PreToolUse | Bash | Phase 2 PR diff comparison — warns when `gh pr create` diff is missing planned files (CC-80/174/175) |
| `feedback-memory-gate.py` | PostToolUse | Write | Warns when feedback memory files describe bugs without an issue tracker reference |
| `git-post-push.sh` | PostToolUse | Bash | Info nag when no PR exists after pushing to a feature branch |
| `stale-branches.sh` | SessionStart | — | Reports merged or stale (>14d) local branches at session start |
| `format-check.sh` | Stop | — | Detects Biome/Prettier/ESLint and formats modified files (non-blocking) |
| `typecheck.sh` | Stop | — | Runs `tsc --noEmit` on TypeScript projects; blocks stop until types pass |
| `compaction-guard.sh` | PreCompact | auto | Blocks auto-compaction at ~95% context; directs agent to follow handoff protocol |
| `hud-session.sh` | SessionStart, Stop | — | Emits session lifecycle events to `events.jsonl` for the HUD |
| `hud-reads.sh` | PostToolUse, InstructionsLoaded | Read | Emits read events to the HUD — tracks which instructions/skills/rules loaded and external file reads |
| `context-warning.sh` | UserPromptSubmit | — | ⚠️ STUB: graduated context warnings at 40/70% (pending statusLine experiment) |

## Requirements

- **jq** — all fail-closed hooks (secret-guard, migration-guard, git-workflow-gate) **require** jq and deny if missing. Fail-open hooks (stale-branches, plan-quality-gate, git-post-push) skip gracefully if jq is missing.
- **Python 3** — `plan-review-phase2.py` and `feedback-memory-gate.py` require Python 3.
- **npx** — format-check and typecheck use npx to run project-local tools.

## Editor Compatibility

Hooks are a **Claude Code CLI** feature. They fire in:
- Claude Code CLI (`claude`)
- VS Code with Claude Code extension

They do **not** fire in Cursor or GitHub Copilot Chat. The scripts themselves are portable bash — they can be run manually or referenced from other tools.

## Context Awareness

**Compaction guard** (`compaction-guard.sh`) — fully operational. Blocks auto-compaction at ~95% context and directs the agent to commit work and follow the handoff protocol instead. Manual `/compact` is unaffected. This mechanically enforces the `global.instructions.md` policy: "prefer clearing context over compacting."

**Graduated warnings** (`context-warning.sh`) — stub, pending experiment. Hook input JSON does not include context usage. However, the `statusLine` setting receives `context_window.used_percentage` (confirmed in env vars docs). A statusLine command can write the percentage to a state file; this hook reads it and injects warnings via `additionalContext` at 40% and 70%. Run `hooks/experiments/statusline-probe.sh` to discover the statusLine input format, then fill in the bridge. See `hooks/experiments/README.md` for setup instructions.

## Customization

Edit the scripts in `~/dotfiles/hooks/` (source of truth). Changes propagate via the symlink. To add a new hook:

1. Create `hooks/your-hook.sh` (receives JSON on stdin, exits 0 or 2)
2. Add the hook entry to `hooks/settings-hooks.json`
3. Re-run `ctrl bootstrap` (or `bash ~/dotfiles/bin/bootstrap.sh`) to merge the updated config

To disable a hook, remove its entry from `~/.claude/settings.json` (or from `settings-hooks.json` and re-run bootstrap with a fresh `~/.claude/settings.json`).

## Fail Modes

Every hook declares its fail mode on line 2 as `# FAIL_MODE: closed|open`.

| Mode | Meaning | When to use |
|------|---------|-------------|
| `closed` | Unhandled errors produce deny JSON — if the hook crashes, the operation is blocked | Security/correctness (secret-guard, migration-guard, git-workflow-gate) |
| `open` | Unhandled errors exit 0 — if the hook crashes, the operation proceeds | Quality/convenience (format-check, typecheck, hud-session) |

**Principle:** Hooks that prevent irreversible damage fail closed. Hooks that improve quality fail open.

**Implementation:** Fail-closed PreToolUse hooks use `trap '_fail_closed' ERR` to emit deny JSON on any error. Other fail-closed hooks (e.g., `compaction-guard.sh`) exit 2 with plain stderr text. Fail-open hooks use `trap 'exit 0' ERR` to ensure any unhandled error exits cleanly without blocking.

## Per-Repo Config

The `git-workflow-gate.sh` hook reads an optional `.ctrlshft` YAML file at the repo root for per-repo overrides:

```yaml
# .ctrlshft — per-repo hook configuration (block-list format)
commit_types:
  - feat
  - fix
  - refactor
  - chore
  - docs
  - test
  - perf
  - ci

protected_branches:
  - main
  - master
  - production
```

> **Note:** Use YAML block-list format (one `- item` per line). Inline arrays (`[feat, fix, ...]`) are not supported by the parser.

If the file doesn't exist, defaults apply. If parsing fails, defaults apply (fail-open for config).

### Commit Message Validation

The conventional commit check in `git-workflow-gate.sh` only validates messages passed inline via the `-m` flag (e.g., `git commit -m "feat: ..."`). Editor-based commits (no `-m` flag) or commits using `-F`/`--file` are **not** validated — the message content isn't visible in the command string. This is a known limitation; linting all commit messages requires a native `commit-msg` git hook.
