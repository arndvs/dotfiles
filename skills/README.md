# Skills

Multi-step workflow definitions — the brains of ctrl+shft. Each skill is a `SKILL.md` file that defines a complete workflow triggered by task description or slash command.

## How Skills Load (Tier 4)

Skills are auto-discovered from `skills/*/SKILL.md`. The agent reads each skill's `description` frontmatter and loads the SKILL.md when the user's task matches. Skills can also be invoked explicitly via [commands/](../commands/README.md).

## Skill Inventory

| Skill | Triggers | Purpose |
|-------|----------|---------|
| `architect` | "plan this", "act as an Architect", "slice this into tasks" | Implementation planning with vertical slices |
| `atomic-commits` | "commit", "checkpoint", "ship", "push", "create a PR" | Atomic commits on feature branches, conventional messages |
| `code-review` | "review my changes", "check my diff", "pre-merge review" | Focused review of staged/recent changes |
| `codebase-audit` | "audit", "code audit", "find bugs" | Ruthless audit reporting only real problems |
| `compliance-audit` | Auto-invoked after do-work, tdd, systematic-debugging | Review diff against active rules, flag violations |
| `do-work` | "implement", "build this", "fix this", "work loop" | Core execution loop: understand → plan → implement → validate → commit |
| `error-audit` | After sessions with repeated retry loops | Analyze cross-session error patterns to surface systemic issues |
| `document` | "write docs", "update the README", "create an ADR" | Write, update, or audit documentation |
| `explore` | "explore", "understand", "investigate", "how does X work" | Deep codebase exploration via parallel subagents |
| `frontend-component-style` | "build a component", "scaffold this", "extract this into" | Component file structure, naming, and layer separation |
| `grill-me` | "grill me", "interview me", "ask me questions" | Relentless interrogation until shared understanding |
| `halbert-copy-editor` | "punch up my copy", "edit sales page", "improve conversions" | Edit persuasive writing using the Halbert Copywriting Method |
| `improve-architecture` | "improve architecture", "find shallow modules" | Deep module analysis for architectural improvements |
| `npm-security-audit` | "is this package safe", "audit this project" | Layered security audit before npm install |
| `prd-to-issues` | "break this PRD into issues", "create a kanban" | PRD → vertical slices → GitHub issues (AFK/HITL labeled) |
| `pr-preflight` | "/preflight", "pre-PR audit" | Exhaustive pre-PR audit that front-runs review tools |
| `research` | "research", "investigate before building", "flush unknowns" | Cache exploration into a research document |
| `review-pr-copilot` | "address review comments", "fix PR comments" | Triage Copilot review comments, fix, resolve threads |
| `sanity-best-practices` | Working with Sanity CMS content, schemas, GROQ | Sanity development patterns and framework integrations |
| `session-close` | "/check", before ending a session | Pre-flight checklist: quality gates before session end |
| `sketch-the-solution` | "design UX", "UX process", "product design process" | 7-phase UX design: user stories → tested interfaces |
| `skill-scaffolder` | "create a skill", "scaffold a skill" | Meta-skill for building new agent skills |
| `stress-test` | "/stress-test", before deploying, after rules update | Adversarial rule compliance testing |
| `systematic-debugging` | Any bug, test failure, unexpected behavior | Root cause investigation before proposing fixes |
| `tdd` | "write tests first", "TDD", "red-green refactor" | Red-green-refactor workflow (backend only) |
| `write-a-prd` | "write a PRD", "plan a feature" | Product Requirements Document from a rough idea |

## The Planning Pipeline

Skills chain together for end-to-end feature delivery:

```
/grill-me → /write-a-prd → /architect → /prd-to-issues → /do-work → shft
```

## Private Skills

`skills/_local/` is gitignored. Drop private, business-specific, or stack-specific skills here — auto-discovered alongside public skills, never leave your machine.

## Adding a Skill

1. Create `skills/your-skill/SKILL.md`
2. Add YAML frontmatter with `name` and `description` (description contains trigger phrases)
3. Define the workflow steps, output format, and rules
4. Auto-discovered — no registration needed

See [ADR-001](../docs/adr/ADR-001-vendor-boundary.md) for what belongs in `skills/` (universal workflow) vs `_local/` (stack-specific).
