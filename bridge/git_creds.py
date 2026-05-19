"""Shared git credential env injection.

Builds a process env dict with ephemeral GIT_CONFIG_COUNT/KEY/VALUE
vars so git uses an x-access-token URL rewrite — no token ever touches
.git/config or a remote URL stored on disk.
"""
from __future__ import annotations

import os

from .github import Token

# Only forward safe, non-secret env vars to git subprocesses.
_SAFE_ENV_VARS = ("HOME", "PATH", "TERM", "LANG", "USER", "LOGNAME", "SHELL")


def git_credential_env(token: Token) -> dict[str, str]:
    """Return a scrubbed env with ephemeral git credential config.

    Only forwards safe vars — does NOT spread os.environ to avoid
    leaking secrets from the worker's EnvironmentFile.
    """
    env = {k: os.environ[k] for k in _SAFE_ENV_VARS if k in os.environ}
    env.update({
        "GIT_CONFIG_COUNT": "1",
        "GIT_CONFIG_KEY_0": (
            f"url.https://x-access-token:{token.value}@github.com/.insteadOf"
        ),
        "GIT_CONFIG_VALUE_0": "https://github.com/",
    })
    return env
