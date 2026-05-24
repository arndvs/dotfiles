#!/usr/bin/env bash
# _proxy_env.sh — Proxy env injection for shft invocations.
#
# Sourced by once.sh and afk.sh before invoking claude/srt.
# Sets ANTHROPIC_BASE_URL, ANTHROPIC_AUTH_TOKEN, CLAUDE_CODE_DISABLE_EXPERIMENTAL_BETAS
# when the proxy is enabled and healthy.
#
# Usage: source _proxy_env.sh "hitl"   (localhost for direct claude)
#        source _proxy_env.sh "afk"    (host.docker.internal for srt)
#
# Self-contained — reads ~/.shft/proxy.json directly.

_PROXY_MODE="${1:-hitl}"
_PROXY_STATE="$HOME/.shft/proxy.json"
_PROXY_DEFAULT_PORT=4000

# ── Minimal helpers (no dependency on shft or _lib.sh) ────────────────────────

_proxy_env_get() {
    local field="$1"
    if [[ ! -f "$_PROXY_STATE" ]]; then return; fi
    # Prefer jq (no shim risk), then python3/python, then grep fallback
    if command -v jq &>/dev/null; then
        jq -r --arg f "$field" '.[$f] // empty' "$_PROXY_STATE" 2>/dev/null || true
    else
        local _py_bin=""
        if command -v python3 &>/dev/null && python3 --version &>/dev/null; then _py_bin=python3;
        elif command -v python &>/dev/null && python --version &>/dev/null; then _py_bin=python;
        fi
        if [[ -n "$_py_bin" ]]; then
            "$_py_bin" - "$_PROXY_STATE" "$field" <<'PYEOF'
import json, sys
try:
    d = json.load(open(sys.argv[1]))
    v = d.get(sys.argv[2], '')
    if isinstance(v, bool): print(str(v).lower())
    else: print(v)
except: pass
PYEOF
        else
            grep -o "\"$field\":[^,}]*" "$_PROXY_STATE" 2>/dev/null | cut -d: -f2 | tr -d ' "' || true
        fi
    fi
}

# ── Check if proxy is enabled ─────────────────────────────────────────────────

_proxy_enabled=$(_proxy_env_get "enabled")

if [[ "$_proxy_enabled" != "true" ]]; then
    # Not enabled — nothing to do
    return 0 2>/dev/null || true
fi

# ── Proxy is enabled — verify daemon is running ──────────────────────────────

_proxy_pid=$(_proxy_env_get "pid")
_proxy_dir=$(_proxy_env_get "dir")
_proxy_port=$(_proxy_env_get "port")
_proxy_port="${_proxy_port:-$_PROXY_DEFAULT_PORT}"

# Verify daemon is running — PID check first, health endpoint fallback (MINGW64 kill -0 can't see Windows PIDs)
if [[ -z "$_proxy_pid" ]] || ! kill -0 "$_proxy_pid" 2>/dev/null; then
    if ! curl -sf --max-time 2 "http://localhost:${_proxy_port}/health/readiness" >/dev/null 2>&1; then
        echo "  ERROR: Proxy enabled but daemon not running." >&2
        echo "  Start it:  shft proxy start" >&2
        echo "  Or disable: shft proxy off" >&2
        exit 1
    fi
fi

# Health check
_proxy_check_host=$( (ip route 2>/dev/null || true) | awk '/default/{print $3; exit}'); _proxy_check_host="${_proxy_check_host:-localhost}"
if ! curl -sf --max-time 2 "http://${_proxy_check_host}:${_proxy_port}/health/readiness" > /dev/null 2>&1 \
  && ! curl -sf --max-time 2 "http://localhost:${_proxy_port}/health/readiness" > /dev/null 2>&1; then
    echo "  ERROR: Proxy daemon running but health check failed." >&2
    echo "  Restart: shft proxy stop && shft proxy start" >&2
    echo "  Logs:    tail -20 ~/.shft/proxy.log" >&2
    exit 1
fi

# Load master key from proxy dir's .env
if [[ -z "$_proxy_dir" ]]; then
    echo "  ERROR: Proxy directory not set. Run: shft proxy init <path>" >&2
    exit 1
fi
_proxy_env_file="$_proxy_dir/.env"
if [[ ! -f "$_proxy_env_file" ]]; then
    echo "  ERROR: Proxy .env not found at $_proxy_env_file" >&2
    exit 1
fi
_proxy_key=$(grep '^LITELLM_MASTER_KEY=' "$_proxy_env_file" | cut -d= -f2-)
if [[ -z "$_proxy_key" ]]; then
    echo "  ERROR: LITELLM_MASTER_KEY not found in $_proxy_env_file" >&2
    exit 1
fi

# Determine base URL based on mode
if [[ "$_PROXY_MODE" == "afk" ]]; then
    # AFK runs inside Docker via srt — need host-accessible address
    # Exception: MSYS/Windows runs claude directly (no Docker) so use localhost
    case "$(uname -s)" in
        MINGW*|MSYS*|CYGWIN*) _proxy_host="localhost" ;;
        Darwin*)              _proxy_host="host.docker.internal" ;;
        *)                    _proxy_host=$(ip route 2>/dev/null | awk '/default/{print $3; exit}'); _proxy_host="${_proxy_host:-172.17.0.1}" ;;
    esac
else
    _proxy_host="localhost"
fi

# Export for claude / srt
export ANTHROPIC_BASE_URL="http://${_proxy_host}:${_proxy_port}"
export ANTHROPIC_AUTH_TOKEN="$_proxy_key"
export ANTHROPIC_MODEL="claude-opus-4-6"
export CLAUDE_CODE_DISABLE_EXPERIMENTAL_BETAS=1
export CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1

echo "  Routing: Copilot proxy (${_proxy_host}:${_proxy_port})"

# Clean up locals
unset _PROXY_MODE _PROXY_STATE _PROXY_DEFAULT_PORT
unset _proxy_enabled _proxy_pid _proxy_dir _proxy_port
unset _proxy_env_file _proxy_key _proxy_host _proxy_check_host
