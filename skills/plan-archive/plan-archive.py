#!/usr/bin/env python3
"""Archive plan-mode files in ~/.claude/plans/ by linking them to merged PRs.

Plans accumulate every time the user enters plan mode (each ExitPlanMode writes
a new file). This script groups plans by the PR that executed them and moves
the bundle into ~/.claude/plans/archive/by-pr/PR-<num>-<branch-slug>/, with a
_meta.yaml linking back to the PR + Linear tickets + commits.

Modes:
  --mode=archive-pr --pr=<num>      Archive plans matching one merged PR
  --mode=backfill --since=<spec>    Scan recent merged PRs and archive matches
  --mode=audit                      List active plans + flag orphans

All modes accept --dry-run (default).  Add --execute to actually move files.

Lifted from claude-mechanisms-tools/skills/plan-archive/plan-archive.py
with plan_files_lib inlined (no second consumer in ctrlshft yet).
"""

from __future__ import annotations

import argparse
import json
import os
import re
import shutil
import subprocess
import sys
from datetime import datetime, timedelta, timezone
from pathlib import Path

# ============================================================
# Inlined from lib/plan_files_lib.py
# ============================================================

PLANS_DIR = Path.home() / ".claude" / "plans"


def _detect_repo_prefixes() -> list[str]:
    """Return path prefixes treated as repo-root markers when stripping to repo-relative."""
    env = os.environ.get("CLAUDE_PLAN_REPO_PREFIXES", "").strip()
    if env:
        return [p.strip() for p in env.split(",") if p.strip()]

    try:
        result = subprocess.run(
            ["git", "rev-parse", "--show-toplevel"],
            capture_output=True, text=True, timeout=2,
        )
        if result.returncode == 0:
            toplevel = result.stdout.strip()
            if toplevel:
                home = str(Path.home())
                prefixes = [toplevel + "/"]
                if toplevel.startswith(home + "/"):
                    prefixes.append("~/" + toplevel[len(home) + 1:] + "/")
                return prefixes
    except (subprocess.TimeoutExpired, FileNotFoundError, OSError):
        pass

    return []


REPO_PREFIXES = _detect_repo_prefixes()


def extract_plan_files(plan_text: str) -> tuple[list[str], list[str], list[str]]:
    """Extract file paths from the ## Files section of a plan.

    Returns (repo_files, external_files, conditional_files).
    """
    lines = plan_text.split("\n")
    in_files_section = False
    repo_files: list[str] = []
    external_files: list[str] = []
    conditional_files: list[str] = []

    for line in lines:
        if re.match(r"^#{2,3}\s+Files", line.strip()):
            in_files_section = True
            continue
        if in_files_section and re.match(r"^#{2}\s+(?!#)", line.strip()):
            break
        if in_files_section and re.match(r"^#{3}\s+", line.strip()):
            heading_text = re.sub(r"^#{3}\s+", "", line.strip())
            file_category_patterns = [
                r"(?i)code", r"(?i)spec", r"(?i)bundled", r"(?i)doc",
                r"(?i)mechanism", r"(?i)CI", r"(?i)CLAUDE", r"(?i)config",
            ]
            if not any(re.search(p, heading_text) for p in file_category_patterns):
                break
        if not in_files_section:
            continue

        if re.search(r"\*\*Run:\*\*", line):
            continue

        path_match = re.search(r'\*\*`([^`]+)`\*\*', line)
        if not path_match:
            path_match = re.search(r'`(~?/[^`]+)`', line)
        if not path_match:
            continue

        raw_path = path_match.group(1).strip()

        if re.search(r'\((?:if |conditional|optional)', line, re.IGNORECASE):
            conditional_files.append(raw_path)
            continue

        if any(raw_path.startswith(p) for p in REPO_PREFIXES):
            repo_files.append(raw_path)
        elif raw_path.startswith("~/") or raw_path.startswith("/"):
            external_files.append(raw_path)
        else:
            repo_files.append(raw_path)

    return repo_files, external_files, conditional_files


def normalize_to_repo_relative(path_str: str) -> str:
    """Normalize a file path to be repo-relative by stripping any known REPO_PREFIXES."""
    expanded = path_str
    for prefix in REPO_PREFIXES:
        if expanded.startswith(prefix):
            expanded = expanded[len(prefix):]
            break
    expanded = expanded.lstrip("/")
    return expanded


