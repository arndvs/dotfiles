# Contributing to ctrl+shft

ctrl+shft is a dotfiles system for AI coding agents. Contributions are welcome — skills, worked examples, bug fixes, and documentation all help.

This doc covers everything you need to contribute cleanly.

---

## Quick start

```bash
# 1. Fork the repo on GitHub, then clone your fork
git clone https://github.com/<you>/ctrlshft.git ~/dotfiles

# 2. Bootstrap your local environment
bash ~/dotfiles/bin/bootstrap.sh
# After the initial bootstrap, you can also use: ctrl bootstrap

# 3. Create a branch
git checkout -b skill/your-skill-name

# 4. Make your changes, then open a PR against the default branch
```

Always clone to `~/dotfiles` — paths are hardcoded across the project.

---

## Branch naming

| Type | Pattern | Example |
|------|---------|---------|
| New skill | `skill/name` | `skill/code-review` |
| Worked example | `example/name` | `example/ad-team` |
| Bug fix | `fix/description` | `fix/bootstrap-zsh-detection` |
| Documentation | `docs/description` | `docs/update-readme` |
| Tooling / scripts | `tooling/description` | `tooling/skill-lint-action` |

---

## What to contribute

### Where things belong

ctrl+shft has three distinct places for skills and instructions. Putting something in the wrong place undermines the whole system — a bloated `skills/` directory defeats the purpose of progressive loading.

```text
skills/            ← universal, stack-agnostic, high signal
examples/          ← domain-specific architectures
skills/_local/     ← yours alone, never shared
```

**`skills/` — strict criteria**

A skill belongs here only if it passes all of these:

- Works regardless of stack, domain, or business context
- Improves how Claude Code *operates*, not what it produces for a specific domain
- You'd want it on every machine, for every project, indefinitely
- Removing it would make Claude Code measurably worse for most users

If you're unsure, it probably doesn't belong here.

**`examples/` — domain-specific architectures**

A worked example belongs here if:

- It's specific to a domain (advertising, ecommerce, support, content)
- It teaches agents how to do a business function
- It's opinionated about a particular workflow or toolchain
- It's only complete as part of a larger multi-agent architecture

Skills that only make sense within a specific domain should live inside an example, not in the root `skills/` directory. An ad copywriter skill belongs in `examples/ad-team/`, not in `skills/`.

**`skills/_local/`**

For skills that are specific to your client, codebase, or company — proprietary methods, internal tooling, context that wouldn't make sense to anyone outside your organization. This directory is gitignored and will never appear in a PR.

---

### Picking a tier (instructions vs rules)

Before adding agent guidance, pick the lowest tier that triggers correctly:

| Tier | Where to put it | When to use |
| ---- | --------------- | ----------- |
| **T1 always-on** | `global.instructions.md` | Universal philosophy and safety rules — applies to *every* task |
| **T2 context-gated** | `instructions/<stack>.instructions.md` | Stack-specific (Next.js, Sanity, PHP) — loads via `ACTIVE_CONTEXTS` |
| **T2 task-triggered** | `instructions/<service>.instructions.md` | Service or task mentioned in CLAUDE.base.md (CSS, Sentry, HUD) |
| **T3 path-gated** | `rules/<topic>.md` with `paths:` | Loads only when the agent edits a matching file |
| **T4 skill-triggered** | `skills/<skill>/SKILL.md` | Multi-step workflows the agent invokes on demand |

Re-shelve aggressively. If a rule applies only to `.tsx` files, it belongs in `rules/` with `paths: ["**/*.{tsx,jsx}"]` — not in `global.instructions.md`. The always-on payload should be lean.

---

### Skills

A skill is a markdown file that teaches an agent a specific method or procedure.

**Good `skills/` candidates:**
- A debugging or analysis method that works across any codebase
- A workflow pattern that improves agent behavior regardless of project type
- A meta-skill that helps Claude Code operate more reliably

**Not a `skills/` contribution:**
- A skill that only makes sense for a specific framework, tool, or domain
- A one-off prompt or piece of project-specific context
- Something that duplicates an existing skill without meaningfully improving it
- Anything you wouldn't want loaded on every project you ever work on

