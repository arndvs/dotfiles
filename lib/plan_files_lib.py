"""Shared plan-file utilities for plan-archive and plan-review hooks.

Extracted from skills/plan-archive/plan-archive.py so multiple consumers
(plan-archive, plan-review-phase2) can share the same parsing logic.

Exports:
  PLANS_DIR             — default ~/.claude/plans/ path
  REPO_PREFIXES         — detected path prefixes for repo-relative normalization
  detect_repo_prefixes()      — derive prefixes from a given cwd
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


def _find_repo_root_from_module() -> Path | None:
    """Best-effort repo root discovery based on this module's location."""
    module_path = Path(__file__).resolve()
    for parent in module_path.parents:
        if (parent / ".git").exists():
            return parent
    return None


def _detect_repo_prefixes() -> list[str]:
    """Return path prefixes treated as repo-root markers when stripping to repo-relative."""
    env = os.environ.get("CLAUDE_PLAN_REPO_PREFIXES", "").strip()
    if env:
        return [p.strip() for p in env.split(",") if p.strip()]

    repo_root = _find_repo_root_from_module()
    if repo_root is None:
        return []

    return _prefixes_from_cwd(repo_root)

    try:
        result = subprocess.run(
            ["git", "rev-parse", "--show-toplevel"],
            capture_output=True, text=True, timeout=2, cwd=repo_root,
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

    return _prefixes_from_cwd(repo_root)


def _prefixes_from_cwd(cwd: Path) -> list[str]:
    """Derive repo prefixes from a directory by running git rev-parse."""
    try:
        result = subprocess.run(
            ["git", "rev-parse", "--show-toplevel"],
            capture_output=True, text=True, timeout=2, cwd=cwd,
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


def detect_repo_prefixes(cwd: str | Path | None = None) -> list[str]:
    """Public API: derive repo prefixes from *cwd* (or fall back to module default).

    Callers operating on a repo other than the one containing this module
    should call this with their working directory and pass the result into
    extract_plan_files / normalize_to_repo_relative.
    """
    env = os.environ.get("CLAUDE_PLAN_REPO_PREFIXES", "").strip()
    if env:
        return [p.strip() for p in env.split(",") if p.strip()]
    if cwd is None:
        return REPO_PREFIXES
    return _prefixes_from_cwd(Path(cwd))


REPO_PREFIXES = _detect_repo_prefixes()


def extract_plan_files(plan_text: str, repo_prefixes: list[str] | None = None) -> tuple[list[str], list[str], list[str]]:
    """Extract file paths from the ## Files section of a plan.

    Returns (repo_files, external_files, conditional_files).
    """
    prefixes = repo_prefixes if repo_prefixes is not None else REPO_PREFIXES
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
            path_match = re.search(r'`([^`]+\.[a-zA-Z0-9]+)`', line)
        if not path_match:
            continue

        raw_path = path_match.group(1).strip()

        if re.search(r'\((?:if |conditional|optional)', line, re.IGNORECASE):
            conditional_files.append(raw_path)
            continue

        if any(raw_path.startswith(p) for p in prefixes):
            repo_files.append(raw_path)
        elif raw_path.startswith("~/") or raw_path.startswith("/"):
            external_files.append(raw_path)
        else:
            repo_files.append(raw_path)

    return repo_files, external_files, conditional_files


def normalize_to_repo_relative(path_str: str, repo_prefixes: list[str] | None = None) -> str:
    """Normalize a file path to be repo-relative by stripping any known repo prefixes."""
    prefixes = repo_prefixes if repo_prefixes is not None else REPO_PREFIXES
    expanded = path_str
    for prefix in prefixes:
        if expanded.startswith(prefix):
            expanded = expanded[len(prefix):]
            break
    expanded = expanded.lstrip("/")
    return expanded


def find_plans_matching_diff(
    diff_files: set[str],
    plans_dir: Path | None = None,
    min_overlap: int = 1,
    repo_prefixes: list[str] | None = None,
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
        repo_files, _, _ = extract_plan_files(plan_text, repo_prefixes)
        if not repo_files:
            continue
        plan_rel = {normalize_to_repo_relative(p, repo_prefixes) for p in repo_files}
        overlap = len(plan_rel & diff_files)
        if overlap >= min_overlap:
            candidates.append((overlap, plan_file.stat().st_mtime, plan_file))
    candidates.sort(key=lambda x: (-x[0], -x[1]))
    return candidates


def find_best_plan_for_diff(
    diff_files: set[str],
    plans_dir: Path | None = None,
    repo_prefixes: list[str] | None = None,
) -> Path | None:
    """Return the single best-matching plan for a set of diff files, or None."""
    matches = find_plans_matching_diff(diff_files, plans_dir, min_overlap=1, repo_prefixes=repo_prefixes)
    return matches[0][2] if matches else None
