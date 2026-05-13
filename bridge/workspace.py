"""Per-PR workspace lifecycle.

A workspace is ~/bridge/workspaces/<owner>-<repo>-pr<num>/, a
single-branch clone of the PR's head. Reused across iterations for the
same PR; recreated if missing.

Security: Git credentials are injected via ephemeral GIT_CONFIG_COUNT
env vars (fixes S-1 from audit — no token ever touches .git/config).
"""
from __future__ import annotations

import logging
import os
import shutil
import subprocess
from pathlib import Path

from .github import Token

logger = logging.getLogger(__name__)


class WorkspaceError(RuntimeError):
    pass


def workspace_path(workspaces_root: Path, claim_key: str) -> Path:
    """Convert claim_key to a filesystem-safe path."""
    # claim_key is "owner/repo#42"; normalize for filesystem.
    safe = claim_key.replace("/", "-").replace("#", "-pr")
    return workspaces_root / safe


def _git_env(token: Token) -> dict[str, str]:
    """Build env dict with ephemeral git credential injection.

    Uses GIT_CONFIG_COUNT/GIT_CONFIG_KEY_N/GIT_CONFIG_VALUE_N to inject
    credentials without ever writing them to .git/config or the remote URL.
    """
    return {
        **os.environ,
        "GIT_CONFIG_COUNT": "1",
        "GIT_CONFIG_KEY_0": "url.https://x-access-token:{}@github.com/.insteadOf".format(
            token.value
        ),
        "GIT_CONFIG_VALUE_0": "https://github.com/",
    }


def prepare(
    workspaces_root: Path,
    *,
    token: Token,
    repo_full_name: str,
    pr_number: int,
    head_ref: str,
) -> Path:
    """Ensure a workspace exists and is synced to origin/<head_ref>."""
    workspaces_root.mkdir(parents=True, exist_ok=True)
    claim_key = f"{repo_full_name}#{pr_number}"
    path = workspace_path(workspaces_root, claim_key)
    env = _git_env(token)
    clone_url = f"https://github.com/{repo_full_name}.git"

    if not path.exists():
        logger.info("Cloning %s @ %s into %s", repo_full_name, head_ref, path)
        try:
            subprocess.run(
                [
                    "git", "clone",
                    "--branch", head_ref,
                    "--single-branch",
                    clone_url,
                    str(path),
                ],
                check=True,
                capture_output=True,
                text=True,
                timeout=300,
                env=env,
            )
        except subprocess.CalledProcessError as e:
            raise WorkspaceError(
                f"git clone failed for {repo_full_name} (exit {e.returncode})"
            )
    else:
        logger.info("Fetching %s in %s", head_ref, path)
        try:
            subprocess.run(
                ["git", "-C", str(path), "fetch", "origin", head_ref],
                check=True,
                capture_output=True,
                text=True,
                timeout=120,
                env=env,
            )
            subprocess.run(
                [
                    "git", "-C", str(path),
                    "reset", "--hard", f"origin/{head_ref}",
                ],
                check=True,
            )
        except subprocess.CalledProcessError as e:
            raise WorkspaceError(
                f"git fetch/reset failed for {repo_full_name} (exit {e.returncode})"
            )

    # Configure git identity for commits shft makes in this workspace.
    subprocess.run(
        ["git", "-C", str(path), "config", "user.name", "ctrl-shft bridge"],
        check=True,
    )
    subprocess.run(
        ["git", "-C", str(path), "config", "user.email", "bridge@ctrlshft.local"],
        check=True,
    )

    return path


def cleanup(workspaces_root: Path, claim_key: str) -> None:
    """Remove a workspace. Used when a PR is merged/closed."""
    path = workspace_path(workspaces_root, claim_key)
    if path.exists():
        shutil.rmtree(path)
