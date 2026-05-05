<!-- ARCHITECTURE: This is CLAUDE.base.md — the git-tracked template.
     bootstrap.sh copies this to CLAUDE.md and appends local instruction @-refs.
     CLAUDE.md is gitignored because it contains machine-specific local refs.
     Edit THIS file, then run bootstrap.sh to regenerate CLAUDE.md.
     Only CLAUDE.md is symlinked to ~/.claude/ and read by Claude Code at runtime. -->

<source-of-truth>
~/dotfiles/ is the single source of truth for all agent configuration.
~/.claude/, ~/.copilot/, and ~/.agents/ are consumer targets, not sources.
NEVER edit files directly in ~/.claude/, ~/.copilot/, or ~/.agents/.
ALL changes must be made in ~/dotfiles/ and propagated via bootstrap.sh.
</source-of-truth>

Always read global rule instructions first and confirm that you have done so by writing "Read Claude." in the chat:

@~/dotfiles/global.instructions.md

## Workspace-Detected Instructions

Check the $ACTIVE_CONTEXTS environment variable (set by ~/dotfiles/bin/detect-context.sh). Load instructions matching each active context:

- `nextjs` → @~/dotfiles/instructions/nextjs.instructions.md
- `nextjs` or `react` → @~/dotfiles/instructions/ux-prototyping.instructions.md
- `php` or `laravel` → @~/dotfiles/instructions/php.instructions.md
- `sanity` → @~/dotfiles/instructions/sanity.instructions.md

If `$ACTIVE_CONTEXTS` is not set, fall back to checking for file signatures (`next.config.*`, `composer.json`, `sanity.config.*`, etc.) and load the matching instructions above.

Output "Active Context: [list of detected contexts]." to chat (e.g. "Active Context: nextjs, sanity."). If no contexts were detected, output "Active Context: none."

## Always-Loaded Instructions

@~/dotfiles/instructions/handoff.instructions.md

## Client & Project Context (auto-generated)

@~/dotfiles/working/active-client.md

## Service-Triggered Instructions

If working with Google Docs, Sheets, or Slides, also read:
@~/dotfiles/instructions/google-docs.instructions.md

If working with Sentry, also read:
@~/dotfiles/instructions/sentry.instructions.md

If the HUD daemon is running (check: `curl -sf http://localhost:7823/api/state > /dev/null 2>&1`), also read:
@~/dotfiles/instructions/hud.instructions.md

## Task-Triggered Instructions

If working on CSS, styling, or frontend UI, also read:
@~/dotfiles/instructions/css.instructions.md

## About Local Instructions

`bootstrap.sh` auto-appends `@`-references for any `*.instructions.md` files found in `instructions/_local/`. Files with `auto-load: false` in their frontmatter are registered as task-triggered instead — read them only when the task matches their description. Run `bootstrap.sh` after adding new local instruction files.
