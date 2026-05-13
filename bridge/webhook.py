"""GitHub webhook receiver.

Validates HMAC, filters by event type and actor, enqueues. Total
handler time target: <100ms. No GitHub API calls. No agent work.

MVP: Only pull_request_review events with state=changes_requested
from the Copilot bot are enqueued (fixes L-1 and L-2 from audit).
"""
from __future__ import annotations

import hashlib
import hmac
import json
import logging
from typing import Any

from fastapi import FastAPI, Header, HTTPException, Request, Response

from . import db, hud
from .config import Config

logger = logging.getLogger("bridge.webhook")
config = Config.from_env()
config.ensure_dirs()
db.init_db(config.db_path)

app = FastAPI(title="ctrl+shft bridge webhook", version="0.1.0")

# MVP: only pull_request_review events (fixes L-1 — drop review_comment)
ALLOWED_EVENTS = {"pull_request_review"}


def _verify_signature(body: bytes, header: str | None) -> bool:
    if not header or not header.startswith("sha256="):
        return False
    expected = (
        "sha256="
        + hmac.new(
            config.webhook_secret.encode(), body, hashlib.sha256
        ).hexdigest()
    )
    return hmac.compare_digest(expected, header)


@app.get("/healthz")
async def healthz() -> dict[str, str]:
    return {"status": "ok"}


@app.post("/webhook")
async def webhook(
    request: Request,
    x_github_event: str = Header(default=""),
    x_github_delivery: str = Header(default=""),
    x_hub_signature_256: str = Header(default=""),
) -> Response:
    body = await request.body()

    if not _verify_signature(body, x_hub_signature_256):
        logger.warning("HMAC mismatch (delivery=%s)", x_github_delivery)
        raise HTTPException(status_code=401, detail="bad signature")

    if x_github_event not in ALLOWED_EVENTS:
        return Response(status_code=204)

    try:
        payload: dict[str, Any] = json.loads(body)
    except json.JSONDecodeError:
        raise HTTPException(status_code=400, detail="invalid JSON")

    # Repo allowlist
    repo = (payload.get("repository") or {}).get("full_name")
    if repo not in config.repo_allowlist:
        hud.emit(
            config.hud_script,
            "bridge.webhook.rejected",
            project=repo or "unknown",
            delivery_id=x_github_delivery,
            reason="repo_not_in_allowlist",
        )
        return Response(status_code=204)

    # Actor filter — only Copilot bot reviews
    actor = (
        (payload.get("review") or {}).get("user", {}).get("login", "")
    )
    if actor != config.copilot_bot_login:
        return Response(status_code=204)

    # Review state filter — only changes_requested (fixes L-2)
    review_state = (payload.get("review") or {}).get("state", "")
    if review_state != "changes_requested":
        return Response(status_code=204)

    pr = payload.get("pull_request") or {}
    pr_number = pr.get("number")
    if not isinstance(pr_number, int):
        raise HTTPException(status_code=400, detail="missing pr_number")

    with db.connect(config.db_path) as conn:
        inserted = db.enqueue(
            conn,
            delivery_id=x_github_delivery,
            event_type=x_github_event,
            repo_full_name=repo,
            pr_number=pr_number,
            payload=payload,
        )

    if inserted:
        hud.emit(
            config.hud_script,
            "bridge.webhook.received",
            project=repo,
            workspace_id=f"{repo}#{pr_number}",
            delivery_id=x_github_delivery,
            pr_number=pr_number,
            event_type=x_github_event,
        )
        logger.info(
            "Enqueued delivery=%s repo=%s pr=%s event=%s",
            x_github_delivery,
            repo,
            pr_number,
            x_github_event,
        )
    else:
        logger.info("Duplicate delivery=%s — ignored", x_github_delivery)

    return Response(status_code=202)
