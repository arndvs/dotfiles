---
name: ux-user-stories
description: "Phase 1 of Sketch the Solution. Write pain-state user stories per avatar, highlight entities and actions. Use when asked to 'write user stories', 'user stories', 'capture user goals', or starting the UX process."
---

# UX Phase 1 — User Stories

Output "Read UX User Stories skill." to chat to acknowledge you read this file.

Pipeline position: **`/ux-user-stories`** → `/ux-system-map` → `/ux-flow-diagram` → `/ux-model-attributes` → `/ux-screen-requirements` → `/ux-interface-design` → `/ux-test-driven-design`

> *What versus how. Capture imagination and magic.*

Write empathy-driven narratives that describe every user's current pain, workflow, environment, and emotions — BEFORE any solution design begins.

## Prerequisites

- Customer avatar(s) from idea extraction
- ID call notes / interview transcripts
- Understanding of user pain points

## Steps

### Step 1 — Identify Goals
Invoke `/ux-identify-goals`
Define goals for each user type. Identify every distinct user avatar and what they're trying to accomplish.

### Step 2 — Write User Story
Invoke `/ux-write-user-story`
Write a pain-state narrative for each avatar/goal. Describe the CURRENT challenge, not your solution.

### Step 3 — Highlight Key Terms & Verbs
Invoke `/ux-highlight-key-terms`
Extract entities (nouns) and actions (verbs) from stories into structured tables. These feed directly into the System Map.

## Output

Generate `user-stories.md` containing:
- Avatar profiles with goals
- Narrative user stories (pain-state, per avatar)
- Entity table (highlighted nouns)
- Action table (highlighted verbs)
- Formal user story templates: "As a [role], I want to [behavior], so that [value]"

## Rules

- Stories describe the CURRENT pain — never how your product solves it
- Write stories for EVERY user type, not just the primary one
- Find "the need behind the need" — ask WHY at every step
- Stories are living documents — update after future customer calls

## Handoff

After completion, offer:

1. `/ux-system-map` — proceed to Phase 2
2. `/sketch-the-solution` — return to orchestrator

If context is high, follow the standard handoff protocol (`@~/dotfiles/instructions/handoff.instructions.md`).
