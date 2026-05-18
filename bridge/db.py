"""SQLite-backed job queue and audit log.

Schema is forward-compatible with Phase 2 multi-worker. The MVP claim
query ignores claim_key for serialization; Phase 2 adds a NOT IN filter
in claim_next_job. Everything else is identical.
"""
from __future__ import annotations

import json
import sqlite3
from contextlib import contextmanager
from dataclasses import dataclass
from pathlib import Path
from typing import Iterator, Optional


SCHEMA = """
CREATE TABLE IF NOT EXISTS jobs (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  delivery_id TEXT UNIQUE NOT NULL,
  event_type TEXT NOT NULL,
  repo_full_name TEXT NOT NULL,
  pr_number INTEGER NOT NULL,
  claim_key TEXT NOT NULL,
  payload_json TEXT NOT NULL,
  status TEXT NOT NULL DEFAULT 'queued',
  iteration INTEGER NOT NULL DEFAULT 0,
  tracking_issue_number INTEGER,
  workspace_path TEXT,
  worker_id TEXT,
  error TEXT,
  enqueued_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  claimed_at TIMESTAMP,
  finished_at TIMESTAMP
);

CREATE TABLE IF NOT EXISTS claim_keys (
  claim_key TEXT PRIMARY KEY,
  current_iteration INTEGER NOT NULL DEFAULT 0,
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_jobs_status_id ON jobs(status, id);
CREATE INDEX IF NOT EXISTS idx_jobs_claim_key ON jobs(claim_key, status);
CREATE INDEX IF NOT EXISTS idx_jobs_pr ON jobs(repo_full_name, pr_number);
"""


# Phase 2 toggle. When True, the claim query filters out any claim_key
# already held by another worker, enabling parallel processing across
# different PRs. MVP runs with this False.
PHASE_2_CONCURRENT_CLAIMS = False


@dataclass
class Job:
    id: int
    delivery_id: str
    event_type: str
    repo_full_name: str
    pr_number: int
    claim_key: str
    payload: dict
    status: str
    iteration: int
    tracking_issue_number: Optional[int]
    workspace_path: Optional[str]
    worker_id: Optional[str]

    @classmethod
    def from_row(cls, row: sqlite3.Row) -> Job:
        return cls(
            id=row["id"],
            delivery_id=row["delivery_id"],
            event_type=row["event_type"],
            repo_full_name=row["repo_full_name"],
            pr_number=row["pr_number"],
            claim_key=row["claim_key"],
            payload=json.loads(row["payload_json"]),
            status=row["status"],
            iteration=row["iteration"],
            tracking_issue_number=row["tracking_issue_number"],
            workspace_path=row["workspace_path"],
            worker_id=row["worker_id"],
        )


def init_db(db_path: Path) -> None:
    db_path.parent.mkdir(parents=True, exist_ok=True)
    with sqlite3.connect(db_path) as conn:
        conn.executescript(SCHEMA)
        conn.execute("PRAGMA journal_mode=WAL;")
        conn.execute("PRAGMA synchronous=NORMAL;")


@contextmanager
def connect(db_path: Path) -> Iterator[sqlite3.Connection]:
    conn = sqlite3.connect(db_path, isolation_level=None, timeout=30.0)
    conn.row_factory = sqlite3.Row
    try:
        yield conn
    finally:
        conn.close()


def enqueue(
    conn: sqlite3.Connection,
    *,
    delivery_id: str,
    event_type: str,
    repo_full_name: str,
    pr_number: int,
    payload: dict,
) -> bool:
    """Insert a job. Returns True if inserted, False if duplicate.

    Idempotent on delivery_id — GitHub redeliveries are silently ignored.
    """
    claim_key = f"{repo_full_name}#{pr_number}"
    cur = conn.execute(
        """
        INSERT OR IGNORE INTO jobs
          (delivery_id, event_type, repo_full_name, pr_number,
           claim_key, payload_json)
        VALUES (?, ?, ?, ?, ?, ?)
        """,
        (
            delivery_id,
            event_type,
            repo_full_name,
            pr_number,
            claim_key,
            json.dumps(payload),
        ),
    )
    if cur.rowcount > 0:
        # Ensure claim_key row exists for iteration tracking
        conn.execute(
            "INSERT OR IGNORE INTO claim_keys (claim_key) VALUES (?)",
            (claim_key,),
        )
    return cur.rowcount > 0


def claim_next_job(conn: sqlite3.Connection, worker_id: str) -> Optional[Job]:
    """Atomically claim the next queued job.

    MVP: FIFO across all queued jobs.
    Phase 2: skip jobs whose claim_key is already held by another worker.
    """
    conn.execute("BEGIN IMMEDIATE;")
    try:
        if PHASE_2_CONCURRENT_CLAIMS:
            row = conn.execute(
                """
                SELECT * FROM jobs
                  WHERE status = 'queued'
                    AND claim_key NOT IN (
                      SELECT claim_key FROM jobs WHERE status = 'claimed'
                    )
                  ORDER BY id
                  LIMIT 1
                """
            ).fetchone()
        else:
            row = conn.execute(
                """
                SELECT * FROM jobs
                  WHERE status = 'queued'
                  ORDER BY id
                  LIMIT 1
                """
            ).fetchone()

        if row is None:
            conn.execute("COMMIT;")
            return None

        conn.execute(
            """
            UPDATE jobs
              SET status='claimed',
                  claimed_at=CURRENT_TIMESTAMP,
                  worker_id=?
              WHERE id=?
            """,
            (worker_id, row["id"]),
        )
        conn.execute("COMMIT;")
        row = conn.execute(
            "SELECT * FROM jobs WHERE id=?", (row["id"],)
        ).fetchone()
        return Job.from_row(row)
    except Exception:
        conn.execute("ROLLBACK;")
        raise


def mark_done(
    conn: sqlite3.Connection,
    job_id: int,
    *,
    tracking_issue_number: Optional[int] = None,
    workspace_path: Optional[str] = None,
) -> None:
    conn.execute(
        """
        UPDATE jobs
          SET status='done',
              finished_at=CURRENT_TIMESTAMP,
              tracking_issue_number=COALESCE(?, tracking_issue_number),
              workspace_path=COALESCE(?, workspace_path)
          WHERE id=?
        """,
        (tracking_issue_number, workspace_path, job_id),
    )


def mark_failed(conn: sqlite3.Connection, job_id: int, error: str) -> None:
    conn.execute(
        """
        UPDATE jobs
          SET status='failed',
              finished_at=CURRENT_TIMESTAMP,
              error=?
          WHERE id=?
        """,
        (error[:4000], job_id),
    )


def bump_iteration(conn: sqlite3.Connection, claim_key: str) -> int:
    """Increment the per-PR iteration counter and return new value.

    Uses the dedicated claim_keys table (fixes H-4 from audit —
    iteration count is independent of job volume).

    Ensures the claim_key row exists first (UPSERT guard) so the
    function is robust to partial/older DB state.
    """
    conn.execute(
        "INSERT OR IGNORE INTO claim_keys (claim_key) VALUES (?)",
        (claim_key,),
    )
    conn.execute(
        """
        UPDATE claim_keys
          SET current_iteration = current_iteration + 1
          WHERE claim_key = ?
        """,
        (claim_key,),
    )
    row = conn.execute(
        "SELECT current_iteration FROM claim_keys WHERE claim_key = ?",
        (claim_key,),
    ).fetchone()
    return row["current_iteration"]
