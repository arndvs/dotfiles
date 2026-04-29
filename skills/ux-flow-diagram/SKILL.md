---
name: ux-flow-diagram
description: "Phase 3 of Sketch the Solution. List screens, draw navigation flows, validate against user stories. Use when asked to 'create flow diagram', 'map user flows', 'screen flow', or 'navigation diagram'."
---

# UX Phase 3 — Flow Diagram

Output "Read UX Flow Diagram skill." to chat to acknowledge you read this file.

Pipeline position: `/ux-user-stories` → `/ux-system-map` → **`/ux-flow-diagram`** → `/ux-model-attributes` → `/ux-screen-requirements` → `/ux-interface-design` → `/ux-test-driven-design`

> *How users move on the site and how that accomplishes their goals.*

Define screen-level architecture and navigation paths. Each screen is a "neighborhood" in a city; the flow is the "streets" connecting them. You are the GPS guiding users from their starting point to their goal.

## Prerequisites

- `user-stories.md` from Phase 1
- `system-map.md` from Phase 2

## Steps

### Step 1 — List Screens
Invoke `/ux-list-screens`
Derive the complete list of screens from the system map. One combined list — not separated by user type.

### Step 2 — Create Flow Diagram
Invoke `/ux-create-flow-diagram`
Map navigation paths between screens. Annotate paths by user type. Generate a Mermaid flowchart.

### Step 3 — Validate with User Stories
Invoke `/ux-validate-flow`
Walk through each user story against the flow diagram. Verify every user can get from entry to goal. Identify missing screens.

## Output

Generate `flow-diagram.md` containing:
- Screen inventory table
- Mermaid flowchart with user-type-annotated paths
- Validation log (each story traced through the flow)
- Gaps identified and resolved
- MVP scope (ideal system → V1 cut)

## Rules

- Design the IDEAL system first, then cut to MVP later
- Apply the Instant Gratification principle: show value before asking for login/signup
- Keep the screen list combined (a "View Item" screen serves all user types)
- Don't spend more than ~30 minutes equivalent per step — move fast, iterate

## Handoff

After completion, offer:

1. `/ux-model-attributes` — proceed to Phase 4
2. `/sketch-the-solution` — return to orchestrator

If context is high, follow the standard handoff protocol (`@~/dotfiles/instructions/handoff.instructions.md`).
