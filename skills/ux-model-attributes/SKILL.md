---
name: ux-model-attributes
description: "Phase 4 of Sketch the Solution. List exhaustive attributes for every entity in the system map. Use when asked to 'model attributes', 'list attributes', 'data model', or 'entity attributes'."
---

# UX Phase 4 — Model Attributes

Output "Read UX Model Attributes skill." to chat to acknowledge you read this file.

Pipeline position: `/ux-user-stories` → `/ux-system-map` → `/ux-flow-diagram` → **`/ux-model-attributes`** → `/ux-screen-requirements` → `/ux-interface-design` → `/ux-test-driven-design`

> *Get as many as possible from user stories, surveys, and flow diagram.*

Create a comprehensive inventory of every data attribute for every entity. Aim for 20-25+ attributes per entity. Include even attributes you won't use in V1 — they inform future versions.

## Prerequisites

- `system-map.md` from Phase 2 (entities and relationships)
- `user-stories.md` from Phase 1
- `flow-diagram.md` from Phase 3

## Steps

### Step 1 — List Attributes
Invoke `/ux-list-attributes`
For each entity in the system map, brainstorm every possible attribute. Sources: user stories, customer interviews, existing reports/spreadsheets, competitor products.

## Output

Generate `attributes.md` containing:
- Per-entity attribute table (20-25+ attributes each)
- Attribute categories: functional, demographic, psychographic, security
- V1 vs. future version flags per attribute
- Source notation (where each attribute was discovered)

## Rules

- More is better — list everything, filter later
- Include demographics and psychographics for user entities
- Ask customers to send their current reports/spreadsheets — this reveals what matters
- Don't skip "boring" entity attributes (settings, admin) — Carl's ClinicMetrics bug was a missing attribute on a settings screen
- Note which attributes are V1 vs. deferred, but don't delete deferred ones

## Handoff

After completion, offer:

1. `/ux-screen-requirements` — proceed to Phase 5
2. `/sketch-the-solution` — return to orchestrator

If context is high, follow the standard handoff protocol (`@~/dotfiles/instructions/handoff.instructions.md`).