When in doubt: if it's domain-specific, put it in an example. If it's personal or client-specific, put it in `_local/`. The shared `skills/` directory should stay lean.

See [Skill file format](#skill-file-format) below.

### Worked examples

Complete agent architectures for a specific use case — folder structure, system prompts, skills files, and a brief explaining the design decisions. Lives in `examples/`.

This is the right place for domain-specific skills. An example for an ad team will have its own copywriter skill, analyst skill, and data ingestion skill — all scoped to that architecture, none polluting the root `skills/` directory.

### Bug fixes

If bootstrap, uninstall, detect-context, or any other script behaves unexpectedly on your OS or setup — open an issue first, then a fix. Include your OS, shell, and what you expected vs. what happened.

### Documentation

Corrections, clarifications, and additions to README, CONTRIBUTING, or inline comments. Keep the voice consistent — direct, specific, no filler.

---

## Skill file format

Every skill lives in its own folder:

```text
skills/
└── your-skill/
    └── SKILL.md
```

### Required front matter

```markdown
---
name: your-skill
description: "One sentence: when to invoke this skill and what it does. Be specific enough that an agent can decide whether to use it."
---
```

### Body structure

```markdown
# Skill name

Brief explanation of what this skill is for and when to use it. 1–3 sentences.

## When to invoke

Specific triggers — what the user says or what situation calls for this skill.

## Method

Step-by-step procedure. Be explicit. Assume the agent will follow this literally.

### Step 1 — Name the step

What to do. Include code blocks, commands, or examples where relevant.

### Step 2 — Name the step

...

## Output format

What the agent should produce at the end. Format, structure, length.

## Examples

Optional but strongly encouraged. Show a good output.
```

### What makes a skill good

- **Procedural, not philosophical.** Steps the agent can follow, not advice.
- **Scoped.** One skill does one thing. If it's doing two things, split it.
- **Tested.** You've actually run it and it produces useful output.
- **Honest about limits.** If the skill only works for a specific stack or context, say so.

### What gets a skill rejected from `skills/`

- No front matter
- Description that doesn't explain when to invoke it
- Body is a wall of prose with no steps
- Duplicates an existing skill without meaningfully improving it
- Domain-specific — belongs in an example instead
- Only useful for a specific framework, tool, or client — belongs in `_local/`

---

## Worked example format

```text
examples/
└── your-example/
    ├── README.md          ← architecture overview and design decisions
    ├── orchestrator/
    │   └── system-prompt.md
    ├── agent-name/
    │   ├── system-prompt.md
    │   └── skills/
    │       └── skill-name.md
    └── knowledge-base/
        └── brief.md
```

The README.md for a worked example should explain:
- The problem being solved
- Why this agent architecture (not just what)
- What you'd change after running it in production
- What triggers a shift between phases if the workflow has phases

---

## Pull request checklist

Before opening a PR, check:

- [ ] Branch name follows the naming convention
- [ ] Skill files have valid front matter (`name`, `description`)
- [ ] New skills are in their own folder under `skills/`
- [ ] No sensitive data (API keys, tokens, personal info)
- [ ] `bootstrap.sh` still runs cleanly after your changes
- [ ] PR description explains what changed and why

PRs that skip the checklist will be asked to complete it before review.

---

## Commit messages

Use conventional commits:

```text
skill: add systematic-refactoring skill
fix: detect zsh on macOS when SHELL unset
docs: clarify bootstrap idempotency
example: add ad-team worked example
tooling: add skill front matter lint action
```

Keep the subject line under 72 characters. Add a body if the why isn't obvious from the subject.

---

## Issues

Before opening an issue:

- Search existing issues — it may already be reported or in progress
- For bugs, include OS, shell, and the exact error output
- For skill requests, describe the workflow you want taught — what triggers it, what it should produce

Use the issue templates. They exist to make triage faster.

---

## Private skills

If your skill contains client-specific logic, proprietary methods, or anything you don't want public — put it in `skills/_local/`. That directory is gitignored and will never appear in a PR.

---

## Questions

Open a [GitHub Discussion](https://github.com/arndvs/ctrlshft/discussions) rather than an issue. Issues are for bugs and tracked work. Discussions are for questions, ideas, and architecture conversations.
