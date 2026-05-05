---
description: "Git conventions — atomic commits, conventional messages, working-tree hygiene."
paths:
  - "**/*"
---

# Git Conventions

Loaded when committing or reviewing changes. The `atomic-commits` skill is the workflow companion to this rule file.

- One logical change per commit. Never bundle unrelated fixes
- Review `git diff --staged` before committing. No debug logs or dead code
- Commit message format: `<type>(<scope>): <short description>` — types: feat, fix, refactor, chore, docs, test
- Each commit must leave the codebase working — no broken states mid-task
