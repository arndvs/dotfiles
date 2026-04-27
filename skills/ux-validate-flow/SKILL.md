---
name: ux-validate-flow
description: "Step 3.3 of Sketch the Solution. Cross-check flow diagram against user stories to find gaps. Use when asked to 'validate flow', 'test user flow', 'check flow against stories', or 'flow validation'."
---

# UX Step 3.3 — Validate with User Stories

Output "Read UX Validate Flow skill." to chat to acknowledge you read this file.

Phase: `/ux-flow-diagram` → Step 3 of 3

Read each user story and trace the path through the flow diagram. Identify missing screens, dead ends, and friction points.

## Process

1. **For each user story**, trace the user's journey through the flow:
   - What screen do they start on?
   - What do they do at each step?
   - Can they reach their goal via the available screens?
   - How many screens/clicks to reach their goal?

2. **Log each validation:**
```markdown
## Flow Validation Log

### [Avatar]'s Story: [Goal]
- **Entry:** Landing Page
- **Path:** Landing → Login → Dashboard → Content Feed → Search → View Content
- **Goal reached:** ✓ Yes / ✗ No
- **Gaps found:** [e.g., "No comment feature — user expects to reply but no screen supports it"]
- **Friction:** [e.g., "3 clicks to reach content — could be 2"]
```

3. **Fix gaps** — add missing screens or paths to the flow diagram

4. **Identify MVP scope** — highlight which screens/paths are essential for V1:
```markdown
## MVP Scope

| Screen | MVP? | Rationale |
|--------|------|-----------|
| Landing | ✓ | Entry point |
| Login | ✓ | Required |
| Dashboard | ✓ | Core experience |
| Reports | ✗ | V2 — nice to have |
```

## Rules

- Every user story must have a complete, traceable path through the flow
- Gaps found = screens or features to add (iterate the flow diagram)
- MVP = what's definitely not going to change + most benefit for least effort
- Promise the vision, deliver incrementally

## Output

Append to `flow-diagram.md`: Validation Log, Gap Analysis, and MVP Scope table.
