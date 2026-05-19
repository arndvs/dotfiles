#!/usr/bin/env bash
# bin/bridge-install.sh — set up the Copilot review bridge on this host.
# Idempotent. Safe to re-run after pulls.
#
# Usage:
#   bridge-install.sh              full install
#   bridge-install.sh --validate   check-only (no installs, no symlinks)
set -euo pipefail

DOTFILES="${CTRLSHFT_HOME:-$HOME/dotfiles}"
BRIDGE_ROOT="${BRIDGE_ROOT:-$HOME/bridge}"
VENV="$DOTFILES/secrets/.venv"

log()  { printf '\033[1;34m[bridge-install]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[bridge-install]\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31m[bridge-install]\033[0m %s\n' "$*" >&2; exit 1; }

validate_only=0
[[ "${1:-}" == "--validate" ]] && validate_only=1

# ── 1. Prereq checks ────────────────────────────────────────────────────────
_ok=1
_check() {
    if ! command -v "$1" >/dev/null 2>&1; then
        die "$1 not installed — $2"
    fi
}

_check docker "required by shft afk (srt sandbox)"
_check systemctl "systemd required for service management"
_check sqlite3 "required for job queue"
_check jq "required for JSON processing"

# srt (Docker sandbox runner) — required for shft afk
if ! command -v srt >/dev/null 2>&1; then
    die "srt not installed — required by shft afk. See: https://github.com/arndvs/srt"
fi

[[ -d "$VENV" ]] || die "$VENV missing — run 'ctrl bootstrap' first"
[[ -x "$VENV/bin/python" ]] || die "$VENV/bin/python missing — venv is broken"

log "prerequisites: OK"

# ── 2. Required env vars ────────────────────────────────────────────────────
for v in GITHUB_APP_ID GITHUB_APP_INSTALLATION_ID GITHUB_APP_PRIVATE_KEY_B64 \
         WEBHOOK_SECRET BRIDGE_REPO_ALLOWLIST; do
    if [[ -z "${!v:-}" ]]; then
        die "$v is not set (check secrets/.env.agent and .env.secrets)"
    fi
done

# WEBHOOK_SECRET entropy check
if [[ ${#WEBHOOK_SECRET} -lt 32 ]]; then
    warn "WEBHOOK_SECRET is only ${#WEBHOOK_SECRET} chars — recommend >= 32 for security"
    warn "Generate with: openssl rand -hex 32"
fi

log "environment: OK"

# ── 3. Python deps ──────────────────────────────────────────────────────────
if [[ "$validate_only" == "0" ]]; then
    if [[ -f "$DOTFILES/bridge/requirements.txt" ]]; then
        "$VENV/bin/pip" install --quiet -r "$DOTFILES/bridge/requirements.txt" >/dev/null
    else
        "$VENV/bin/pip" install --quiet fastapi uvicorn httpx pydantic >/dev/null
    fi
    log "python deps: OK"
else
    log "python deps: skipped (--validate)"
fi

# ── 3a. Bridge secrets file ─────────────────────────────────────────────────
# systemd EnvironmentFile= requires this file to exist before units start.
if [[ ! -f "$DOTFILES/secrets/.env.bridge" ]]; then
    if [[ "$validate_only" == "0" ]]; then
        if [[ -f "$DOTFILES/secrets/.env.bridge.example" ]]; then
            cp "$DOTFILES/secrets/.env.bridge.example" "$DOTFILES/secrets/.env.bridge"
            log "created secrets/.env.bridge from example — edit with your webhook secret"
        else
            printf 'WEBHOOK_SECRET=%s\n' "$WEBHOOK_SECRET" > "$DOTFILES/secrets/.env.bridge"
            log "created secrets/.env.bridge from current WEBHOOK_SECRET"
        fi
    else
        warn "secrets/.env.bridge does not exist — systemd units will fail to start"
    fi
else
    log "secrets/.env.bridge: exists"
fi

# ── 4. Runtime dirs ─────────────────────────────────────────────────────────
mkdir -p "$BRIDGE_ROOT/workspaces" "$BRIDGE_ROOT/logs"
touch "$BRIDGE_ROOT/logs/bridge.log"
log "runtime dirs: $BRIDGE_ROOT"

# ── 5. Systemd user units ──────────────────────────────────────────────────
if [[ "$validate_only" == "0" ]]; then
    SYSTEMD_USER="$HOME/.config/systemd/user"
    mkdir -p "$SYSTEMD_USER"

    if [[ -f "$DOTFILES/systemd/bridge-webhook.service" ]]; then
        ln -sfn "$DOTFILES/systemd/bridge-webhook.service" \
                "$SYSTEMD_USER/bridge-webhook.service"
    else
        warn "systemd/bridge-webhook.service not found — skipping"
    fi

    if [[ -f "$DOTFILES/systemd/bridge-worker@.service" ]]; then
        ln -sfn "$DOTFILES/systemd/bridge-worker@.service" \
                "$SYSTEMD_USER/bridge-worker@.service"
    else
        warn "systemd/bridge-worker@.service not found — skipping"
    fi

    systemctl --user daemon-reload 2>/dev/null || warn "systemctl daemon-reload failed"
    log "systemd units: linked"
else
    log "systemd units: skipped (--validate)"
fi

# ── 6. User linger ──────────────────────────────────────────────────────────
if command -v loginctl >/dev/null 2>&1; then
    if ! loginctl show-user "$USER" 2>/dev/null | grep -q 'Linger=yes'; then
        warn "User linger is off. Services will stop on logout."
        warn "Fix: sudo loginctl enable-linger $USER"
    fi
fi

# ── 7. Token mint smoke test ───────────────────────────────────────────────
if [[ "$validate_only" == "0" ]]; then
    if [[ -f "$DOTFILES/bin/verify-github-app-token.sh" ]]; then
        if bash "$DOTFILES/bin/verify-github-app-token.sh" >/dev/null 2>&1; then
            log "token mint: OK"
        else
            die "token mint smoke test failed — run 'ctrl verify-token' for detail"
        fi
    else
        warn "verify-github-app-token.sh not found — skipping mint test"
    fi
else
    log "token mint: skipped (--validate)"
fi

# ── Done ────────────────────────────────────────────────────────────────────
echo ""
if [[ "$validate_only" == "1" ]]; then
    log "Validation passed."
else
    log "Done. To start: ctrl bridge start"
    log "Configure GitHub App webhook URL to point at this host's reverse proxy."
fi
