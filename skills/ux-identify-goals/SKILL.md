---
name: ux-identify-goals
description: "Step 1.1 of Sketch the Solution. Identify goals for each user type/avatar. Use when asked to 'identify user goals', 'define user goals', 'map user types', or 'list personas'."
---

# UX Step 1.1 — Identify Goals

Output "Read UX Identify Goals skill." to chat to acknowledge you read this file.

Phase: `/ux-user-stories` → Step 1 of 3

Identify every distinct user avatar and define what they're trying to accomplish. Each user type has different goals, pain points, and workflows.

## Process

1. **List all user types** from ID calls and customer interviews. Include obvious AND non-obvious users (Carl's Tesla mistake: forgot in-store staff, only considered online buyers).
2. **For each user type, define:**
   - Who they are (role, demographics, tech comfort level)
   - What they're trying to accomplish (1-3 primary goals)
   - What frustrates them about the current process
   - What devices/tools they currently use
3. **Output a structured persona table:**

```markdown
## User Avatars

### [Avatar Name] — [Role]
- **Demographics:** [age range, tech proficiency, context]
- **Goals:**
  1. [Primary goal]
  2. [Secondary goal]
- **Current Pain:** [What frustrates them today]
- **Devices/Tools:** [What they use now]
```

## Rules

- Include ALL user types — not just the primary customer
- Consider: end users, admins, managers, support staff, external stakeholders
- Goals describe what users WANT, not what your product does
- Source everything from real customer data, not assumptions

## Output

Append to `user-stories.md`: User Avatars section with persona table.
