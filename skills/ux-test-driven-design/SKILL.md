---
name: ux-test-driven-design
description: "Phase 7 of Sketch the Solution. Plan user testing sessions and validate designs. Use when asked to 'test design', 'user testing', 'validate UI', 'test driven design', or 'get feedback on design'."
---

# UX Phase 7 — Test Driven Design

Output "Read UX Test Driven Design skill." to chat to acknowledge you read this file.

Pipeline position: `/ux-user-stories` → `/ux-system-map` → `/ux-flow-diagram` → `/ux-model-attributes` → `/ux-screen-requirements` → `/ux-interface-design` → **`/ux-test-driven-design`**

> *Decide what you want to test first. Testing is its own process.*

Design is "done" when customer feedback becomes predictable — when you can correctly predict what users will do and say at each step. Until then, iterate.

## Prerequisites

- `interface-design.md` from Phase 6
- Prospect list from idea extraction
- All prior artifacts for reference

## Steps

### Step 1 — User Testing
Invoke `/ux-user-testing`
Create a structured test plan with per-screen questions. Design the feedback session script.

### Step 2 — Six Mistakes Review
Invoke `/ux-six-mistakes`
Apply Amir Khella's "Six Mistakes of User Testing" as a validation checklist against your test plan.

## Output

Generate `test-plan.md` containing:
- Test session script (intro, expectations, walkthrough structure)
- Per-screen question list (benefit probing, value assessment)
- Price anchoring capture template
- Hidden benefits tracking table
- Iteration log (version → feedback → changes)
- Six Mistakes checklist (pass/fail per anti-pattern)

## Rules

- **NEVER email prototypes for feedback** — always walk through live on screen share
- Always record feedback sessions
- Set expectations: "This is rough. Tell me what sucks. Nothing is final."
- Ask benefit questions at every screen: "How would this help you?"
- Track price anchors: "How much time/money would this save?"
- Plan for 3+ iterations before asking for the sale
- Design is done when feedback becomes predictable

## Handoff

After completion, offer:

1. `/architect` — create implementation plan from validated UX artifacts
2. `/do-work` — begin building the product
3. `/write-a-prd` — formalize into a PRD
4. `/sketch-the-solution` — return to orchestrator

If context is high, follow the standard handoff protocol (`@~/dotfiles/instructions/handoff.instructions.md`).