def find_plans_matching_diff(
    diff_files: set[str],
    plans_dir: Path | None = None,
    min_overlap: int = 1,
) -> list[tuple[int, float, Path]]:
    """Find every plan whose ## Files section overlaps diff_files by >= min_overlap.

    Returns a list of (overlap, mtime, plan_path) tuples, sorted by overlap desc
    then mtime desc.
    """
    if plans_dir is None:
        plans_dir = PLANS_DIR
    if not plans_dir.exists():
        return []
    candidates: list[tuple[int, float, Path]] = []
    for plan_file in plans_dir.glob("*.md"):
        try:
            plan_text = plan_file.read_text()
        except Exception:
            continue
        repo_files, _, _ = extract_plan_files(plan_text)
        if not repo_files:
            continue
        plan_rel = {normalize_to_repo_relative(p) for p in repo_files}
        overlap = len(plan_rel & diff_files)
        if overlap >= min_overlap:
            candidates.append((overlap, plan_file.stat().st_mtime, plan_file))
    candidates.sort(key=lambda x: (-x[0], -x[1]))
    return candidates


# ============================================================
# Plan archive logic
# ============================================================

ARCHIVE_DIR = PLANS_DIR / "archive"
BY_PR_DIR = ARCHIVE_DIR / "by-pr"
ORPHAN_DIR = ARCHIVE_DIR / "orphan"

LINEAR_RE = re.compile(r"\bCC-(\d+)\b")


def _pr_url_template() -> str:
    """Return GitHub PR URL template with `{number}` placeholder."""
    env = os.environ.get("CLAUDE_PLAN_PR_URL_TEMPLATE", "").strip()
    if env:
        return env
    try:
        result = subprocess.run(
            ["git", "remote", "get-url", "origin"],
            capture_output=True, text=True, timeout=2,
        )
        if result.returncode == 0:
            url = result.stdout.strip()
            m = re.match(r"git@github\.com:([^/]+)/([^/.]+)(?:\.git)?$", url)
            if not m:
                m = re.match(r"https?://github\.com/([^/]+)/([^/.]+?)(?:\.git)?/?$", url)
            if m:
                owner, repo = m.group(1), m.group(2)
                return f"https://github.com/{owner}/{repo}/pull/{{number}}"
    except (subprocess.TimeoutExpired, FileNotFoundError, OSError):
        pass
    return "pull/{number}"


def info(msg: str) -> None:
    print(msg, flush=True)


def slugify_branch(branch: str) -> str:
    """Make a branch name filesystem-safe."""
    return re.sub(r"[^A-Za-z0-9._-]+", "-", branch).strip("-")


def parse_since(spec: str) -> datetime:
    """Parse `--since=30d` / `--since=2w` etc into a UTC cutoff datetime."""
    m = re.match(r"^(\d+)([dwhm])$", spec.strip())
    if not m:
        raise ValueError(f"Invalid --since: {spec}. Use e.g. 30d, 2w, 12h.")
    n = int(m.group(1))
    unit = m.group(2)
    delta = {
        "d": timedelta(days=n),
        "w": timedelta(weeks=n),
        "h": timedelta(hours=n),
        "m": timedelta(minutes=n),
    }[unit]
    return datetime.now(timezone.utc) - delta


def gh_json(args: list[str]) -> object:
    """Run `gh` with --json args, return parsed JSON. Returns None on failure."""
    try:
        out = subprocess.run(
            args, check=True, capture_output=True, text=True, timeout=30
        )
        return json.loads(out.stdout)
    except (subprocess.CalledProcessError, json.JSONDecodeError, subprocess.TimeoutExpired) as e:
        info(f"warn: gh call failed ({' '.join(args)}): {e}")
        return None


def gh_text(args: list[str]) -> str:
    """Run `gh` and return stdout text. Returns '' on failure."""
    try:
        out = subprocess.run(
            args, check=True, capture_output=True, text=True, timeout=30
        )
        return out.stdout
    except (subprocess.CalledProcessError, subprocess.TimeoutExpired) as e:
        info(f"warn: gh call failed ({' '.join(args)}): {e}")
        return ""


def fetch_pr_data(pr_number: int, repo: str | None = None) -> dict | None:
    """Fetch PR metadata + diff filenames."""
    args = ["gh", "pr", "view", str(pr_number), "--json", "number,title,headRefName,body,mergedAt,mergeCommit"]
    if repo:
        args += ["--repo", repo]
    data = gh_json(args)
    if not data:
        return None

    diff_args = ["gh", "pr", "diff", str(pr_number), "--name-only"]
    if repo:
        diff_args += ["--repo", repo]
    diff_text = gh_text(diff_args)
    files = {line.strip() for line in diff_text.splitlines() if line.strip()}

    body = data.get("body") or ""
    log_args = ["gh", "pr", "view", str(pr_number), "--json", "commits"]
    if repo:
        log_args += ["--repo", repo]
    commits_data = gh_json(log_args) or {}
    commit_msgs = "\n".join(
        c.get("messageHeadline", "") + "\n" + c.get("messageBody", "")
        for c in (commits_data.get("commits") or [])
    )

    haystack = body + "\n" + commit_msgs
    linear = sorted(set(f"CC-{m}" for m in LINEAR_RE.findall(haystack)))

    return {
        "number": data["number"],
        "title": data["title"],
        "branch": data["headRefName"],
        "body": body,
        "mergedAt": data.get("mergedAt"),
        "mergeCommit": (data.get("mergeCommit") or {}).get("oid", ""),
        "files": files,
        "linear": linear,
    }


