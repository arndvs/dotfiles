# Secrets

Three-tier credential isolation. Agents see config, never credentials.

## Three Tiers

| Tier | File | Visibility | Contains |
|------|------|-----------|----------|
| **Config** | `secrets/.env.agent` | Agent can see (sourced into shell) | Non-sensitive config — project IDs, feature flags, endpoints |
| **Credentials** | `secrets/.env.secrets` | Agent never sees (process-scoped) | API keys, tokens, passwords — exist only inside `run-with-secrets.sh` child process |
| **AFK tokens** | Minted per-iteration | Short-lived, auto-expire | GitHub App installation tokens for autonomous loops |

## How It Works

- `bin/load-secrets.sh` sources `.env.agent` into the shell — this is the config tier, safe for agent context
- `bin/run-with-secrets.sh` executes a command in a child process with `.env.secrets` loaded — credentials exist only for the duration of that process and vanish on exit
- `bin/mint_github_app_token.py` mints short-lived GitHub App installation tokens for each AFK iteration — no long-lived auth tokens persist

## Templates

Copy these to `secrets/` and fill in values:

| Template | Target |
|----------|--------|
| `.env.agent.example` | `secrets/.env.agent` — non-sensitive agent config |
| `.env.secrets.example` | `secrets/.env.secrets` — sensitive credentials |
| `.env.citation.example` | `secrets/.env.citation` — citation builder secrets |

## Directory Contents

```
secrets/
├── .env.agent           ← tier 1: config (sourced into shell)
├── .env.secrets         ← tier 2: credentials (process-scoped only)
├── .venv/               ← Python venv for mint_github_app_token.py
├── *.json               ← service account credentials (tier 2)
└── citation-evidence/   ← citation builder data
```

The `secrets/` directory is gitignored except for this README. No credentials or config files here are ever committed.

## Adding Secrets

1. Add the variable to the appropriate `.env.*.example` template (tracked in git, no real values)
2. Add the real value to `secrets/.env.agent` or `secrets/.env.secrets` (gitignored)
3. If the secret needs validation, add a check to `bin/validate-env.sh`

See [env-security rule](../rules/env-security.md) for the enforcement policy.
