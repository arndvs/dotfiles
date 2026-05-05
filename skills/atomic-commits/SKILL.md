---
name: atomic-commits
description: "Atomic commits on a feature branch with conventional messages — Commit mode for checkpoints, Ship mode for PR. Use when committing, checkpointing, shipping, pushing, or creating a PR."
---

# Atomic Commits

Output "Read Atomic Commits skill." to chat to acknowledge you read this file.

## When to use

Use this skill whenever work has been completed and needs to be committed or shipped. Enforces atomic commits — one logical change per commit with a conventional commit message — on a feature branch, merged via PR. Two modes: **Commit** (branch + stage + commit) for checkpoints, **Ship** (+ rebase + push + PR) when ready for review. Trigger any time the user asks to 'commit', 'save progress', 'checkpoint my work', 'ship', 'push', 'create a PR', or has just finished implementing a feature, fix, or refactor.

## Core Principles

- **One logical change per commit** — each commit does exactly one thing
- **Self-contained** — every commit leaves the codebase in a working state
- **Independently revertable** — any commit can be reverted without breaking other commits
- **Descriptive** — the commit message fully explains _what_ changed and _why_
- **Branch-isolated** — work happens on an `ai/` feature branch, merged via PR

---

## Two Modes

This skill operates in two modes depending on the user's intent:

| Mode       | When                                                                  | Steps    |
| ---------- | --------------------------------------------------------------------- | -------- |
| **Commit** | Default. User says "commit", "save progress", "checkpoint my work"    | 0 → 1 → 2 → 3 |
| **Ship**   | User says "ship", "push", "PR", "create a pull request", "open a PR" | 0 → 1 → 2 → 3 → 4 → 5 |

During multi-slice work, use **Commit** mode at each slice. Use **Ship** mode only when all slices are done and the work is ready for review.

---

## Workflow

### 0. Ensure a feature branch

Before any staging, make sure you're on a feature branch — never commit directly to `dev`, `main`, or `master`.

```bash
CURRENT_BRANCH="$(git branch --show-current)"
```

**If already on an `ai/*` branch or any non-base branch** (e.g. `feature/foo`, `bugfix/bar`): reuse it — add commits to the current branch.

**If on a base branch** (`dev`, `main`, or `master`): create a new feature branch:

```bash
BASE_BRANCH="$CURRENT_BRANCH"
# Branch name format: ai/<type>/<short-desc>
# <type> matches the primary conventional commit type (feat, fix, refactor, docs, chore)
# <short-desc> is 2-4 kebab-case words describing the work
git checkout -b "ai/<type>/<short-desc>"
```

Examples:
- `ai/feat/compaction-guard-hooks`
- `ai/fix/pagination-off-by-one`
- `ai/docs/sync-readme-with-project`
- `ai/refactor/extract-date-helpers`

### 1. Survey the diff

Start by reviewing everything that changed:

```bash
git diff          # unstaged changes
git diff --staged # already staged changes
git status        # full picture of modified/untracked files
```

Identify natural "seams" — boundaries between distinct logical changes. These become your commit boundaries.

### 2. Group into logical units

Decompose the diff into an ordered commit plan. Each unit should have a single clear purpose:

```
1. feat(auth): add JWT refresh token rotation
2. test(auth): cover token rotation edge cases
3. chore(config): add REFRESH_SECRET env variable
```

If a change touches unrelated concerns, split the file-level staging accordingly using `git add -p` for partial file staging.

### 3. Stage and commit each unit

Work through each logical unit one at a time:

```bash
git add <specific-files>        # stage only what belongs to this commit
git add -p <file>               # stage partial file changes if needed
git diff --staged               # confirm exactly what's going in
git commit -m "<type>(<scope>): <summary>"
```

Never use `git add .` blindly — always confirm what's staged before committing.

### 4. Sync with base branch (Ship mode only)

After all commits are made, rebase onto the base branch to catch conflicts early:

```bash
# Detect the base branch — check which of dev/main/master exists on remote
for candidate in dev main master; do
  if git rev-parse --verify "origin/$candidate" >/dev/null 2>&1; then
    BASE_BRANCH="$candidate"
    break
  fi
done
BASE_BRANCH="${BASE_BRANCH:-main}"

git fetch origin "$BASE_BRANCH"
git rebase "origin/$BASE_BRANCH"
```

If conflicts arise:
1. Resolve each conflict manually — never auto-accept theirs or ours blindly
2. `git add <resolved-file>` after each resolution
3. `git rebase --continue`
4. If the conflict is too complex, `git rebase --abort` and ask the user

### 5. Push and create PR (Ship mode only)

```bash
git push -u origin HEAD
```

Then create a pull request targeting the base branch. Requires `gh` CLI:

```bash
if ! command -v gh >/dev/null 2>&1; then
  echo "gh CLI not found — push completed. Create the PR manually."
else
  gh pr create \
    --base "$BASE_BRANCH" \
    --title "<type>(<scope>): <summary of all changes>" \
    --body "## Changes

  - <bullet summary of each commit>

  ## Verification

  - [ ] Tests pass
  - [ ] Types check
  - [ ] Reviewed diff"
fi
```

The PR title should summarize the full feature branch, not individual commits. Use the conventional commit format.

**After creating the PR:** report the PR URL to the user. Do not merge — the PR exists for review.

---

## Conventional Commit Message Format

```
<type>(<scope>): <short imperative summary>

[optional body: explain WHY, not what — the diff shows what]

[optional footer: breaking changes, issue refs]
```

### Types

| Type       | When to use                                |
| ---------- | ------------------------------------------ |
| `feat`     | New feature or capability                  |
| `fix`      | Bug fix                                    |
| `refactor` | Code restructuring with no behavior change |
| `test`     | Adding or updating tests                   |
| `docs`     | Documentation only                         |
| `chore`    | Tooling, deps, config, build scripts       |
| `style`    | Formatting, whitespace (no logic change)   |
| `perf`     | Performance improvement                    |
| `revert`   | Reverting a prior commit                   |

### Rules

- Summary line: 50 chars or fewer, imperative mood ("add", not "added" or "adds")
- No period at end of summary
- Body: wrap at 72 chars, explain motivation and context
- Reference issues in footer: `Closes #42`, `Fixes #17`

### Examples

```
feat(auth): add JWT refresh token rotation

Tokens now rotate on each use to limit exposure window.
Previous single-token approach left sessions vulnerable
to replay attacks if a token was intercepted.

Closes #88
```

```
fix(api): return 404 instead of 500 for missing user
```

```
refactor(utils): extract date formatting into shared helper
```

---

## What Makes a Good Atomic Commit?

✅ **Good** — single, clear purpose:

- `fix: correct off-by-one in pagination offset`
- `feat(search): add debounce to search input`
- `test: cover edge cases for empty cart checkout`

❌ **Bad** — too broad or mixed:

- `fix stuff`
- `WIP`
- `feat: add search, fix bug, update styles, refactor utils`

If your message needs "and" to describe what changed — split it into two commits.