def write_meta_yaml(target_dir: Path, pr: dict, plan_filenames: list[str], cross_refs: list[int] | None = None) -> None:
    """Write _meta.yaml inside target_dir using a hand-rolled YAML emitter (no PyYAML dep)."""
    cross_refs = cross_refs or []
    lines = [
        "pr:",
        f"  number: {pr['number']}",
        f"  url: {_pr_url_template().format(number=pr['number'])}",
        f"  title: {json.dumps(pr['title'])}",
        f"  branch: {pr['branch']}",
        f"  merged_at: {pr.get('mergedAt') or 'unknown'}",
        f"  merge_sha: {pr.get('mergeCommit') or 'unknown'}",
        "linear:",
    ]
    if pr["linear"]:
        for tk in pr["linear"]:
            lines.append(f"  - {tk}")
    else:
        lines.append("  []")
    lines.append("plans:")
    for fn in plan_filenames:
        lines.append(f"  - {fn}")
    if cross_refs:
        lines.append("cross_refs:")
        for n in cross_refs:
            lines.append(f"  - {n}")
    lines.append(f"archived_at: {datetime.now(timezone.utc).isoformat()}")
    (target_dir / "_meta.yaml").write_text("\n".join(lines) + "\n")


def find_matching_plans_for_pr(pr: dict, plans_dir: Path) -> list[Path]:
    """All plans whose ## Files section overlaps the PR's diff files."""
    diff_set = set(pr["files"])
    matches = find_plans_matching_diff(diff_set, plans_dir, min_overlap=1)
    return [m[2] for m in matches]


def archive_pr_bundle(
    pr: dict,
    plans: list[Path],
    plans_dir: Path,
    by_pr_dir: Path,
    dry_run: bool,
) -> Path | None:
    """Create archive/by-pr/PR-<num>-<slug>/, move plans, write _meta.yaml."""
    slug = slugify_branch(pr["branch"])
    target_dir = by_pr_dir / f"PR-{pr['number']}-{slug}"
    if not plans:
        return None
    if dry_run:
        info(f"  [dry-run] would create {target_dir}")
        for p in plans:
            info(f"  [dry-run]   move {p.name}")
        info(f"  [dry-run]   write _meta.yaml (linear={pr['linear']})")
        return target_dir
    target_dir.mkdir(parents=True, exist_ok=True)
    moved_filenames: list[str] = []
    for p in plans:
        dest = target_dir / p.name
        if dest.exists():
            info(f"  warn: {dest} already exists, skipping {p}")
            continue
        shutil.move(str(p), str(dest))
        moved_filenames.append(p.name)
    if moved_filenames:
        write_meta_yaml(target_dir, pr, moved_filenames)
        info(f"  archived {len(moved_filenames)} plan(s) to {target_dir}")
    return target_dir


def cmd_archive_pr(args: argparse.Namespace) -> int:
    """--mode=archive-pr --pr=<num>"""
    pr = fetch_pr_data(args.pr, repo=args.repo)
    if not pr:
        info(f"error: could not fetch PR #{args.pr}")
        return 2
    plans = find_matching_plans_for_pr(pr, args.plans_dir)
    if not plans:
        info(f"PR #{args.pr}: no matching plans in {args.plans_dir}")
        return 0
    info(f"PR #{args.pr} ({pr['branch']}): {len(plans)} matching plan(s)")
    if not args.execute:
        info("(dry-run; pass --execute to move files)")
    by_pr_dir = args.archive_dir / "by-pr"
    if args.execute:
        by_pr_dir.mkdir(parents=True, exist_ok=True)
    archive_pr_bundle(pr, plans, args.plans_dir, by_pr_dir, dry_run=not args.execute)
    return 0


