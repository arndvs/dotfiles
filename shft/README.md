# shft

The autonomous execution side of ctrl+shft. `ctrl` manages your environment; `shft` manages your work queue.

## Two Execution Modes

| Mode | Command | How it works |
|------|---------|-------------|
| **HITL** | `shft run` | Claude with `--permission-mode acceptEdits` — you watch and approve each edit |
| **AFK** | `shft afk [n]` | Autonomous loop — picks issues, implements, commits, closes, repeats for `n` iterations (default 5) |

## Commands

| Command | Purpose |
|---------|---------|
| `shft run` | Start a HITL session |
| `shft afk [n]` | Start an AFK loop (`n` iterations, default 5) |
| `shft status` | Show loop state, open issues, plan progress |
| `shft stop` | Signal the AFK loop to stop after current iteration |
| `shft log [-f]` | Show recent log entries (`-f` to follow) |
| `shft issues` | List open GitHub issues sorted by priority |
| `shft next` | Show the next issue to work on |
| `shft done` | Mark current issue as complete |
| `shft plan` | View/edit the working plan |
| `shft engine on\|off\|status` | Switch between bash and TypeScript engines |
| `shft proxy start\|stop\|status` | Manage the LiteLLM/Copilot proxy daemon |
| `shft validate` | Run AFK environment validation |
| `shft mint` | Test GitHub App token minting |
| `shft context` | Show current context detection results |
| `shft help` | Show all commands |

## Task Selection Priority

The agent picks issues in this order (defined in `prompt.md`):

1. Critical bugfixes — bugs block other work
2. Development infrastructure — tests, types, dev scripts
3. Tracer bullets — small end-to-end slices validating approach
4. Polish and quick wins
5. Refactors

## TypeScript Engine

The TypeScript engine (`shft/engine/`) replaces shft's raw bash-to-Claude pipeline with schema-validated typed results via `@ai-hero/sandcastle`. Enable it with `shft engine on` or `SHFT_ENGINE=ts`.

### Architecture

```
shft/engine/
  main.ts          ← CLI entry + orchestrator
  schemas/         ← Zod schemas for each workflow's output
  workflows/       ← TypeScript workflow implementations
  prompts/         ← Prompt templates consumed by sandcastle
  lib/             ← Shared utilities (semaphore, diff parsing, PR comments)
```

**Key principle:** separation of thinking from acting. The agent emits structured JSON data; TypeScript code acts on it (posting reviews, creating issues, merging branches).

### Workflows

| Workflow | Flag | Purpose |
|----------|------|---------|
| `parallel` | `--workflow parallel` | Plan phase selects issues, then fan-out concurrent implementation + merge |
| `implement` | `--workflow implement` | Single-issue implementation with `<promise>COMPLETE</promise>` signal |
| `implement-pr` | `--workflow implement-pr --pr N` | Address PR review feedback, post replies and inline comments |
| `review` | `--workflow review --pr N` | Code review — posts a GitHub review with summary and inline comments |
| `to-issues-prd` | `--workflow to-issues-prd --issue N` | Decompose a PRD issue into sub-issues |
| `plan` | `--workflow plan` | Plan phase only — select and prioritize issues |

### CLI Flags

| Flag | Default | Purpose |
|------|---------|---------|
| `--repo` | required | Absolute path to the target repo |
| `--workflow` | `implement` | Which workflow to run |
| `--max-iterations` | `1` | Max agent iterations per issue |
| `--max-issues` | `5` | Max issues for plan phase |
| `--max-parallel` | `4` | Max concurrent agents (parallel workflow) |
| `--issue` | — | Target a specific issue number |
| `--branch` | — | Branch name override |
| `--pr` | — | PR number (for review/implement-pr) |
| `--dry-run` | `false` | Print without acting (to-issues-prd) |

### How It Works

**Bash engine (default):**
```
shft afk N → afk.sh → _build_prompt.sh → claude CLI → parse stream → loop
```

**TypeScript engine (`SHFT_ENGINE=ts`):**
```
shft afk N → afk.sh → npx tsx engine/main.ts --workflow parallel
  → runPlan() → plan.md → PlanOutput (issue list)
  → Semaphore(maxParallel) for each issue
    → createSandbox(branch) → implement.md → commits
  → runMerge(completedBranches) → merge.md → MergeOutput
```

### Schemas

Each workflow produces Zod-validated structured output:

| Schema | Fields |
|--------|--------|
| `PlanOutput` | `issues[].{number, title, branch}` |
| `MergeOutput` | `merged[], failed[].{branch, reason}, testsPassed` |
| `ImplementPrOutput` | `threadReplies[], newInlineComments[], topLevelComments[]` |
| `ReviewOutput` | `summary, inlineComments[], replies[]` |
| `PrdSlicesOutput` | `slices[].{title, type, whatToBuild, acceptanceCriteria[], blockedBy[]}` |

Schema field aliasing via Zod `.transform()` handles LLM output variations (e.g. `file`/`path`, `body`/`comment`).

### Validation

- Inline comments are validated against `git diff` output — comments on lines not in the diff are silently dropped with a warning
- Thread reply `commentId`s are validated against fetched PR threads — invalid IDs are dropped with a warning
- `StructuredOutputError` fires when agent output doesn't match the expected schema

## Files

| File | Purpose |
|------|---------|
| `shft` | Main CLI — command routing, state management, environment validation |
| `afk.sh` | AFK loop — engine dispatch, iteration control, locking |
| `once.sh` | Single HITL run — invokes Claude with issue context |
| `prompt.md` | System prompt injected into AFK/HITL sessions |
| `_build_prompt.sh` | Assembles the full prompt from issues + recent commits |
| `_proxy_env.sh` | Proxy environment setup (reads `~/.shft/proxy.json`) |
| `engine/` | TypeScript engine (see above) |

## Security

- AFK mode uses **short-lived GitHub App tokens** minted per iteration via `bin/mint_github_app_token.py`
- **Lock directory** (`/tmp/shft-afk.lock`) prevents concurrent AFK loops
- AFK invokes Claude with `--dangerously-skip-permissions`; on Linux/macOS it typically runs inside the Docker-backed `srt` sandbox, but on WSL/MSYS it runs unsandboxed with an explicit warning (deny rules still apply)
- The TypeScript engine currently uses `noSandbox()` on all platforms; Docker-backed sandboxing is not yet wired in
