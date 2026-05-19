---
name: visual-feedback
description: "Add a visual feedback loop to frontend work. Use when implementing UI, checking dark/light mode, validating animations or interactions, or any time you need to see what the browser is actually rendering. Companion to do-work for frontend tasks."
---

# Visual Feedback

Output "Read Visual Feedback skill." to chat to acknowledge you read this file.

Pipeline position: sits inside **`/do-work`** → replaces the "look at the UI" step that LLMs otherwise skip.

## Why this exists

Backend feedback loops are fully textual — tests, types, lint. Frontend feedback loops are not. Without a browser, the LLM is flying blind: it can write code that passes typecheck and still produce a broken layout, a broken dark mode, or an animation that feels wrong. This skill closes that gap.

## Setup assumptions

- **VS Code browser** is available (Simple Browser or a browser preview panel pointed at the dev server)
- **Tavily MCP** is connected for web search when you hit something unfamiliar

## Workflow

### 1. Start the dev server

Before taking any screenshots, confirm the dev server is running and note the local URL (e.g. `localhost:5173`). If it isn't running, start it.

### 2. Open the VS Code browser

Open the Simple Browser pointed at the local URL. This is your visual ground truth for the session.

### 3. Implement a slice

Write the minimum code for one visual change — a component, a layout adjustment, a theme switch. Keep slices small so screenshots stay meaningful.

### 4. Screenshot and evaluate

Take a screenshot of the current state. Ask:

- Does the layout match the intent?
- Are there overflow, clipping, or alignment issues?
- Does it work at different viewport widths?
- If dark mode is relevant — does it render correctly under `prefers-color-scheme: dark`?

To emulate dark mode without a toggle, inject via devtools:
```js
// Force dark mode for screenshot
document.documentElement.classList.add('dark')
// or emulate media query via CDP if available
```

### 5. Iterate

If something looks wrong, fix it and screenshot again. Do not move on until the visual matches the intent. One slice, fully resolved, before the next.

### 6. Research with Tavily when stuck

If a CSS behaviour, browser quirk, or animation issue is unfamiliar, use Tavily to search before guessing:

```
tavily_search("css scroll snap momentum iOS Safari")
tavily_search("framer motion exit animation not triggering")
```

Prefer MDN, CSS-Tricks, and the relevant library's own docs. Do not iterate blindly on broken CSS — understand the mechanism first.

### 7. Validate the full page

Once a feature is complete, do a final sweep:

- [ ] Light mode
- [ ] Dark mode (if applicable)
- [ ] Mobile viewport (375px)
- [ ] Desktop viewport
- [ ] Any interactive states (hover, focus, active, disabled)
- [ ] Any loading/empty/error states

### 8. Hand back to do-work

Once the visual sweep is clean, return to the standard `/do-work` validate step (typecheck, tests) and commit.

## Notes

- Screenshots are context-heavy. Take targeted screenshots — specific components or states — rather than full-page dumps unless you need the full layout.
- If the browser MCP starts consuming too much context, switch to taking screenshots only at decision points rather than after every change.
- The goal is the same ad hoc testing a human dev does — not exhaustive E2E coverage, just confirming the thing you just built actually works.