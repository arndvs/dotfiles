# UX Step 4.1 — List Attributes

Output "Read UX List Attributes skill." to chat to acknowledge you read this file.

Phase: Phase 4 — Model Attributes → Step 1 of 1

For each entity in the system map, brainstorm every possible attribute. Aim for 20-25+ per entity. More is better — list everything, filter later.

## Process

1. **Take each entity** from `system-map.md`

2. **Brainstorm attributes from multiple sources:**
   - User stories (what properties are mentioned?)
   - Customer interviews (what do they track today?)
   - Customer-sent materials (reports, spreadsheets, existing processes)
   - Competitor products (what fields do they have?)
   - Flow diagram (what data does each screen need?)

3. **Categorize each attribute:**
   - **Functional** — name, email, title, description, status, date
   - **Demographic** — age, gender, location, marital status
   - **Psychographic** — tech proficiency, app preferences, experience level
   - **Security** — password, role, permissions, verification status

4. **Flag V1 vs. deferred:**
```markdown
## Entity: [Name]

| # | Attribute | Type | Category | V1? | Source |
|---|-----------|------|----------|-----|--------|
| 1 | name | string | functional | ✓ | stories |
| 2 | email | string | functional | ✓ | stories |
| 3 | avatar_url | string | functional | ✓ | competitor |
| 4 | linkedin_url | string | functional | ✗ | Amir's trust pattern |
| 5 | tech_proficiency | enum | psychographic | ✗ | interview |
```

5. **Target 20-25 attributes per entity** — if you have fewer, dig deeper.

## Rules

- Ask customers for their current reports/spreadsheets — they reveal what matters
- Don't skip "boring" entities (settings, admin) — that's where hidden bugs live
- Write down ALL attributes even if you won't use them in V1
- Every entity from the system map must have an attribute table
- Note the source of each attribute (story, interview, competitor, flow)

## Output

Generate `attributes.md` with per-entity attribute tables.
