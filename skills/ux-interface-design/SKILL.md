---
name: ux-interface-design
description: "Phase 6 of Sketch the Solution. Create wireframe variations per screen from screen requirements. Use when asked to 'design interface', 'wireframes', 'create UI', 'interface design', or 'sketch screens'."
---

# UX Phase 6 — Interface Design

Output "Read UX Interface Design skill." to chat to acknowledge you read this file.

Pipeline position: `/ux-user-stories` → `/ux-system-map` → `/ux-flow-diagram` → `/ux-model-attributes` → `/ux-screen-requirements` → **`/ux-interface-design`** → `/ux-test-driven-design`

> *Create variations of each screen based on screen requirements.*

Transform screen requirements into visual interface specs. Focus on "sellable UI" — only design screens that demonstrate value to the customer. Skip admin, login, and user management for now.

## Prerequisites

- `screen-requirements.md` from Phase 5
- `flow-diagram.md` from Phase 3
- `attributes.md` from Phase 4

## Steps

### Step 1 — Get Inspired from UI Patterns
Invoke `/ux-get-inspired`
Research established UI patterns relevant to each screen type. Reference Pattern Tap, Dribbble, competitor products.

### Step 2 — High-Level Sketches
Invoke `/ux-high-level-sketches`
Create component layout specs for each screen (~1 minute per screen). Design in chunks: individual components first, then assemble into screens.

### Step 3 — Detailed Sketches
Invoke `/ux-detailed-sketches`
Develop detailed screen specs with specific UI controls, component types, and interaction patterns.

## Output

Generate `interface-design.md` containing:
- Per-screen inspiration references
- Per-screen component layout (high-level)
- Per-screen detailed specification with UI control types
- EGHC simplification notes (what was Eliminated, Grouped, Hidden, Contextualized)
- Multiple variations for key screens (especially landing pages)

## Rules

- **Sellable UI only** — design value-demonstrating screens, skip admin/login
- **Design in chunks** — components → screens → flows (not full pages at once)
- Apply **EGHC simplification**: Eliminate (remove what's not used 80% of the time), Group (combine related), Hide (collapse into menus), Contextualize (show only when needed)
- Create multiple variations for landing pages and high-impact screens
- Speed over polish — "the name of the game is speed"
- Notes about design decisions alongside specs

## Handoff

After completion, offer:

1. `/ux-test-driven-design` — proceed to Phase 7
2. `/sketch-the-solution` — return to orchestrator

If context is high, follow the standard handoff protocol (`@~/dotfiles/instructions/handoff.instructions.md`).
