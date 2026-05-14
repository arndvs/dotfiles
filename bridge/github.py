"""GitHub interactions: token mint, GraphQL, REST.

The mint script (~/dotfiles/bin/mint_github_app_token.py) owns the
private key. We shell out to it per job and never log the raw token.
"""
from __future__ import annotations

import json
import logging
import subprocess
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import Optional

import httpx

logger = logging.getLogger(__name__)


class GitHubError(RuntimeError):
    """Wraps GitHub API failures."""


@dataclass
class Token:
    value: str
    expires_at: str  # ISO 8601

    def __repr__(self) -> str:
        # Never accidentally log the token via repr.
        return f"Token(expires_at={self.expires_at!r}, value=<redacted>)"


def mint_token(mint_script: Path) -> Token:
    """Invoke the existing mint script and parse its JSON output.

    The script outputs JSON natively: {"token":"...","expires_at":"..."}
    No --json flag needed (fixes C-1 from audit — mint script has no
    --json flag, it always outputs JSON).
    """
    try:
        result = subprocess.run(
            [sys.executable, str(mint_script)],
            check=True,
            capture_output=True,
            text=True,
            timeout=30,
        )
    except subprocess.CalledProcessError as e:
        raise GitHubError(
            f"Token mint failed (exit {e.returncode}): {e.stderr.strip()}"
        )
    except subprocess.TimeoutExpired:
        raise GitHubError("Token mint timed out after 30s")

    try:
        data = json.loads(result.stdout)
    except json.JSONDecodeError:
        # Don't include raw stdout — may contain a partial token.
        raise GitHubError("Token mint produced invalid JSON")

    token = data.get("token")
    expires_at = data.get("expires_at")
    if not token or not expires_at:
        raise GitHubError("Token mint missing token or expires_at")

    return Token(value=token, expires_at=expires_at)


def _client(token: Token) -> httpx.Client:
    """Create an authenticated GitHub API client."""
    return httpx.Client(
        base_url="https://api.github.com",
        headers={
            "Authorization": f"Bearer {token.value}",
            "Accept": "application/vnd.github+json",
            "X-GitHub-Api-Version": "2022-11-28",
            "User-Agent": "ctrlshft-bridge/0.1",
        },
        timeout=30.0,
    )


@dataclass
class PrMetadata:
    head_ref: str
    head_repo_full_name: str  # fork-aware: may differ from base repo
    title: str
    html_url: str


def fetch_pr_metadata(
    token: Token, *, owner: str, repo: str, pr_number: int
) -> PrMetadata:
    """Fetch PR metadata via REST (fixes H-3 — no inline httpx usage).

    Returns head_repo_full_name so callers can clone from the fork repo
    when the PR originates from a fork (the head branch only exists there).
    """
    with _client(token) as client:
        r = client.get(f"/repos/{owner}/{repo}/pulls/{pr_number}")
        r.raise_for_status()
        data = r.json()
    head_repo = data["head"].get("repo") or {}
    return PrMetadata(
        head_ref=data["head"]["ref"],
        head_repo_full_name=head_repo.get("full_name", f"{owner}/{repo}"),
        title=data["title"],
        html_url=data["html_url"],
    )


GRAPHQL_UNRESOLVED_THREADS = """
query($owner:String!,$repo:String!,$num:Int!){
  repository(owner:$owner, name:$repo){
    pullRequest(number:$num){
      reviewThreads(first:100){
        nodes{
          id
          isResolved
          comments(first:1){
            nodes{
              id
              body
              path
              line
              diffHunk
              url
              author{ login }
            }
          }
        }
      }
    }
  }
}
"""


@dataclass
class UnresolvedThread:
    thread_id: str
    url: str
    path: Optional[str]
    line: Optional[int]
    body: str
    diff_hunk: Optional[str]
    author: str


def fetch_unresolved_copilot_threads(
    token: Token,
    *,
    owner: str,
    repo: str,
    pr_number: int,
    copilot_login: str,
) -> list[UnresolvedThread]:
    """Return unresolved review threads authored by Copilot."""
    # Strip [bot] suffix for GraphQL — GraphQL surfaces logins without it.
    copilot_bare = copilot_login.removesuffix("[bot]")

    with _client(token) as client:
        r = client.post(
            "/graphql",
            json={
                "query": GRAPHQL_UNRESOLVED_THREADS,
                "variables": {"owner": owner, "repo": repo, "num": pr_number},
            },
        )
        r.raise_for_status()
        data = r.json()

    if "errors" in data:
        raise GitHubError(f"GraphQL errors: {data['errors']}")

    threads = (
        data["data"]["repository"]["pullRequest"]["reviewThreads"]["nodes"]
    )
    out: list[UnresolvedThread] = []
    for t in threads:
        if t["isResolved"]:
            continue
        comments = t["comments"]["nodes"]
        if not comments:
            continue
        first = comments[0]
        author = first["author"]["login"] if first.get("author") else ""
        if author != copilot_bare:
            continue
        out.append(
            UnresolvedThread(
                thread_id=t["id"],
                url=first["url"],
                path=first.get("path"),
                line=first.get("line"),
                body=first["body"],
                diff_hunk=first.get("diffHunk"),
                author=author,
            )
        )
    return out


def find_tracking_issue(
    token: Token, *, owner: str, repo: str, marker: str
) -> Optional[dict]:
    """Search for an open tracking issue containing the marker."""
    q = f'repo:{owner}/{repo} is:issue is:open in:body "{marker}"'
    with _client(token) as client:
        r = client.get("/search/issues", params={"q": q})
        r.raise_for_status()
        data = r.json()
    items = data.get("items") or []
    return items[0] if items else None


def create_issue(
    token: Token,
    *,
    owner: str,
    repo: str,
    title: str,
    body: str,
    labels: list[str],
) -> int:
    with _client(token) as client:
        r = client.post(
            f"/repos/{owner}/{repo}/issues",
            json={"title": title, "body": body, "labels": labels},
        )
        r.raise_for_status()
        return r.json()["number"]


def update_issue(
    token: Token,
    *,
    owner: str,
    repo: str,
    issue_number: int,
    body: Optional[str] = None,
    state: Optional[str] = None,
    labels: Optional[list[str]] = None,
) -> None:
    payload: dict = {}
    if body is not None:
        payload["body"] = body
    if state is not None:
        payload["state"] = state
    if labels is not None:
        payload["labels"] = labels
    if not payload:
        return
    with _client(token) as client:
        r = client.patch(
            f"/repos/{owner}/{repo}/issues/{issue_number}", json=payload
        )
        r.raise_for_status()


def comment_on_issue(
    token: Token, *, owner: str, repo: str, issue_number: int, body: str
) -> None:
    with _client(token) as client:
        r = client.post(
            f"/repos/{owner}/{repo}/issues/{issue_number}/comments",
            json={"body": body},
        )
        r.raise_for_status()
