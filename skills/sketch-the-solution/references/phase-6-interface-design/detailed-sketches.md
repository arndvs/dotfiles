# UX Step 6.3 — Detailed Sketches

Output "Read UX Detailed Sketches skill." to chat to acknowledge you read this file.

Phase: Phase 6 — Interface Design → Step 3 of 3

Develop detailed screen specifications with specific UI controls, interaction patterns, and state descriptions. Apply the EGHC simplification framework.

## Process

1. **Map each attribute to a UI control:**
   - Text → text input, textarea
   - Selection (few options) → radio buttons, toggle
   - Selection (many options) → dropdown, autocomplete
   - Multi-select → checkboxes, tag picker
   - Range → slider, number input
   - Date → date picker
   - Boolean → toggle switch, checkbox
   - File → file upload with preview
   - Rich text → rich text editor

2. **Apply EGHC simplification to every screen:**
   - **Eliminate** — remove anything not used 80% of the time
   - **Group** — combine related controls into sections/fieldsets
   - **Hide** — collapse secondary controls into expandable panels/menus
   - **Contextualize** — show controls only when needed (e.g., bulk actions appear only when items are selected)

3. **Define interaction states:**
   - Default state
   - Hover/focus state
   - Loading state
   - Empty state (no data yet)
   - Error state

4. **Generate detailed screen spec:**
```markdown
### [Screen Name] — Detailed Spec

**Layout:** [From high-level sketch, chosen variation]

**Components:**

#### [Component Name]
- **Type:** [e.g., "Filterable card grid"]
- **Controls:** [e.g., "Search: text input with autocomplete | Skill: multi-select dropdown | Location: autocomplete"]
- **Data displayed:** [e.g., "Avatar (48px circle), Name (h3), Location (subtitle), Skills (tag pills, max 3)"]
- **Actions:** [e.g., "Click card → Member Profile | Hover → show 'View' button"]
- **States:** Default: show first 12 cards | Empty: "No members match your filters" | Loading: skeleton cards

**EGHC Applied:**
- Eliminated: [what was removed and why]
- Grouped: [what was combined]
- Hidden: [what was collapsed]
- Contextualized: [what appears conditionally]

**Annotations:**
- [Design decision notes, e.g., "Cards over table because mobile-friendly"]
```

5. **Generate a developer-ready screen walkthrough:**
   - Walk through the screen as if narrating a video
   - Describe each interaction: "User clicks X, sees Y, then Z happens"

## Rules

- Every attribute from Phase 4 must map to a UI control
- Apply EGHC to every screen — document what you eliminated/grouped/hidden/contextualized
- Define empty states and error states, not just happy paths
- The detailed spec should be sufficient for a developer to build from
- Notes about WHY decisions were made are as valuable as the spec itself

## Output

Append to `interface-design.md`: Detailed screen specs with EGHC notes and interaction walkthrough.
