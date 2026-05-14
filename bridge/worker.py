"""Bridge worker — the persistent process.

Polls the SQLite queue, claims jobs, processes them, execs shft afk 1
as a subprocess. systemd template unit invokes this with WORKER_ID set
to the instance number.

MVP constraints (documented, accepted):
- Global lockfile at /tmp/shft-afk.lock limits to single concurrent
  shft invocation across all bridge + manual runs.
- Global ~/dotfiles/working/ means HUD events don't distinguish bridge
  vs manual sessions. Phase 2 follows ADR-NNNN for per-workspace isolation.
"""
from __future__ import annotations

import logging
import os
import subprocess
import sys
import time
import traceback

from . import db, github, hud, issue, workspace
from .config import Config

logger = logging.getLogger("bridge.worker")

POLL_INTERVAL_SECONDS = 2.0
SHFT_RUN_TIMEOUT_SECONDS = 60 * 30  # 30 min hard cap per shft invocation


def _process_job(cfg: Config, job: db.Job, worker_id: str) -> None:
    repo = job.repo_full_name
    owner, repo_name = repo.split("/", 1)
    workspace_id = job.claim_key

    def emit(event: str, **extra) -> None:
        hud.emit(
            cfg.hud_script,
            event,
            project=repo,
            workspace_id=workspace_id,
            worker_id=worker_id,
            delivery_id=job.delivery_id,
            pr_number=job.pr_number,
            **extra,
        )

    emit("bridge.job.claimed")

    # 1. Mint token.
    token = github.mint_token(cfg.mint_script)
    emit("bridge.job.token_minted", expires_at=token.expires_at)

    # 2. Fetch unresolved threads.
    threads = github.fetch_unresolved_copilot_threads(
        token,
        owner=owner,
        repo=repo_name,
        pr_number=job.pr_number,
        copilot_login=cfg.copilot_bot_login,
    )
    emit("bridge.job.threads_found", count=len(threads))

    marker_str = issue.marker(repo, job.pr_number)
    existing = github.find_tracking_issue(
        token, owner=owner, repo=repo_name, marker=marker_str
    )

    # 3. Decide and act.
    if not threads and existing:
        github.update_issue(
            token,
            owner=owner,
            repo=repo_name,
            issue_number=existing["number"],
            state="closed",
        )
        github.comment_on_issue(
            token,
            owner=owner,
            repo=repo_name,
            issue_number=existing["number"],
            body="All Copilot review threads resolved. Closing.",
        )
        emit(
            "bridge.job.issue_closed",
            tracking_issue_number=existing["number"],
        )
        return

    if not threads:
        emit("bridge.job.done", reason="no_threads_no_issue")
        return

    # Iteration cap (uses claim_keys table — fixes H-4).
    with db.connect(cfg.db_path) as conn:
        iteration_num = db.bump_iteration(conn, job.claim_key)
    emit("bridge.job.iteration", iteration=iteration_num)

    if iteration_num > cfg.max_iterations:
        emit("bridge.loop.cap_exceeded", iteration=iteration_num)
        if existing:
            github.update_issue(
                token,
                owner=owner,
                repo=repo_name,
                issue_number=existing["number"],
                labels=["copilot-review", "agent-loop-exceeded"],
            )
            github.comment_on_issue(
                token,
                owner=owner,
                repo=repo_name,
                issue_number=existing["number"],
                body=(
                    f"Iteration cap ({cfg.max_iterations}) exceeded. "
                    "Stopping autonomous loop. Human review required."
                ),
            )
        return

    # 4. Prepare workspace — fetch PR metadata via REST helper (fixes H-3).
    pr_meta = github.fetch_pr_metadata(
        token, owner=owner, repo=repo_name, pr_number=job.pr_number
    )
    review_event_url = job.payload.get("review", {}).get("html_url", "")

    ws_path = workspace.prepare(
        cfg.workspaces_root,
        token=token,
        repo_full_name=repo,
        pr_number=job.pr_number,
        head_ref=pr_meta.head_ref,
        head_repo_full_name=pr_meta.head_repo_full_name,
    )
    emit("bridge.workspace.prepared", path=str(ws_path))

    # 5. Upsert tracking issue.
    title_str = issue.title(job.pr_number, pr_meta.title)
    body_str = issue.body(
        repo_full_name=repo,
        pr_number=job.pr_number,
        pr_title=pr_meta.title,
        pr_url=pr_meta.html_url,
        branch=pr_meta.head_ref,
        review_event_url=review_event_url,
        threads=threads,
    )

    if existing:
        github.update_issue(
            token,
            owner=owner,
            repo=repo_name,
            issue_number=existing["number"],
            body=body_str,
        )
        tracking_number = existing["number"]
        emit("bridge.job.issue_updated", tracking_issue_number=tracking_number)
    else:
        tracking_number = github.create_issue(
            token,
            owner=owner,
            repo=repo_name,
            title=title_str,
            body=body_str,
            labels=issue.ISSUE_LABELS,
        )
        emit("bridge.job.issue_created", tracking_issue_number=tracking_number)

    with db.connect(cfg.db_path) as conn:
        conn.execute(
            "UPDATE jobs SET tracking_issue_number=?, workspace_path=? WHERE id=?",
            (tracking_number, str(ws_path), job.id),
        )

    # 6. Exec shft afk 1 inside the workspace.
    emit("bridge.job.shft_invoked")
    env = os.environ.copy()
    env["BRIDGE_WORKSPACE"] = str(ws_path)
    env["GH_TOKEN"] = token.value  # shft uses gh CLI internally
    # Inject git credentials via env (matches workspace.py pattern)
    env["GIT_CONFIG_COUNT"] = "1"
    env["GIT_CONFIG_KEY_0"] = (
        f"url.https://x-access-token:{token.value}@github.com/.insteadOf"
    )
    env["GIT_CONFIG_VALUE_0"] = "https://github.com/"

    try:
        proc = subprocess.run(
            ["shft", "afk", "1"],
            cwd=str(ws_path),
            env=env,
            timeout=SHFT_RUN_TIMEOUT_SECONDS,
            check=False,
        )
        emit("bridge.job.shft_completed", exit_code=proc.returncode)
        if proc.returncode != 0:
            raise RuntimeError(f"shft afk exited {proc.returncode}")
    except subprocess.TimeoutExpired:
        emit("bridge.job.failed", reason="shft_timeout")
        raise RuntimeError("shft afk timed out")


