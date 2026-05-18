"""Shared git credential env injection.

Builds a process env dict with ephemeral GIT_CONFIG_COUNT/KEY/VALUE
vars so git uses an x-access-token URL rewrite — no token ever touches
.git/config or a remote URL stored on disk.
"""
from __future__ import annotations

import os

from .github import Token


def git_credential_env(token: Token) -> dict[str, str]:
    """Return os.environ merged with ephemeral git credential config."""
    return {
        **os.environ,
        "GIT_CONFIG_COUNT": "1",
        "GIT_CONFIG_KEY_0": (
            f"url.https://x-access-token:{token.value}@github.com/.insteadOf"
        ),
        "GIT_CONFIG_VALUE_0": "https://github.com/",
    }
