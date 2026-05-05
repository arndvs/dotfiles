# UX Step 5.1 — Create Screen Goals

Output "Read UX Create Screen Goals skill." to chat to acknowledge you read this file.

Phase: Phase 5 — Screen Requirements → Step 1 of 3

Every screen must have a clear purpose. Define 1-2 primary goals that answer: "Why does this screen exist? What should the user accomplish here?"

## Process

1. **Take each screen** from `flow-diagram.md`

2. **Define 1-2 goals per screen:**
   - What is the ONE thing a user should accomplish on this screen?
   - What's the secondary goal (if any)?

3. **Generate goals table:**
```markdown
## Screen Goals

| Screen | Goal 1 | Goal 2 |
|--------|--------|--------|
| Landing Page | Understand the value proposition | Sign up or log in |
| Dashboard | See overview of activity | Navigate to key features |
| Member Directory | Find members with specific skills | View member profiles |
| Content Feed | Discover relevant content | Post new content |
| Create Content | Publish content quickly | Tag/categorize properly |
| Member Profile | Understand member's expertise | Contact the member |
```

## Rules

- Maximum 2 goals per screen — if you need more, the screen is doing too much (split it)
- Goals must be user-centric ("find a member") not system-centric ("display member list")
- Every screen's goals must connect to at least one user story
- The goal drives what gets prominent placement on the screen

## Output

Start `screen-requirements.md` with Screen Goals table.
