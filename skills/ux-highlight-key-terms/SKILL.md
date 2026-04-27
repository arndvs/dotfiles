---
name: ux-highlight-key-terms
description: "Step 1.3 of Sketch the Solution. Extract entities (nouns) and actions (verbs) from user stories. Use when asked to 'highlight key terms', 'extract entities', 'identify nouns and verbs', or 'entity extraction'."
---

# UX Step 1.3 — Highlight Key Terms & Verbs

Output "Read UX Highlight Key Terms skill." to chat to acknowledge you read this file.

Phase: `/ux-user-stories` → Step 3 of 3

Parse completed user stories to extract two categories: **entities** (nouns — the key players/things) and **actions** (verbs — what they do). These become the foundation for the System Map in Phase 2.

## Process

1. **Read through each user story** and identify:
   - **Nouns/Entities:** People, roles, objects, documents, reports, data, content types
   - **Verbs/Actions:** Creates, searches, posts, views, edits, deletes, shares, contacts, applies

2. **Generate entity table:**
```markdown
## Entities (Nouns)

| Entity | Source Story | Category |
|--------|-------------|----------|
| Member | Ian's story | Person |
| Content | Ed's story | Object |
| Skills | Jordy's story | Attribute |
```

3. **Generate action table:**
```markdown
## Actions (Verbs)

| Action | Who | What | Source Story |
|--------|-----|------|-------------|
| searches | Member | Content | Ian's story |
| posts | Member | Content | Ed's story |
| views | Member | Profile | Jordy's story |
```

4. **Group entities** — find commonalities across stories:
   - Individual people (Ian, Amy, Ed) → "Members"
   - Facebook marketing, blog posts → "Content"
   - Products, projects → "Projects"

## Rules

- Extract from ALL stories, not just one
- Group similar entities into categories
- Verbs become relationships/actions in the system map
- Nouns become entities in the system map
- Don't filter yet — capture everything, refine in Phase 2

## Output

Append to `user-stories.md`: Entities table, Actions table, and Grouped Entity Categories.
