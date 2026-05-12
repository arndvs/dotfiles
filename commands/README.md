# Commands

Slash command dispatchers. Each `.md` file is a thin entry point that loads a skill and passes through arguments.

## How Commands Work

Typing `/work` in Claude Code chat loads `commands/work.md`, which reads the `do-work` skill's `SKILL.md` and executes it. Commands are the user-facing interface; skills are the implementation.

```
User types /work → commands/work.md → loads skills/do-work/SKILL.md → executes workflow
```

`$ARGUMENTS` in the command file is replaced with whatever the user typed after the command name.

## Command Inventory

| Command | Skill | Purpose |
|---------|-------|---------|
| `/address-review` | `review-pr-copilot` | Fetch and address Copilot review comments on active PR |
| `/audit` | `codebase-audit` | Ruthless audit reporting only real problems |
| `/check` | `session-close` | Pre-flight checklist before ending a coding session |
| `/document` | `document` | Write, update, or audit documentation |
| `/explore` | `explore` | Deep codebase exploration via parallel subagents |
| `/plan` | `architect` | Implementation plan with vertical slices |
| `/review` | `code-review` | Focused review of staged or recent changes |
| `/test` | `tdd` | Red-green-refactor workflow |
| `/work` | `do-work` | Core execution loop — understand, plan, implement, validate, commit |

## Adding a Command

1. Create `commands/your-command.md`
2. Content is minimal — load a skill and pass arguments:
   ```markdown
   Load the your-skill skill from ~/dotfiles/skills/your-skill/SKILL.md. Execute the workflow.

   $ARGUMENTS
   ```
3. Auto-discovered — no registration needed.