def cmd_backfill(args: argparse.Namespace) -> int:
    """--mode=backfill --since=30d"""
    cutoff = parse_since(args.since)
    info(f"backfill: scanning merged PRs since {cutoff.isoformat()}")
    list_args = [
        "gh", "pr", "list", "--state", "merged",
        "--limit", str(args.limit),
        "--json", "number,title,headRefName,mergedAt",
    ]
    if args.repo:
        list_args += ["--repo", args.repo]
    prs = gh_json(list_args) or []
    in_window: list[dict] = []
    for pr_summary in prs:
        merged_at = pr_summary.get("mergedAt")
        if not merged_at:
            continue
        try:
            merged_dt = datetime.fromisoformat(merged_at.replace("Z", "+00:00"))
        except ValueError:
            continue
        if merged_dt >= cutoff:
            in_window.append(pr_summary)
    info(f"  {len(prs)} PRs returned by gh; {len(in_window)} merged within window")

    plans_assigned: dict[Path, int] = {}
    cross_refs_per_pr: dict[int, list[int]] = {}
    pr_data_cache: dict[int, dict] = {}
    by_pr_dir = args.archive_dir / "by-pr"
    if args.execute:
        by_pr_dir.mkdir(parents=True, exist_ok=True)

    plans_archived_count = 0
    prs_with_matches = 0
    for pr_summary in sorted(in_window, key=lambda p: p["mergedAt"]):
        pr = fetch_pr_data(pr_summary["number"], repo=args.repo)
        if not pr:
            continue
        pr_data_cache[pr["number"]] = pr
        candidate_plans = find_matching_plans_for_pr(pr, args.plans_dir)
        plans_for_this_pr: list[Path] = []
        for p in candidate_plans:
            if p in plans_assigned:
                cross_refs_per_pr.setdefault(plans_assigned[p], []).append(pr["number"])
            else:
                plans_for_this_pr.append(p)
                plans_assigned[p] = pr["number"]

        if not plans_for_this_pr:
            continue
        prs_with_matches += 1
        info(f"PR #{pr['number']} ({pr['branch']}): {len(plans_for_this_pr)} plan(s)")
        archive_pr_bundle(pr, plans_for_this_pr, args.plans_dir, by_pr_dir, dry_run=not args.execute)
        plans_archived_count += len(plans_for_this_pr)

    if args.execute:
        for owning_pr, refs in cross_refs_per_pr.items():
            pr = pr_data_cache.get(owning_pr)
            if not pr:
                continue
            slug = slugify_branch(pr["branch"])
            target_dir = by_pr_dir / f"PR-{owning_pr}-{slug}"
            if not target_dir.exists():
                continue
            meta_path = target_dir / "_meta.yaml"
            existing = meta_path.read_text() if meta_path.exists() else ""
            if "cross_refs:" not in existing:
                addendum = "cross_refs:\n" + "\n".join(f"  - {r}" for r in sorted(set(refs))) + "\n"
                meta_path.write_text(existing + addendum)

    remaining = sum(1 for _ in args.plans_dir.glob("*.md")) if args.execute else None
    info("---")
    info(f"backfill summary: {plans_archived_count} plan(s) archived across {prs_with_matches} PR(s)")
    if remaining is not None:
        info(f"active plans remaining: {remaining}")
    return 0


def cmd_audit(args: argparse.Namespace) -> int:
    """--mode=audit — list active plans + their mtimes."""
    plans = sorted(args.plans_dir.glob("*.md"), key=lambda p: p.stat().st_mtime, reverse=True)
    info(f"active plans in {args.plans_dir}: {len(plans)}")
    for p in plans:
        mtime = datetime.fromtimestamp(p.stat().st_mtime, tz=timezone.utc).strftime("%Y-%m-%d")
        info(f"  {mtime}  {p.name}")
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(description="Archive plan-mode files by linking them to merged PRs.")
    parser.add_argument("--mode", choices=["archive-pr", "backfill", "audit"], required=True)
    parser.add_argument("--pr", type=int, help="PR number (for --mode=archive-pr)")
    parser.add_argument("--since", default="30d", help="Time window for --mode=backfill (e.g. 30d, 2w)")
    parser.add_argument("--limit", type=int, default=200, help="gh pr list limit")
    parser.add_argument("--repo", help="Override repo (default: current cwd's repo)")
    parser.add_argument("--execute", action="store_true", help="Actually move files (default: dry-run)")
    parser.add_argument("--plans-dir", type=Path, default=PLANS_DIR, help="Override plans directory")
    parser.add_argument("--archive-dir", type=Path, default=ARCHIVE_DIR, help="Override archive directory")
    args = parser.parse_args()

    if args.mode != "audit" and not args.archive_dir.exists():
        args.archive_dir.mkdir(parents=True, exist_ok=True)

    if args.mode == "archive-pr":
        if not args.pr:
            info("error: --mode=archive-pr requires --pr=<num>")
            return 2
        return cmd_archive_pr(args)
    if args.mode == "backfill":
        return cmd_backfill(args)
    if args.mode == "audit":
        return cmd_audit(args)
    return 2


if __name__ == "__main__":
    sys.exit(main())
