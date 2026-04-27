---
name: ux-create-system-map
description: "Step 2.1 of Sketch the Solution. Identify core players and actions from entity inventory. Use when asked to 'create system map', 'identify entities', 'core players', or 'entity inventory'."
---

# UX Step 2.1 — Create System Map

Output "Read UX Create System Map skill." to chat to acknowledge you read this file.

Phase: `/ux-system-map` → Step 1 of 2

Take the grouped entities and actions from Phase 1 and build a structured entity inventory with their properties and capabilities.

## Process

1. **Take the entity categories** from `user-stories.md` (grouped nouns)

2. **For each entity, define three dimensions:**
   - **Has** — what properties/sub-entities does it possess?
   - **Being** — what is its identity/role/state?
   - **Does** — what actions can it take?

3. **Apply the CRUD model** — for every action, verify completeness:
   - If an entity can be **Created**, it must also be **Editable** and **Deletable**
   - Add missing CRUD operations

4. **Generate entity inventory:**
```markdown
## Entity: [Name]

**Has:** [list of properties/sub-entities]
**Being:** [identity, role, states]
**Does:** [actions — create, edit, delete, view, search, filter, share]
**CRUD Check:** ✓ Create / ✓ Read / ✓ Update / ✓ Delete
```

## Rules

- Every entity from the stories must appear in the inventory
- Apply CRUD to every entity — no exceptions
- Include properties you'll defer past V1 (flag them but don't delete)
- Group minor entities under major ones where appropriate

## Output

Start `system-map.md` with Entity Inventory section.
