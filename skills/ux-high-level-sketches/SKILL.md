---
name: ux-high-level-sketches
description: "Step 6.2 of Sketch the Solution. Create high-level component layout specs for each screen. Use when asked to 'sketch screens', 'high-level wireframes', 'rough sketches', 'layout specs', or 'component layout'."
---

# UX Step 6.2 — High-Level Sketches

Output "Read UX High-Level Sketches skill." to chat to acknowledge you read this file.

Phase: `/ux-interface-design` → Step 2 of 3

Create component-level layout specifications for each screen. Design in chunks: individual components first, then assemble into full screen layouts. ~1 minute per screen — speed over polish.

## Process

1. **Break each screen into chunks** (components):
   - Navigation (header, sidebar, breadcrumbs)
   - Content area (list, detail, form)
   - Actions (buttons, CTAs, toolbars)
   - Filters/search (if applicable)
   - Footer/secondary navigation

2. **For each chunk, define:**
   - What component type (card grid, table, form, modal, sidebar)
   - What data it displays (from attributes)
   - What actions it supports (from screen requirements B)
   - Where it sits in the layout (top, left, center, bottom)

3. **Generate component layout spec:**
```markdown
### [Screen Name] — Layout

**Header:** Logo | Nav: [Dashboard, Profile, Settings] | User menu
**Filters:** [Search bar] [Skill dropdown] [Location dropdown] [Clear]
**Content:** 2-column card grid
  - Each card: [Avatar | Name, Location | Skills tags | View button]
**Pagination:** [Previous] [1] [2] [3] [Next]
**Footer:** [About] [Help] [Terms]
```

4. **Create multiple variations** for high-impact screens (landing pages, dashboards):
```markdown
#### Variation A — Card Grid
[layout description]

#### Variation B — Table List  
[layout description]

#### Variation C — Map + Sidebar
[layout description]
```

5. **Apply the "sellable UI" filter** — only design value-demonstrating screens:
   - ✓ Design: landing, dashboard, browse, profiles, content
   - ✗ Skip: login, signup, admin, settings, user management

## Rules

- **Design in chunks** — components → screens → flows
- **Speed over polish** — ~1 minute per screen, iterate later
- **Sellable UI only** — skip screens that don't demonstrate value
- Create 2-3 variations for landing pages and core screens
- Include notes about design rationale alongside specs
- "If you catch yourself getting too detailed, do 10 pushups"

## Output

Append to `interface-design.md`: Per-screen component layout specs with variations.
