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

from .git_creds import git_credential_env
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
    """Build env dict with ephemeral git credential injection."""
    return git_credential_env(token)


def prepare(
    workspaces_root: Path,
    *,
    token: Token,
    repo_full_name: str,
    pr_number: int,
    head_ref: str,
    head_repo_full_name: str | None = None,
) -> Path:
    """Ensure a workspace exists and is synced to origin/<head_ref>.

    For fork PRs, head_repo_full_name should be the fork's full_name
    so the clone targets the repo where the branch actually exists.
    """
    workspaces_root.mkdir(parents=True, exist_ok=True)
    claim_key = f"{repo_full_name}#{pr_number}"
    path = workspace_path(workspaces_root, claim_key)
    env = _git_env(token)
    clone_repo = head_repo_full_name or repo_full_name
    clone_url = f"https://github.com/{clone_repo}.git"

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
            # Clean up partial clone directory to avoid stale state
            if path.exists():
                shutil.rmtree(path, ignore_errors=True)
            raise WorkspaceError(
                f"git clone failed for {repo_full_name} (exit {e.returncode})"
            )
    else:
        logger.info("Fetching %s in %s", head_ref, path)
        try:
            subprocess.run(
                [
                    "git", "-C", str(path),
                    "fetch", "origin",
                    f"refs/heads/{head_ref}:refs/remotes/origin/{head_ref}",
                ],
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
                timeout=60,
                env=env,
            )
        except subprocess.CalledProcessError as e:
            raise WorkspaceError(
                f"git fetch/reset failed for {repo_full_name} (exit {e.returncode})"
            )

    # Configure git identity for commits shft makes in this workspace.
    subprocess.run(
        ["git", "-C", str(path), "config", "user.name", "ctrl-shft bridge"],
        check=True,
        timeout=10,
    )
    subprocess.run(
        ["git", "-C", str(path), "config", "user.email", "bridge@ctrlshft.local"],
        check=True,
        timeout=10,
    )

    return path


def cleanup(workspaces_root: Path, claim_key: str) -> None:
    """Remove a workspace. Used when a PR is merged/closed."""
    path = workspace_path(workspaces_root, claim_key)
    if path.exists():
        shutil.rmtree(path)
