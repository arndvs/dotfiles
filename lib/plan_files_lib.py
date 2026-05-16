"""Shared plan-file utilities for plan-archive and plan-review hooks.

Extracted from skills/plan-archive/plan-archive.py so multiple consumers
(plan-archive, plan-review-phase2) can share the same parsing logic.

Exports:
  PLANS_DIR             — default ~/.claude/plans/ path
  REPO_PREFIXES         — detected path prefixes for repo-relative normalization
  extract_plan_files()  — parse ## Files section from a plan
  normalize_to_repo_relative() — strip repo prefixes from a path
  find_plans_matching_diff()   — find plans overlapping a set of diff files
  find_best_plan_for_diff()    — return the single best-matching plan
"""

from __future__ import annotations

import os
import re
import subprocess
from pathlib import Path

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


def find_best_plan_for_diff(
    diff_files: set[str],
    plans_dir: Path | None = None,
) -> Path | None:
    """Return the single best-matching plan for a set of diff files, or None."""
    matches = find_plans_matching_diff(diff_files, plans_dir, min_overlap=1)
    return matches[0][2] if matches else None
