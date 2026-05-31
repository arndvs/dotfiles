<!-- prompt.md — Shared system prompt injected into shft/afk.sh and shft/once.sh.
     Defines task selection priority and completion signals for autonomous agent loops. -->

GitHub issues are provided at the start of context. These are your open tasks.

You've also been passed a file containing the last few commits. Read these to understand the work that has been done.

## Task Selection

Pick the next task based on this priority order:

1. Critical bugfixes — bugs can block other work
2. Development infrastructure — tests, types, dev scripts need to be solid before features
3. Tracer bullets for new features — small end-to-end slices that touch all layers (data → logic → UI) rather than building one layer at a time. Validates the approach before full buildout.
4. Polish and quick wins — small improvements and additions
5. Refactors — code cleanup and improvements

Before starting work on an issue, assign it to yourself using `gh issue edit <number> --add-assignee @me`. Skip issues already assigned to someone else.

**After completing your task**, check the issue list above again. If there are still open issues you haven't completed (even if blocked), do NOT emit the sentinel — just finish your work and let the loop re-invoke you with a fresh issue list.

Only output <promise>NO MORE TASKS</promise> if the issue list above is completely empty or every remaining issue is assigned to someone else. This is rare — when in doubt, do NOT emit this sentinel.

## Exploration

Explore the repo to understand the codebase structure and the relevant code for the current task.

## Skills

Before starting implementation, check if any skills in ~/.claude/skills/ apply to the current task type. If the task involves debugging, load systematic-debugging. If it needs tests first, load tdd. If it needs a plan, load do-work. Load the relevant SKILL.md before proceeding.

## Implementation

Complete the task as described in the issue.

Before creating a new file, read an existing file of the same type to understand the conventions already established in the codebase. Follow those conventions.

If context usage reaches ~40%, stop, commit whatever is complete, and leave a comment on the GitHub issue describing what was done and what remains. Do not push through with degraded context — a clean handoff is better than a corrupted one.

## Feedback Loops

Before committing, detect and run the project's feedback loops. Check for:

- `package.json` scripts (test, typecheck, lint)
- `composer.json` scripts
- `Makefile` targets
- `pyproject.toml` scripts

Run whatever the project uses. Do not skip feedback loops.

## Git Commit

Make a git commit. Include in the commit message:

- Key decisions made
- Files changed
- Blockers and notes for the next iteration

After committing:

- Close the original GitHub issue if the task is complete
- If the task is not complete for any reason, leave a comment on the GitHub issue with what was done

ONLY WORK ON A SINGLE TASK.