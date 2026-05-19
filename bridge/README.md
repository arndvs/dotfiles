# ctrl+shft Copilot Review Bridge

Automated bridge that receives GitHub Copilot review events via webhook and dispatches them to the `shft afk` agent loop for resolution.

## Architecture

```
GitHub webhook → FastAPI (bridge-webhook.service)
                     ↓ SQLite queue
              Worker (bridge-worker@1.service)
                     ↓
              shft afk 1 (Claude Code in srt sandbox)
```

## Quick Start

```bash
# Install (run on VPS)
bash bin/bridge-install.sh

# Start
ctrl bridge start

# Status
ctrl bridge status

# View queue
ctrl bridge queue

# Logs
ctrl bridge logs
```

## Required Environment Variables

### Non-sensitive (`secrets/.env.agent`)

Sourced into shells or loaded via systemd EnvironmentFile. No secrets.

| Variable | Description |
|---|---|
| `BRIDGE_PORT` | Port for webhook receiver (default: 8765) |
| `COPILOT_BOT_LOGIN` | Bot login (default: `copilot-pull-request-reviewer[bot]`) |
| `BRIDGE_REPO_ALLOWLIST` | Comma-separated `owner/repo` list |
| `BRIDGE_MAX_ITERATIONS` | Loop cap per PR (default: 3) |

### Webhook secret (`secrets/.env.bridge`)

Process-scoped only — loaded as a required systemd EnvironmentFile by
`bridge-webhook.service`. Never sourced into interactive shells.

| Variable | Description |
|---|---|
| `WEBHOOK_SECRET` | GitHub webhook secret (≥32 chars entropy) |

### Worker secrets (`secrets/.env.secrets`)

Process-scoped only — loaded by `bridge-worker@.service` via EnvironmentFile.
Never sourced into interactive shells.

| Variable | Description |
|---|---|
| `GITHUB_APP_ID` | GitHub App ID for token minting |
| `GITHUB_APP_PRIVATE_KEY_B64` | Base64-encoded private key (used by mint script) |
| `GITHUB_APP_INSTALLATION_ID` | Installation ID |

> **Note:** The webhook receiver only needs `WEBHOOK_SECRET` (from `.env.bridge`).
> GitHub App credentials are required only by the worker (from `.env.secrets`).

## MVP Constraints (Accepted)

These are known limitations of the MVP, documented and accepted:

1. **Global lockfile** — `/tmp/shft-afk.lock` limits to one concurrent `shft` invocation across all bridge + manual runs. Phase 2: per-workspace locks.

2. **Global working directory** — `~/dotfiles/working/` is shared. HUD events don't distinguish bridge vs manual sessions. Phase 2: per-workspace isolation (ADR pending).

3. **Single worker** — Only `bridge-worker@1` is supported. The `@` template supports future multi-worker, but the lockfile constraint makes it moot until Phase 2.

4. **No retry with backoff** — Failed jobs are marked `failed` and stay in the queue. Manual replay via `ctrl bridge replay <id>`.

5. **30-minute hard cap** — `shft afk 1` subprocess times out after 30 minutes. Adjust `SHFT_RUN_TIMEOUT_SECONDS` in `worker.py` if needed.

## Files

```
bridge/
  __init__.py          # Package init
  config.py            # Environment-based configuration
  models.py            # Pydantic models for GitHub events
  db.py                # SQLite queue (jobs + claim_keys tables)
  github.py            # Token minting, GraphQL/REST helpers
  workspace.py         # Per-PR git clone/fetch lifecycle
  issue.py             # Tracking issue body construction
  hud.py               # Fire-and-forget HUD event emission
  webhook.py           # FastAPI receiver (HMAC, filtering, enqueue)
  worker.py            # Poll loop → process → shft afk 1
  requirements.txt     # Python dependencies

systemd/
  bridge-webhook.service    # Webhook receiver unit
  bridge-worker@.service    # Worker template unit

bin/
  bridge-install.sh    # Idempotent installer
  ctrl                 # CLI (bridge subcommand)
```

## Audit Fixes Applied

All 10 priority findings from the codebase audit are addressed:

- **C-1**: No `--json` flag in mint_token (flag doesn't exist)
- **H-2**: head_ref fetched via REST, not from webhook payload
- **H-3**: All GitHub API calls go through `_client()` helper
- **H-4**: Dedicated `claim_keys` table for iteration tracking
- **S-1**: Ephemeral `GIT_CONFIG_COUNT` env vars (no token in .git/config)
- **S-2**: Token `__repr__` returns `Token(***)`
- **I-1**: bot_login validated as non-empty
- **I-3**: Allowlist parsing filters empty strings
- **L-1**: Only `pull_request_review` events accepted
- **L-2**: Only `state=changes_requested` reviews enqueued

See `docs/copilot-bridge-docs/CODEBASE-AUDIT.md` for the full audit report and `IMPLEMENTATION-PLAN.md` for the slice-by-slice plan.