def run(worker_id: str) -> None:
    cfg = Config.from_env()
    cfg.ensure_dirs()
    db.init_db(cfg.db_path)

    logger.info(
        "Worker %s started, polling every %.1fs",
        worker_id,
        POLL_INTERVAL_SECONDS,
    )

    while True:
        try:
            with db.connect(cfg.db_path) as conn:
                job = db.claim_next_job(conn, worker_id)
        except Exception as e:
            logger.exception("Claim failed: %s", e)
            time.sleep(POLL_INTERVAL_SECONDS)
            continue

        if job is None:
            time.sleep(POLL_INTERVAL_SECONDS)
            continue

        try:
            _process_job(cfg, job, worker_id)
            with db.connect(cfg.db_path) as conn:
                db.mark_done(conn, job.id)
        except Exception as e:
            tb = traceback.format_exc()
            logger.error("Job %s failed: %s\n%s", job.id, e, tb)
            with db.connect(cfg.db_path) as conn:
                db.mark_failed(conn, job.id, tb)
            hud.emit(
                cfg.hud_script,
                "bridge.job.failed",
                project=job.repo_full_name,
                workspace_id=job.claim_key,
                worker_id=worker_id,
                delivery_id=job.delivery_id,
                pr_number=job.pr_number,
                error=str(e),
            )


if __name__ == "__main__":
    worker_id = (
        os.environ.get("WORKER_ID")
        or (sys.argv[1] if len(sys.argv) > 1 else "1")
    )
    logging.basicConfig(
        level=logging.INFO,
        format="%(asctime)s %(name)s %(levelname)s %(message)s",
    )
    run(worker_id)
