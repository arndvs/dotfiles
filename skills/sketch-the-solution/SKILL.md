---
name: sketch-the-solution
description: "7-phase UX design process from user stories to tested interfaces. Use when asked to 'sketch the solution', 'design UX', 'UX process', 'product design process', or when going from idea to interface design."
---

# Sketch the Solution

Output "Read Sketch the Solution skill." to chat to acknowledge you read this file.

Pipeline position: `/grill-me` → `/write-a-prd` → **`/sketch-the-solution`** → `/architect` → `/do-work`

A 7-phase framework for designing user-centered digital products — from goal discovery through tested interface design. Each phase produces artifacts that feed the next. Derived from the GRNDWRK UX process (Amir Khella, Carl Smith, Dane Maxwell).

## Prerequisites

- Customer avatar(s) from idea extraction
- ID call notes / customer interview transcripts
- Understanding of the customer's current pain (problem space)

## The 7 Phases

Run each phase sequentially. Do not skip phases — outputs of phase N are required inputs for phase N+1. Each phase has a detailed reference document under [references/](references/). Read the phase reference before running the phase, then read each step reference as you work through it.

### Phase 1 — User Stories

Reference: [references/phase-1-user-stories.md](references/phase-1-user-stories.md). Produces: `user-stories.md`
Steps: [Identify Goals](references/phase-1-user-stories/identify-goals.md) → [Write User Story](references/phase-1-user-stories/write-user-story.md) → [Highlight Key Terms & Verbs](references/phase-1-user-stories/highlight-key-terms.md)

### Phase 2 — System Map

Reference: [references/phase-2-system-map.md](references/phase-2-system-map.md). Produces: `system-map.md` (with Mermaid ERD)
Steps: [Create System Map](references/phase-2-system-map/create-system-map.md) → [Draw Relationships](references/phase-2-system-map/draw-relationships.md)

### Phase 3 — Flow Diagram

Reference: [references/phase-3-flow-diagram.md](references/phase-3-flow-diagram.md). Produces: `flow-diagram.md` (with Mermaid flowchart)
Steps: [List Screens](references/phase-3-flow-diagram/list-screens.md) → [Create Flow Diagram](references/phase-3-flow-diagram/create-flow-diagram.md) → [Validate with User Stories](references/phase-3-flow-diagram/validate-flow.md)

### Phase 4 — Model Attributes

Reference: [references/phase-4-model-attributes.md](references/phase-4-model-attributes.md). Produces: `attributes.md`
Steps: [List Attributes](references/phase-4-model-attributes/list-attributes.md) for each system map element

### Phase 5 — Screen Requirements

Reference: [references/phase-5-screen-requirements.md](references/phase-5-screen-requirements.md). Produces: `screen-requirements.md`
Steps: [Create Screen Goals](references/phase-5-screen-requirements/create-screen-goals.md) → [Inform / Engage / Invite](references/phase-5-screen-requirements/inform-engage-invite.md) → [List Screen Attributes (ABC)](references/phase-5-screen-requirements/list-screen-attributes.md)

### Phase 6 — Interface Design

Reference: [references/phase-6-interface-design.md](references/phase-6-interface-design.md). Produces: `interface-design.md` (specs + wireframes)
Steps: [Get Inspired](references/phase-6-interface-design/get-inspired.md) → [High-Level Sketches](references/phase-6-interface-design/high-level-sketches.md) → [Detailed Sketches](references/phase-6-interface-design/detailed-sketches.md)

### Phase 7 — Test Driven Design

Reference: [references/phase-7-test-driven-design.md](references/phase-7-test-driven-design.md). Produces: `test-plan.md`
Steps: [User Testing](references/phase-7-test-driven-design/user-testing.md) → [Six Mistakes Review](references/phase-7-test-driven-design/six-mistakes.md)

## Data Flow

```
ID Calls → [1] user-stories.md → [2] system-map.md → [3] flow-diagram.md
         → [4] attributes.md → [5] screen-requirements.md
         → [6] interface-design.md → [7] test-plan.md → /architect
```

## Partial Entry

If prior phase artifacts already exist, validate them and start from the next incomplete phase. Ask the user which artifacts they already have.

## Rules

**Do:**

- Complete each phase fully before advancing
- Validate each phase's output against prior artifacts
- Generate Mermaid diagrams for visual artifacts
- Ask the user for missing inputs rather than guessing

**Do not:**

- Skip phases — each depends on the previous
- Design the solution in user stories — stories describe CURRENT pain only
- Jump to interface design before system map and flow are complete
- Over-polish early phases — iteration is expected

## Key Principles

- **Problem Space → Solution Space** — inhabit the user's world before designing
- **Kaizen > Perfection** — 1% daily improvement beats launching perfect products
- **Everything is an experiment** — no right or wrong, only data
- **Sellable UI** — only design value-demonstrating screens, skip admin/login
- **Never skip steps** — each phase builds on the last, skipping creates gaps and assumptions

## Handoff

After completing all 7 phases, offer:

1. `/architect` — create implementation plan from the UX artifacts
2. `/do-work` — begin building the product
3. `/write-a-prd` — formalize the design into a PRD

If context is high, follow the standard handoff protocol (`@~/dotfiles/instructions/handoff.instructions.md`).
