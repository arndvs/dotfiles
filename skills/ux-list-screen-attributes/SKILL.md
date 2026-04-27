---
name: ux-list-screen-attributes
description: "Step 5.3 of Sketch the Solution. Define ABC spec for each screen: what user gets, does, and how they navigate. Use when asked to 'screen attributes', 'ABC spec', 'screen requirements list', or 'what goes on each screen'."
---

# UX Step 5.3 — List Screen Attributes (ABC)

Output "Read UX List Screen Attributes skill." to chat to acknowledge you read this file.

Phase: `/ux-screen-requirements` → Step 3 of 3

For each screen, create a concrete specification: what the user gets (sees), what they can do (actions), and how they navigate to the next screen.

## Process

1. **For each screen**, define three sections drawing from `attributes.md` and `flow-diagram.md`:

```markdown
### [Screen Name]

**A — What the user gets (sees/receives):**
- [e.g., "List of member snippets: avatar, name, skills, location"]
- [e.g., "Content preview: title, summary, author, date, tags"]
- [e.g., "Dashboard metrics: activity count, recent posts"]

**B — What the user can do (actions):**
- [e.g., "Search by keyword", "Filter by skill/location"]
- [e.g., "Sort by date/relevance", "Post new content"]
- [e.g., "Edit profile", "Delete content"]

**C — How they navigate next:**
- [e.g., "Click member → Member Profile"]
- [e.g., "Click content → View Content"]
- [e.g., "Navigation bar → Dashboard, Profile, Settings"]
```

2. **Define snippets** — condensed preview representations of entities in list views:
   - What 3-5 fields represent this entity at a glance?
   - What makes a user want to click to see more?

3. **Prioritize within each section** — most important items first. The most important action should be the most prominent on the screen.

4. **Cross-reference against the system map** — ensure every entity's CRUD operations have corresponding screen actions.

## Rules

- Every screen must have all three sections (A, B, C)
- Snippets are critical for list/directory screens — define them explicitly
- Prioritize by user importance, not alphabetically
- Cross-reference the flow diagram for navigation (C section)
- Cross-reference attributes for content (A section)
- This + the IEI framework = complete designer hand-off document

## Output

Append to `screen-requirements.md`: Per-screen ABC specification with prioritized attributes.
