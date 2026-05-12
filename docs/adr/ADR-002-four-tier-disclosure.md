# ADR-002 — Four-tier progressive disclosure model

**Status:** Accepted
**Date:** 2026-05-12
**Author:** Aaron Davis
**Deciders:** Maintainer (sole, at this stage)

---

## Context

AI coding agents operate within a finite context window. Every instruction loaded at session start consumes tokens that could otherwise be used for the actual task. Early versions of ctrl+shft loaded all instructions, rules, and skill descriptions into every session regardless of the current project's stack or the task being performed. A Next.js developer received PHP conventions. A backend debugging session loaded frontend animation rules.

This created two problems:

1. **Context waste** — irrelevant instructions consumed 20–30% of the available context window before the agent began working, pushing sessions into quality degradation earlier.
2. **Signal dilution** — the agent gave equal weight to all loaded instructions, leading to false positives (applying Next.js patterns to a Laravel project) and attention splitting across irrelevant concerns.

---

## Decision

Instructions are organized into four tiers, each with a distinct loading trigger. The always-on payload stays small (≤80 lines); conditional knowledge loads only when the environment, file context, or task description demands it.

### Tier 1 — Always-on

Loaded every session, unconditionally.

- `global.instructions.md` — universal agent rules, source-of-truth policy, safety constraints
- `instructions/handoff.instructions.md` — session persistence protocol

Target: ≤80 lines combined. If a rule applies only to specific stacks or file types, it does not belong here.

### Tier 2 — Context-gated and service/task-triggered

Loaded when `$ACTIVE_CONTEXTS` (set by `detect-context.sh` on `cd()`) matches, or when a specific service or task type is active.

- **Context-gated:** `nextjs`, `sanity`, `php` — triggered by file signatures (`next.config.*`, `sanity.config.*`, `composer.json`)
- **Service-triggered:** `hud`, `sentry`, `google-docs` — triggered by active service or mention
- **Task-triggered:** `css` — triggered by task type (styling/frontend UI work)

### Tier 3 — Path-gated

Loaded when the agent edits a file matching the rule's `paths` glob pattern. These are convention-enforcement rules in `rules/`.

Examples: TypeScript conventions load on `**/*.{ts,tsx}`, migration safety loads on `**/migrations/**`.

### Tier 4 — Skill-triggered

Loaded when the user's task description matches the skill's `description` frontmatter. These are full workflow definitions in `skills/*/SKILL.md`.

Examples: The TDD skill loads when the user says "write tests first". The explore skill loads on "how does X work".

---

## Consequences

**Positive:**

- Always-on payload dropped from ~160 lines to ≤80, freeing ~50% of the baseline context budget
- Sessions start with only relevant knowledge — a PHP project never loads Next.js rules
- Agents make fewer false-positive suggestions from irrelevant instructions
- Quality degradation threshold pushed later into the session (more budget for actual work)

**Negative:**

- Loading is implicit — a developer must understand the tier model to know why a rule did or didn't fire
- `detect-context.sh` runs on every `cd()`, adding minor shell overhead
- Files misclassified to the wrong tier cause either bloat (too high) or missed enforcement (too low)

**Neutral:**

- The tier model does not change what rules exist — only when they load. All content is still accessible when relevant.

---

## Alternatives considered

**Load everything always:** The original approach. Rejected due to measurable context waste and quality degradation on non-trivial sessions.

**Two tiers (always + conditional):** Simpler but insufficient. Path-gated rules (T3) and skill-triggered workflows (T4) have fundamentally different loading signals — collapsing them loses precision.

**Dynamic loading via LLM self-selection:** The agent decides what to load at session start. Rejected because it requires the agent to read all available instructions to decide which to load — defeating the purpose of reducing context consumption.
