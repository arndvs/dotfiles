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

Run each phase sequentially. Do not skip phases — outputs of phase N are required inputs for phase N+1.

### Phase 1 — User Stories

Invoke `/ux-user-stories`. Produces: `user-stories.md`
Steps: Identify Goals → Write User Story → Highlight Key Terms & Verbs

### Phase 2 — System Map

Invoke `/ux-system-map`. Produces: `system-map.md` (with Mermaid ERD)
Steps: Create System Map → Draw Relationships

### Phase 3 — Flow Diagram

Invoke `/ux-flow-diagram`. Produces: `flow-diagram.md` (with Mermaid flowchart)
Steps: List Screens → Create Flow Diagram → Validate with User Stories

### Phase 4 — Model Attributes

Invoke `/ux-model-attributes`. Produces: `attributes.md`
Steps: List Attributes for each system map element

### Phase 5 — Screen Requirements

Invoke `/ux-screen-requirements`. Produces: `screen-requirements.md`
Steps: Create Goals → Apply Inform/Engage/Invite → List Screen Attributes (ABC)

### Phase 6 — Interface Design

Invoke `/ux-interface-design`. Produces: `interface-design.md` (specs + wireframes)
Steps: Get Inspired → High-Level Sketches → Detailed Sketches

### Phase 7 — Test Driven Design

Invoke `/ux-test-driven-design`. Produces: `test-plan.md`
Steps: User Testing → Six Mistakes Review

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
