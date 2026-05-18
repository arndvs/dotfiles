"""Bridge configuration loaded from environment.

Required vars come from ~/dotfiles/secrets/.env.agent (non-sensitive)
and ~/dotfiles/secrets/.env.secrets (sensitive). `.env.agent` is sourced
into interactive shells; `.env.secrets` is process-scoped only — injected
via systemd EnvironmentFile= or `run-with-secrets.sh`, never sourced
into the shell to avoid secret leakage.
"""
from __future__ import annotations

import os
from dataclasses import dataclass
from pathlib import Path


class ConfigError(RuntimeError):
    """Raised when required configuration is missing or invalid."""


@dataclass(frozen=True)
class Config:
    # GitHub App — optional for webhook-only mode (webhook never mints tokens).
    # Worker must call require_github_app() before using these.
    github_app_id: str | None
    github_app_installation_id: str | None
    # Note: GITHUB_APP_PRIVATE_KEY_B64 is NOT read here — mint script
    # reads it directly. Bridge processes never touch the private key.

    # Webhook
    webhook_secret: str
    webhook_port: int
    copilot_bot_login: str

    # Operational
    repo_allowlist: tuple[str, ...]
    max_iterations: int
    worker_count: int

    # Paths
    dotfiles_root: Path
    bridge_root: Path  # ~/bridge — runtime state, not in dotfiles
    workspaces_root: Path
    db_path: Path
    log_path: Path
    mint_script: Path  # bin/mint_github_app_token.py
    hud_script: Path  # bin/write-hud-state.sh

    @classmethod
    def from_env(cls) -> Config:
        def req(name: str) -> str:
            v = os.environ.get(name)
            if not v:
                raise ConfigError(f"Required env var missing: {name}")
            return v

        def opt(name: str, default: str) -> str:
            return os.environ.get(name, default)

        dotfiles = Path(opt("CTRLSHFT_HOME", str(Path.home() / "dotfiles")))
        bridge_root = Path(opt("BRIDGE_ROOT", str(Path.home() / "bridge")))

        # Filter empty strings from allowlist (fixes I-3: trailing commas)
        allowlist = tuple(
            r.strip() for r in opt("BRIDGE_REPO_ALLOWLIST", "").split(",") if r.strip()
        )
        if not allowlist:
            raise ConfigError("BRIDGE_REPO_ALLOWLIST is empty")

        # Validate bot login contains [bot] suffix (fixes I-1)
        bot_login = opt(
            "COPILOT_BOT_LOGIN", "copilot-pull-request-reviewer[bot]"
        )
        if not bot_login.endswith("[bot]"):
            raise ConfigError(
                f"COPILOT_BOT_LOGIN must end with [bot], got: {bot_login!r}"
            )

        return cls(
            github_app_id=os.environ.get("GITHUB_APP_ID") or None,
            github_app_installation_id=os.environ.get("GITHUB_APP_INSTALLATION_ID") or None,
            webhook_secret=req("WEBHOOK_SECRET"),
            webhook_port=int(opt("BRIDGE_PORT", "8765")),
            copilot_bot_login=bot_login,
            repo_allowlist=allowlist,
            max_iterations=int(opt("BRIDGE_MAX_ITERATIONS", "3")),
            # ^^ default 3 — low cap for MVP safety
            worker_count=int(opt("WORKER_COUNT", "1")),
            dotfiles_root=dotfiles,
            bridge_root=bridge_root,
            workspaces_root=bridge_root / "workspaces",
            db_path=bridge_root / "state.db",
            log_path=bridge_root / "logs" / "bridge.log",
            mint_script=dotfiles / "bin" / "mint_github_app_token.py",
            hud_script=dotfiles / "bin" / "write-hud-state.sh",
        )

    def require_github_app(self) -> tuple[str, str]:
        """Validate GitHub App credentials are present. Call from worker startup."""
        if not self.github_app_id or not self.github_app_installation_id:
            raise ConfigError(
                "GITHUB_APP_ID and GITHUB_APP_INSTALLATION_ID are required "
                "for the worker process (set in secrets/.env.secrets)"
            )
        return self.github_app_id, self.github_app_installation_id

    def ensure_dirs(self) -> None:
        self.workspaces_root.mkdir(parents=True, exist_ok=True)
        self.log_path.parent.mkdir(parents=True, exist_ok=True)
