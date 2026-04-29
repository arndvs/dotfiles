---
name: ux-list-screens
description: "Step 3.1 of Sketch the Solution. Derive the complete screen list from the system map. Use when asked to 'list screens', 'screen inventory', 'what screens do I need', or 'enumerate pages'."
---

# UX Step 3.1 — List Screens

Output "Read UX List Screens skill." to chat to acknowledge you read this file.

Phase: `/ux-flow-diagram` → Step 1 of 3

Derive every screen the product needs from the system map. Think of each screen as a "neighborhood" in a city.

## Process

1. **Walk through the system map** entity by entity:
   - Each entity that users interact with likely needs: a list/browse screen, a detail/view screen, a create/edit screen
   - System-level screens: landing page, login, signup, dashboard, settings

2. **Generate a combined screen list** (not separated by user type):
   - A "View Item" screen serves both user types — the flow determines what actions are available

3. **Output screen inventory table:**
```markdown
## Screen Inventory

| # | Screen Name | Purpose | Derived From |
|---|-------------|---------|--------------|
| 1 | Landing Page | Entry point, value proposition | System entry |
| 2 | Sign Up | Account creation | User entity |
| 3 | Login | Authentication | User entity |
| 4 | Dashboard | Main hub after login | System map |
| 5 | Member Directory | Browse/search members | Member entity |
| 6 | Member Profile | View member details | Member entity |
| 7 | Content Feed | Browse/filter content | Content entity |
| 8 | Create Content | Post new content | Content CRUD |
| 9 | View Content | Read content + comments | Content entity |
```

## Rules

- One combined list — don't separate by user type
- Don't do "premature optimization" — you can always add screens later
- Every CRUD operation may need its own screen (or a modal/section within a screen)
- Include screens for every entity interaction, not just the "sexy" features
- Settings and admin screens count too

## Output

Start `flow-diagram.md` with Screen Inventory table.
