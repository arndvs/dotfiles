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
import signal
import subprocess
import sys
import time
import traceback

import httpx

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
        # Keep the job row's iteration in sync for observability
        conn.execute(
            "UPDATE jobs SET iteration = ? WHERE id = ?",
            (iteration_num, job.id),
        )
    emit("bridge.job.iteration", iteration=iteration_num)

    if iteration_num > cfg.max_iterations:
        emit("bridge.loop.cap_exceeded", iteration=iteration_num)
        if existing:
            try:
                github.add_label(
                    token,
                    owner=owner,
                    repo=repo_name,
                    issue_number=existing["number"],
                    label="agent-loop-exceeded",
                )
            except Exception:
                logger.warning("Failed to add agent-loop-exceeded label (may not exist)")
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
        try:
            tracking_number = github.create_issue(
                token,
                owner=owner,
                repo=repo_name,
                title=title_str,
                body=body_str,
                labels=issue.ISSUE_LABELS,
            )
        except httpx.HTTPStatusError as e:
            if e.response.status_code != 422:
                raise
            # Only retry without labels if the 422 is specifically about invalid labels
            try:
                err_data = e.response.json()
                errors = err_data.get("errors", [])
                is_label_error = any(
                    err.get("resource") == "Label"
                    or "label" in str(err.get("message", "")).lower()
                    for err in errors
                )
            except Exception:
                is_label_error = False
            if not is_label_error:
                raise
            logger.warning("create_issue with labels failed (422, label validation); retrying without labels")
            tracking_number = github.create_issue(
                token,
                owner=owner,
                repo=repo_name,
                title=title_str,
                body=body_str,
                labels=[],
            )
        emit("bridge.job.issue_created", tracking_issue_number=tracking_number)

    with db.connect(cfg.db_path) as conn:
        conn.execute(
            "UPDATE jobs SET tracking_issue_number=?, workspace_path=? WHERE id=?",
            (tracking_number, str(ws_path), job.id),
        )

    # 6. Exec shft afk 1 inside the workspace.
    emit("bridge.job.shft_invoked")
    shft_bin = str(cfg.dotfiles_root / "shft" / "shft")
    # Build a scrubbed environment for shft — only pass what it needs.
    # Do NOT forward the full os.environ (which includes .env.secrets).
    # Preserve existing PATH (may contain srt location from nvm/npm prefix)
    # and prepend ~/.local/bin for user-installed tools.
    existing_path = os.environ.get("PATH", "/usr/local/bin:/usr/bin:/bin")
    local_bin = os.path.expanduser("~/.local/bin")
    if local_bin not in existing_path.split(":"):
        path_val = f"{local_bin}:{existing_path}"
    else:
        path_val = existing_path
    env = {
        "HOME": os.environ.get("HOME", ""),
        "PATH": path_val,
        "TERM": os.environ.get("TERM", "dumb"),
        "LANG": os.environ.get("LANG", "en_US.UTF-8"),
        "USER": os.environ.get("USER", ""),
        "BRIDGE_WORKSPACE": str(ws_path),
        "GH_TOKEN": token.value,
        # Git credential injection (ephemeral, same pattern as workspace.py)
        "GIT_CONFIG_COUNT": "1",
        "GIT_CONFIG_KEY_0": (
            f"url.https://x-access-token:{token.value}@github.com/.insteadOf"
        ),
        "GIT_CONFIG_VALUE_0": "https://github.com/",
    }
    # Pass repo context so gh CLI targets the correct base repo (fork-safe)
    env["GH_REPO"] = repo

    try:
        proc = subprocess.Popen(
            [shft_bin, "afk", "1"],
            cwd=str(ws_path),
            env=env,
            start_new_session=True,
        )
        proc.wait(timeout=SHFT_RUN_TIMEOUT_SECONDS)
        emit("bridge.job.shft_completed", exit_code=proc.returncode)
        if proc.returncode != 0:
            raise RuntimeError(f"shft afk exited {proc.returncode}")
    except subprocess.TimeoutExpired:
        # Kill the entire process group to avoid orphaned agents/stale locks
        try:
            os.killpg(os.getpgid(proc.pid), signal.SIGTERM)
        except (ProcessLookupError, OSError):
            pass
        try:
            proc.wait(timeout=10)  # Allow graceful shutdown
        except subprocess.TimeoutExpired:
            # SIGTERM didn't work — escalate to SIGKILL
            try:
                os.killpg(os.getpgid(proc.pid), signal.SIGKILL)
            except (ProcessLookupError, OSError):
                pass
            proc.wait(timeout=5)
        emit("bridge.job.failed", reason="shft_timeout")
        raise RuntimeError("shft afk timed out")


def run(worker_id: str) -> None:
    cfg = Config.from_env()
    cfg.require_github_app()  # Worker needs GitHub App credentials — fail fast
    cfg.ensure_dirs()
    db.init_db(cfg.db_path)

    # On startup, requeue any jobs left in 'claimed' state from a previous
    # crash (lease expired — prevents permanently stuck jobs).
    with db.connect(cfg.db_path) as conn:
        requeued = db.requeue_stale_claims(conn)
        if requeued:
            logger.info("Requeued %d stale claimed job(s)", requeued)

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
