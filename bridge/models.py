"""Pydantic models for inbound webhook payloads.

We model only the fields we actually read. GitHub's payloads are large;
exhaustive modeling is anti-helpful (every API change becomes a bug).

NOTE: head_ref is intentionally omitted from PullRequest — it's fetched
via REST in the worker (see github.fetch_pr_metadata). The webhook
payload nests it as pull_request.head.ref which doesn't map cleanly
to a flat field.
"""
from __future__ import annotations

from pydantic import BaseModel


class User(BaseModel):
    login: str


class Repository(BaseModel):
    full_name: str


class PullRequest(BaseModel):
    number: int
    title: str
    html_url: str


class Review(BaseModel):
    user: User
    html_url: str
    state: str = ""


class PullRequestReviewEvent(BaseModel):
    action: str
    review: Review
    pull_request: PullRequest
    repository: Repository
