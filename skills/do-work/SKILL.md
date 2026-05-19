---
name: do-work
description: "Core execution loop for implementing tasks. Use when asked to 'do work', 'implement', 'build this', 'fix this', 'plan execute clear', 'plan then execute', 'work loop', or when working through a plan or backlog item."
---

# Do Work

Output "Read Do Work skill." to chat to acknowledge you read this file.

Pipeline position: `/grill-me` → `/write-a-prd` → `/architect` → `/prd-to-issues` → **`/do-work`** → `shft`

## Workflow

### 0. HUD event (if daemon running)

Emit a session-start event so the HUD tracks this work:
```bash
source ~/dotfiles/bin/write-hud-state.sh
write_hud_event "info" "do-work: started — $TASK_SUMMARY"
```
Replace `$TASK_SUMMARY` with a short description. Emit again after each commit (`do-work: committed — <message>`) and at session end (`do-work: completed`).

### 1. Understand

Read any referenced plan, PRD, or GitHub issue. If none provided, clarify the task with the user before proceeding.

### 2. Plan (optional)

If the task has not already been planned, create a plan for it. Break large tasks into vertical slices (tracer bullets) — each slice should touch all layers end-to-end rather than building layer by layer.

Skip this step if a plan or PRD already exists.

### 3. Implement

Read a sample existing file of the same type before creating new ones — follow the conventions already established in the codebase.

**For backend code**: use red/green/refactor, one test at a time in a tracer-bullet style.

1. Write a single failing test for the smallest vertical slice of behaviour
2. Run the test — confirm it fails (red)
3. Write the minimum code to make it pass (green)
4. Repeat from step 1 for the next slice
5. Refactor if needed while keeping tests green

Do not write all tests upfront — write one, make it pass, then move to the next.

**For frontend code**: implement directly without TDD.

### 4. Validate

Run the project's feedback loops until they pass cleanly. Auto-detect from the workspace:

- **package.json** → look for `test`, `typecheck`, `type-check`, `lint` scripts. Run with the project's package manager (npm/pnpm/yarn/bun).
- **composer.json** → look for `test`, `lint`, `phpstan` scripts. Run with `composer run`.
- **Makefile** → look for `test`, `lint`, `check` targets. Run with `make`.
- **pyproject.toml / setup.cfg** → look for pytest, mypy, ruff. Run directly.
- **Pre-commit hooks** → if `.husky/` or `.pre-commit-config.yaml` exists, the commit step will trigger them automatically.

If no feedback loops are detected, tell the user and ask what validation commands to run.

### 5. Commit

Once validation passes, commit the work using the atomic-commits skill (one logical change per commit, conventional commit message).

### 6. Preflight (Ship mode only)

If this is the final slice and the work is ready for review, run the **pr-preflight** skill end-to-end before pushing. Preflight audits `main..HEAD`, so the commit must exist before it can inspect the diff. This catches the class of issues that iterative Copilot reviews find one-at-a-time, so review is one pass instead of many.

Skip this step when using Commit mode for intermediate checkpoints — preflight runs once before the final push, not on every checkpoint.

After preflight passes, use the atomic-commits skill in **Ship** mode — push and open a PR.

### 7. Context Check

If this is one phase of a multi-phase plan, or if context usage is over 40%, follow the standard handoff protocol (`@~/dotfiles/instructions/handoff.instructions.md`) — commit all work, persist the remaining plan to `working/`, and provide the pickup command.

Include @-references to research.md, PRD issues, and key files modified this session.