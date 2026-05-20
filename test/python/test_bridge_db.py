"""Unit tests for bridge/db.py queue semantics.

Covers: enqueue idempotency, claim_next_job, mark_done/mark_failed,
bump_iteration, and requeue_stale_claims.

Run: python3 -m unittest discover -s test/python -p "test_bridge_db.py" -v
"""

import shutil
import sqlite3
import sys
import tempfile
import unittest
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent.parent
sys.path.insert(0, str(REPO_ROOT))

from bridge import db


def _make_db():
    """Create a temp DB and initialize schema. Returns (Path, tmp_dir_path)."""
    tmp_dir = tempfile.mkdtemp()
    tmp = Path(tmp_dir) / "test.db"
    db.init_db(tmp)
    return tmp, tmp_dir


def _enqueue_sample(conn: sqlite3.Connection, delivery_id: str = "d-1",
                    repo: str = "org/repo", pr: int = 42) -> bool:
    return db.enqueue(
        conn,
        delivery_id=delivery_id,
        event_type="pull_request_review",
        repo_full_name=repo,
        pr_number=pr,
        payload={"action": "submitted"},
    )


class TestEnqueue(unittest.TestCase):
    def setUp(self):
        self.db_path, self._tmpdir = _make_db()

    def tearDown(self):
        shutil.rmtree(self._tmpdir, ignore_errors=True)

    def test_enqueue_inserts_job(self):
        with db.connect(self.db_path) as conn:
            result = _enqueue_sample(conn)
            self.assertTrue(result)
            row = conn.execute("SELECT * FROM jobs WHERE delivery_id='d-1'").fetchone()
            self.assertIsNotNone(row)
            self.assertEqual(row["status"], "queued")
            self.assertEqual(row["pr_number"], 42)

    def test_enqueue_idempotent_on_delivery_id(self):
        with db.connect(self.db_path) as conn:
            first = _enqueue_sample(conn, delivery_id="d-dup")
            second = _enqueue_sample(conn, delivery_id="d-dup")
            self.assertTrue(first)
            self.assertFalse(second)
            count = conn.execute(
                "SELECT COUNT(*) as c FROM jobs WHERE delivery_id='d-dup'"
            ).fetchone()["c"]
            self.assertEqual(count, 1)

    def test_enqueue_creates_claim_key_row(self):
        with db.connect(self.db_path) as conn:
            _enqueue_sample(conn)
            row = conn.execute(
                "SELECT * FROM claim_keys WHERE claim_key='org/repo#42'"
            ).fetchone()
            self.assertIsNotNone(row)
            self.assertEqual(row["current_iteration"], 0)


class TestClaimNextJob(unittest.TestCase):
    def setUp(self):
        self.db_path, self._tmpdir = _make_db()

    def tearDown(self):
        shutil.rmtree(self._tmpdir, ignore_errors=True)

    def test_claim_returns_oldest_queued(self):
        with db.connect(self.db_path) as conn:
            _enqueue_sample(conn, delivery_id="d-1", pr=1)
            _enqueue_sample(conn, delivery_id="d-2", pr=2)
            job = db.claim_next_job(conn, worker_id="w-1")
            self.assertIsNotNone(job)
            self.assertEqual(job.delivery_id, "d-1")
            self.assertEqual(job.status, "claimed")
            self.assertEqual(job.worker_id, "w-1")

    def test_claim_skips_already_claimed(self):
        with db.connect(self.db_path) as conn:
            _enqueue_sample(conn, delivery_id="d-1", pr=1)
            _enqueue_sample(conn, delivery_id="d-2", pr=2)
            db.claim_next_job(conn, worker_id="w-1")
            job2 = db.claim_next_job(conn, worker_id="w-2")
            self.assertIsNotNone(job2)
            self.assertEqual(job2.delivery_id, "d-2")

    def test_claim_returns_none_when_empty(self):
        with db.connect(self.db_path) as conn:
            job = db.claim_next_job(conn, worker_id="w-1")
            self.assertIsNone(job)


class TestMarkDone(unittest.TestCase):
    def setUp(self):
        self.db_path, self._tmpdir = _make_db()

    def tearDown(self):
        shutil.rmtree(self._tmpdir, ignore_errors=True)

    def test_mark_done_sets_status(self):
        with db.connect(self.db_path) as conn:
            _enqueue_sample(conn)
            job = db.claim_next_job(conn, worker_id="w-1")
            db.mark_done(conn, job.id, tracking_issue_number=99)
            row = conn.execute("SELECT * FROM jobs WHERE id=?", (job.id,)).fetchone()
            self.assertEqual(row["status"], "done")
            self.assertEqual(row["tracking_issue_number"], 99)
            self.assertIsNotNone(row["finished_at"])


class TestMarkFailed(unittest.TestCase):
    def setUp(self):
        self.db_path, self._tmpdir = _make_db()

    def tearDown(self):
        shutil.rmtree(self._tmpdir, ignore_errors=True)

    def test_mark_failed_stores_error(self):
        with db.connect(self.db_path) as conn:
            _enqueue_sample(conn)
            job = db.claim_next_job(conn, worker_id="w-1")
            db.mark_failed(conn, job.id, "some error")
            row = conn.execute("SELECT * FROM jobs WHERE id=?", (job.id,)).fetchone()
            self.assertEqual(row["status"], "failed")
            self.assertEqual(row["error"], "some error")


class TestBumpIteration(unittest.TestCase):
    def setUp(self):
        self.db_path, self._tmpdir = _make_db()

    def tearDown(self):
        shutil.rmtree(self._tmpdir, ignore_errors=True)

    def test_bump_increments(self):
        with db.connect(self.db_path) as conn:
            _enqueue_sample(conn)
            v1 = db.bump_iteration(conn, "org/repo#42")
            v2 = db.bump_iteration(conn, "org/repo#42")
            self.assertEqual(v1, 1)
            self.assertEqual(v2, 2)

    def test_bump_creates_missing_claim_key(self):
        with db.connect(self.db_path) as conn:
            v = db.bump_iteration(conn, "new/repo#1")
            self.assertEqual(v, 1)


class TestRequeueStaleClaims(unittest.TestCase):
    def setUp(self):
        self.db_path, self._tmpdir = _make_db()

    def tearDown(self):
        shutil.rmtree(self._tmpdir, ignore_errors=True)

    def test_requeues_stale_jobs(self):
        with db.connect(self.db_path) as conn:
            _enqueue_sample(conn)
            job = db.claim_next_job(conn, worker_id="w-1")
            # Backdate the claimed_at to simulate a stale claim
            conn.execute(
                "UPDATE jobs SET claimed_at=datetime('now', '-3600 seconds') WHERE id=?",
                (job.id,),
            )
            count = db.requeue_stale_claims(conn, timeout_seconds=1800)
            self.assertEqual(count, 1)
            row = conn.execute("SELECT * FROM jobs WHERE id=?", (job.id,)).fetchone()
            self.assertEqual(row["status"], "queued")
            self.assertIsNone(row["worker_id"])

    def test_does_not_requeue_fresh_claims(self):
        with db.connect(self.db_path) as conn:
            _enqueue_sample(conn)
            db.claim_next_job(conn, worker_id="w-1")
            count = db.requeue_stale_claims(conn, timeout_seconds=1800)
            self.assertEqual(count, 0)


if __name__ == "__main__":
    unittest.main()
