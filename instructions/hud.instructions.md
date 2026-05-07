---
description: "HUD daemon event emission — observability for VS Code Copilot sessions. Loaded only when daemon is running."
---
Output "Read HUD instructions." to chat to acknowledge you read this file.

# HUD Events

When the HUD daemon is running (check: `curl -sf http://localhost:7823/api/state > /dev/null 2>&1`), emit events to give the HUD visibility into VS Code Copilot sessions that the CLI wrapper can't observe.

**When to emit:**
1. **On skill/instruction/rule load** — After reading a SKILL.md, instructions file, or rule file, emit a `read` event. Batch them into a single terminal call:
   ```bash
   bash ~/dotfiles/bin/write-hud-state.sh reads "global.instructions.md" "skills/codebase-audit/SKILL.md" "instructions/nextjs.instructions.md"
   ```
2. **On milestones** — At slice completion, commit, or audit finish, emit an `info` event:
   ```bash
   bash ~/dotfiles/bin/write-hud-state.sh info "Slice 3 committed"
   ```
3. **On compliance results** — After compliance audit, emit pass/fail/warn:
   ```bash
   bash ~/dotfiles/bin/write-hud-state.sh compliance <pass> <fail> <warn>
   ```

**How:** Always use `write-hud-state.sh` CLI — it handles transport fallback (pipe → HTTP → JSONL).

Event types: `info` (milestone), `read` (skill/rule/instruction loaded), `pass`/`fail`/`warn` (compliance), `context` (context change).

Emit reads once after loading all files for the session. Keep milestone events to 3-5 per session. This is observability, not logging.
