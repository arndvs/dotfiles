# UX Phase 2 — System Map

Output "Read UX System Map skill." to chat to acknowledge you read this file.

Pipeline position: Phase 1 → 2 → 3 → 4 → 5 → 6 → 7 (see [parent SKILL](../SKILL.md))

> *Define relationships: has, being, does.*

Bridge the gap between problem discovery (user stories) and solution design (UI/screens). Translate narratives into a visual, structural representation of the system.

## Prerequisites

- `user-stories.md` from Phase 1 (with highlighted entities and actions)

## Steps

### Step 1 — Create System Map
[Create System Map](phase-2-system-map/create-system-map.md)
Identify core players (entities) and the actions they can take. Build an entity inventory from the highlighted nouns in user stories.

### Step 2 — Draw Relationships
[Draw Relationships](phase-2-system-map/draw-relationships.md)
Map how entities interact using labeled relationships (has, creates, edits, deletes, views, searches). Generate a Mermaid ERD.

## Output

Generate `system-map.md` containing:
- Entity inventory (grouped by category)
- Per-entity properties and actions
- Mermaid entity-relationship diagram
- CRUD verification (anything creatable must be editable + deletable)

## Rules

- Apply the CRUD model: if an entity can be created, it must also be editable and deletable
- System map is the "bridge" — transitioning from problem space into solution space
- Group related entities (e.g., individual members → "Members" category)
- Include ALL entities from stories, even minor ones

## Handoff

After completion, offer:

1. [phase-3-flow-diagram.md](phase-3-flow-diagram.md) — proceed to Phase 3
2. `/sketch-the-solution` — return to orchestrator

If context is high, follow the standard handoff protocol (`@~/dotfiles/instructions/handoff.instructions.md`).
