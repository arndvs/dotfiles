---
name: ux-screen-requirements
description: "Phase 5 of Sketch the Solution. Define goals and ABC requirements for every screen. Use when asked to 'screen requirements', 'screen specs', 'define screens', or 'screen goals'."
---

# UX Phase 5 — Screen Requirements

Output "Read UX Screen Requirements skill." to chat to acknowledge you read this file.

Pipeline position: `/ux-user-stories` → `/ux-system-map` → `/ux-flow-diagram` → `/ux-model-attributes` → **`/ux-screen-requirements`** → `/ux-interface-design` → `/ux-test-driven-design`

> *Goals for each screen in a flow diagram. The purpose is to get a user to the next phase in UX.*

Define what every screen must contain so users know: where they are, what they can do, and where they can go. This is the hand-off document for UI designers.

## Prerequisites

- `flow-diagram.md` from Phase 3 (screen list and navigation paths)
- `attributes.md` from Phase 4 (data attributes per entity)
- `system-map.md` from Phase 2

## Steps

### Step 1 — Create 1-2 Goals
Invoke `/ux-create-screen-goals`
Define 1-2 primary goals for each screen in the flow diagram.

### Step 2 — Apply Inform → Engage → Invite
Invoke `/ux-inform-engage-invite`
Structure each screen's intent: inform the user (trust, context), engage them (show value), invite them forward (CTA).

### Step 3 — List Screen Attributes (ABC)
Invoke `/ux-list-screen-attributes`
For each screen define: A) what the user gets, B) what they can do, C) how they navigate next.

## Output

Generate `screen-requirements.md` containing:
- Per-screen goals table
- Per-screen Inform/Engage/Invite breakdown
- Per-screen ABC specification (Gets / Does / Navigates)
- Prioritized requirements (most important actions = most prominent)

## Rules

- Every screen must answer: "Where am I? What can I do? Where can I go?"
- Landing pages need trust elements: testimonials, press, featured customers
- Engage before asking for anything — show value first
- Prioritize requirements by user importance within each screen
- This document IS the designer hand-off if you have a UI designer

## Handoff

After completion, offer:

1. `/ux-interface-design` — proceed to Phase 6
2. `/sketch-the-solution` — return to orchestrator

If context is high, follow the standard handoff protocol (`@~/dotfiles/instructions/handoff.instructions.md`).
