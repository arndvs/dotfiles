Load the cmd subcommand skill from ~/cmd/tools/skills/cmd-<subcommand>/SKILL.md, where <subcommand> is the first argument after /cmd. Read ~/cmd/CLAUDE.md for context. If the skill doesn't exist yet, tell the user it's planned but not implemented.

If no subcommand is provided, show available subcommands:
- **init** — Initialize a new venture or client (`/cmd init <venture-name>`)
- **ingest** — Process new raw material into wiki pages (`/cmd ingest [path]`)
- **cadence** — Run a cadence review (`/cmd cadence daily|weekly|monthly|quarterly|yearly`)
- **lint** — Check cmd structural health (`/cmd lint`)
- **voice-check** — Validate a draft against voice samples (`/cmd voice-check <draft-path>`)
- **batch** — Sunday content batch: pick ideas, draft, voice-check (`/cmd batch`)

$ARGUMENTS
