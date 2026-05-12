# shft

The autonomous execution side of ctrl+shft. `ctrl` manages your environment; `shft` manages your work queue.

## Two Execution Modes

| Mode | Command | How it works |
|------|---------|-------------|
| **HITL** | `shft run` | Claude with `--permission-mode acceptEdits` — you watch and approve each edit |
| **AFK** | `shft afk [n]` | Autonomous loop via `srt` (Anthropic Sandbox Runtime, Docker-backed) — picks issues, implements, commits, closes, repeats for `n` iterations (default 5) |

## Commands

| Command | Purpose |
|---------|---------|
| `shft run` | Start a HITL session |
| `shft afk [n]` | Start an AFK loop (`n` iterations, default 5). Requires Docker + `srt` |
| `shft status` | Show loop state, open issues, plan progress |
| `shft stop` | Signal the AFK loop to stop after current iteration |
| `shft log [-f]` | Show recent log entries (`-f` to follow) |
| `shft issues` | List open GitHub issues sorted by priority |
| `shft next` | Show the next issue to work on |
| `shft done` | Mark current issue as complete |
| `shft plan` | View/edit the working plan |
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

## Files

| File | Purpose |
|------|---------|
| `shft` | Main CLI — command routing, state management, environment validation |
| `afk.sh` | AFK loop implementation — Docker sandbox, iteration control, locking |
| `once.sh` | Single HITL run — invokes Claude with issue context |
| `prompt.md` | System prompt injected into AFK/HITL sessions |
| `_build_prompt.sh` | Assembles the full prompt from issues + recent commits |

## Security

- AFK runs in a **sandboxed container** via `srt` (Anthropic Sandbox Runtime) — filesystem and network isolation provided by Docker
- **Short-lived GitHub App tokens** are minted per AFK iteration via `bin/mint_github_app_token.py` — no long-lived auth tokens
- **Lock file** (`/tmp/shft-afk.lock`) prevents concurrent AFK loops
