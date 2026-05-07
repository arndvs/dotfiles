---
description: "Git conventions — atomic commits, conventional messages, working-tree hygiene."
paths:
  - "**/*.{ts,tsx,js,jsx,mjs,cjs,py,rb,go,rs,java,php,sh,bash,md,yml,yaml,json}"
---

# Git Conventions

Auto-loads when editing common source files (the file types that typically get committed).

- One logical change per commit. Never bundle unrelated fixes
- Review `git diff --staged` before committing. No debug logs or dead code
- Commit message format: `<type>(<scope>): <short description>` — types: feat, fix, refactor, chore, docs, test
- Each commit must leave the codebase working — no broken states mid-task
- Before committing, remove unused imports YOUR changes created, scan for DRY violations, broken code, hidden bugs, overengineering, edge cases, and your last code changes not being reflected everywhere else in the app. Do not remove pre-existing dead code unless asked
