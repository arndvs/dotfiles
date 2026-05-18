"""HUD event emission.

Wraps ~/dotfiles/bin/write-hud-state.sh. Events are best-effort — if the
HUD daemon is down, emission fails silently and the worker continues.
"""
from __future__ import annotations

import json
import logging
import subprocess
from pathlib import Path
from typing import Optional

logger = logging.getLogger(__name__)


def emit(
    hud_script: Path,
    event: str,
    *,
    project: str,
    workspace_id: Optional[str] = None,
    worker_id: Optional[str] = None,
    delivery_id: Optional[str] = None,
    pr_number: Optional[int] = None,
    **extra,
) -> None:
    """Fire-and-forget HUD event.

    project is the GitHub repo full_name (the existing HUD per-project
    tab key). workspace_id and worker_id are Phase 2 forward-compat;
    HUD ignores them today, will use them later.
    """
    payload = {
        "type": event,
        "message": event,
        "project": project,
        **({"workspace_id": workspace_id} if workspace_id else {}),
        **({"worker_id": worker_id} if worker_id else {}),
        **({"delivery_id": delivery_id} if delivery_id else {}),
        **({"pr_number": pr_number} if pr_number else {}),
        **extra,
    }
    try:
        subprocess.run(
            ["bash", str(hud_script), "bridge-event"],
            input=json.dumps(payload),
            text=True,
            check=False,  # never fail the job on HUD issues
            timeout=2,
        )
    except Exception as e:
        logger.debug("HUD emit failed (non-fatal): %s", e)
