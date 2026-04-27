---
name: ux-create-flow-diagram
description: "Step 3.2 of Sketch the Solution. Map navigation paths between screens as a Mermaid flowchart. Use when asked to 'create flow diagram', 'user flow', 'navigation map', or 'screen flow diagram'."
---

# UX Step 3.2 — Create Flow Diagram

Output "Read UX Create Flow Diagram skill." to chat to acknowledge you read this file.

Phase: `/ux-flow-diagram` → Step 2 of 3

Turn the screen inventory into a navigation flow. Map which screen leads to which, based on user actions and user type.

## Process

1. **Start from the landing page** and map outward:
   - Landing → Sign Up / Login
   - Login → Dashboard / Main View
   - Dashboard → Browse / Create / Profile / Settings

2. **Annotate paths by user type:**
   - Paths available to all users: unmarked
   - Paths specific to user type A: labeled `[A]`
   - Paths specific to user type B: labeled `[B]`

3. **Apply the Instant Gratification principle:**
   - Let users see value BEFORE asking for login/signup
   - Show the product before requesting credentials

4. **Generate Mermaid flowchart:**
```mermaid
flowchart TD
    Landing[Landing Page] --> SignUp[Sign Up]
    Landing --> Login[Login]
    Landing --> Browse[Browse Content]
    Login --> Dashboard[Dashboard]
    SignUp --> Dashboard
    Dashboard --> Profile[My Profile]
    Dashboard --> ContentFeed[Content Feed]
    Dashboard --> MemberDir[Member Directory]
    ContentFeed --> ViewContent[View Content]
    ContentFeed --> CreateContent[Create Content]
    MemberDir --> MemberProfile[Member Profile]
```

5. **Include navigation back-paths** — not just forward flow (e.g., Sign Out → Landing, Back to Dashboard)

## Rules

- Every screen must be reachable from at least one other screen
- Every screen must have at least one exit path
- Mark user-type-specific paths clearly
- Show value before asking for credentials (Instant Gratification)
- Design the IDEAL flow first — cut to MVP later

## Output

Append to `flow-diagram.md`: Mermaid flowchart with user-type annotations.
