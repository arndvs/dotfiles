---
description: "Universal agent rules — source of truth, coding standards, error handling, and safety constraints. Always relevant."
---
<!-- global.instructions.md — Universal agent rules loaded for every workspace.
     Referenced by CLAUDE.md via @~/dotfiles/global.instructions.md.
     Always loaded regardless of ACTIVE_CONTEXTS. -->

<source-of-truth>
~/dotfiles/ is the single source of truth for all agent configuration.
~/.claude/, ~/.copilot/, and ~/.agents/ are consumer targets, not sources.
NEVER edit files directly in ~/.claude/, ~/.copilot/, or ~/.agents/.
ALL changes must be made in ~/dotfiles/ and propagated via bootstrap.sh.
If a consumer path is not a symlink (or verified Windows fallback copy) from ~/dotfiles/, treat that as broken state and repair it.
Public shared skills belong in ~/dotfiles/skills/. Private machine/client skills belong in ~/dotfiles/skills/_local/ (gitignored).
</source-of-truth>

Output "Read global instructions." to chat to acknowledge you read this file.

<general>
- Leave NO todo's, placeholders or missing pieces
- Keep it simple, lean, reuse what we have. Prefer early returns, removing code over adding. Think how can we REMOVE code from this repo instead of adding baggage or bloat
- Do not add legacy or backward compatibility except for database migrations
- Never fail silently. No sample data, placeholder text, || or ?? fallbacks, or defensive fixes — use fast, type-safe patterns that throw explicit errors with context. Exception: UI prototyping components use CMS-replaceable static data and graceful degradation per ux-prototyping instructions. If a response is unexpected, print it raw for debugging
- Before adding or changing code, read existing examples of the same pattern. Scan all usages of shared methods before modifying. Match existing style exactly
- Verify utilities and functions exist in the codebase before using them — search for definitions first, never assume a name exists
- Don't touch code outside the task. If you notice dead code or problems, mention them — don't fix them. Only remove imports/variables your changes made unused
- Never change my AI model, its context window, settings, URL or API keys unless explicitly told to do so
- If anything is unclear, ambiguous, or has a simpler alternative, stop and ask before implementing. List options when multiple valid interpretations exist
- Use modern APIs and patterns over legacy approaches. Baseline browser support is February 2026
- NEVER print credentials: Not in logs, not in error messages, not in agent outputs
- If I tell you to "report" or ask "how feasible", enter discuss mode and DO NOT EDIT CODE UNTIL I EXPLICITLY TELL YOU TO DO SO. Simply report, discuss, get skeptical, double check and plan all changes in a lean, DRY way
- When an API call fails (expired token, auth error, missing permissions), STOP IMMEDIATELY. Do not continue the task, do not speculate. Tell me the exact error, which token/key needs updating and in which file, then wait for me to fix it
- After you are done, remove unused imports YOUR changes created, scan for DRY violations, broken code, hidden bugs, overengineering, edge cases, your last code changes not being reflected everywhere else in the app. Do not remove pre-existing dead code unless asked
- Prefer clearing context and starting fresh over compacting. Repeated compaction leaves sediment — each round loses nuance and accumulates errors. When context is high, commit and start a new conversation. If you must compact (once per session max), pass summarization instructions describing what you're about to do next
</general>

<skill-context>
If the ACTIVE_CONTEXTS environment variable is set (by ~/dotfiles/bin/detect-context.sh), use it as the authoritative context list. Otherwise, check the workspace for file signatures (next.config.*, composer.json, sanity.config.*, prisma/schema.prisma, etc.) before loading domain-specific skills. Do not load skills irrelevant to the current workspace context.
</skill-context>

<!-- Counter-directive for microsoft/vscode#311462: VS Code Insiders 1.117 changed the
     system prompt to inject ALL rule files (including those with applyTo globs) alongside
     a blanket "acquire the instructions" directive, causing the model to eagerly load
     every rule at session start regardless of context. This block tells the model to
     treat applyTo as a conditional gate. Remove once the upstream bug is fixed. -->
<rule-loading>
Instruction/rule files that include an `<applyTo>` glob pattern are CONDITIONAL — only read them when a file matching that glob is actively being edited or is directly relevant to the current task. Do NOT eagerly load all rule files at session start. The `<applyTo>` metadata is a gate, not a label. If no files matching the glob are in context, skip that rule entirely.
</rule-loading>

<skill-self-learning>
This section covers two triggers: automatic self-learning after tasks, and explicit "remember" commands from the user.

**Trigger 1 — After completing any task where you loaded a SKILL.md:**
Self-evaluate: did anything go wrong, require a workaround, or behave differently than documented?
If yes, update the skill inline where the fix belongs — fix wrong instructions, add missing steps, correct parameters. Keep it DRY: integrate the new knowledge into the existing structure rather than appending to a separate section. If no suitable place exists, add a bullet to a `## Lessons Learned` section at the bottom (create if needed). Replace old bullets that a new finding supersedes.
Do NOT update for user error, transient issues (network timeout, rate limit), or findings already documented.
After updating, tell the user: "Updated [skill-name] skill: [one-sentence summary of what changed]"

**Trigger 2 — User says "remember", "save this", "add this to skill", or similar:**
Read the relevant SKILL.md in full, find the most suitable place to integrate the information in a DRY way, and edit it inline. Only fall back to `## Lessons Learned` if no better location exists. Confirm with: "Saved to [skill-name] skill: [one-sentence summary]."
</skill-self-learning>

<thinking>
- You must engage in exhaustive, deep-level reasoning. Think deeply about edge cases, data integrity, and architectural consequences before writing code and after refactorings.
- Self-check before committing: "Would a senior engineer say this is overcomplicated?" If yes, simplify. "Does every changed line trace directly to the user's request?" If not, revert the extras.
</thinking>

