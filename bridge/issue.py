"""Tracking issue body construction.

The body is the agent's working surface. The bridge writes the
unresolved threads and standard instructions; do-work reads them and
handles per-thread judgment.
"""
from __future__ import annotations

from .github import UnresolvedThread

ISSUE_LABELS = ["afk", "copilot-review"]


def marker(repo_full_name: str, pr_number: int) -> str:
    return f"<!-- copilot-bridge:pr-{repo_full_name}#{pr_number} -->"


MAX_TITLE_LEN = 256
MAX_BODY_LEN = 65000


def title(pr_number: int, pr_title: str) -> str:
    raw = f"[copilot-review] PR #{pr_number}: {pr_title}"
    if len(raw) > MAX_TITLE_LEN:
        return raw[: MAX_TITLE_LEN - 1] + "\u2026"
    return raw


def body(
    *,
    repo_full_name: str,
    pr_number: int,
    pr_url: str,
    branch: str,
    review_event_url: str,
    threads: list[UnresolvedThread],
) -> str:
    parts = [
        "## Source",
        "",
        f"PR: {pr_url}",
        f"Branch: `{branch}`",
        f"Review event: {review_event_url}",
        "",
        "## Unresolved Copilot review threads",
        "",
    ]
    for i, t in enumerate(threads, 1):
        location = (
            f"{t.path}:{t.line}" if t.path and t.line is not None else "(no location)"
        )
        parts.append(f"### Thread {i} — {location}")
        parts.append(f"**URL:** {t.url}")
        parts.append("")
        parts.append(t.body)
        if t.diff_hunk:
            parts.append("")
            parts.append("```diff")
            parts.append(t.diff_hunk)
            parts.append("```")
        parts.append("")

    parts.extend(
        [
            "## Instructions for the agent",
            "",
            "Resolve each unresolved thread above using normal `do-work` flow.",
            "For each thread:",
            "",
            "1. Read the comment in context of the diff hunk and surrounding code.",
            "2. Decide: AFK-able fix, or escalate as `hitl`?",
            "3. If AFK: implement, commit atomically (one commit per thread,",
            "   scoped to the thread's file/line). Push to the PR branch, then",
            "   reply to the thread with `Fixed in <sha>` and resolve it via GraphQL.",
            "4. If HITL: remove the `afk` label from this issue, add `hitl`,",
            "   post a summary comment on this issue explaining which thread(s)",
            "   and why.",
            "5. When all threads handled, close this issue.",
            "",
            marker(repo_full_name, pr_number),
        ]
    )
    result = "\n".join(parts)
    if len(result) > MAX_BODY_LEN:
        mkr = marker(repo_full_name, pr_number)
        # Preserve the marker at the end so the bridge can find this issue.
        budget = MAX_BODY_LEN - len(mkr) - 60
        result = (
            result[:budget]
            + "\n\n---\n*Body truncated (GitHub limit).*\n\n"
            + mkr
        )
    return result
