---
name: ux-six-mistakes
description: "Step 7.2 of Sketch the Solution. Validate test plan against the six common user testing mistakes. Use when asked to 'six mistakes', 'testing anti-patterns', 'validate test plan', or 'user testing checklist'."
---

# UX Step 7.2 — Six Mistakes of User Testing

Output "Read UX Six Mistakes skill." to chat to acknowledge you read this file.

Phase: `/ux-test-driven-design` → Step 2 of 2

Apply Amir Khella's "Six Mistakes of User Testing" as a validation checklist against your test plan. Catch anti-patterns before running sessions.

## Process

1. **Review the test plan against each anti-pattern:**

```markdown
## Six Mistakes Checklist

### 1. Testing too late
- ✓/✗ Are you testing BEFORE building, not after?
- ✓/✗ Are you testing prototypes/wireframes, not finished products?
- Fix: Test as early as possible — even paper sketches are testable

### 2. Leading the user
- ✓/✗ Do your questions avoid suggesting the answer?
- ✓/✗ Are questions open-ended ("What would you do?") not closed ("Would you click this?")?
- Fix: Replace leading questions with observational prompts

### 3. Testing with the wrong people
- ✓/✗ Are test participants actual target users (matching your avatars)?
- ✓/✗ Are you avoiding friends/family who will be too polite?
- Fix: Test with prospects from ID calls, not convenience samples

### 4. Explaining too much
- ✓/✗ Does the test let users figure things out on their own?
- ✓/✗ Are you observing confusion rather than preemptively explaining?
- Fix: Show the screen, stay quiet, observe where they get stuck

### 5. Taking feedback literally
- ✓/✗ Are you interpreting BEHAVIOR, not just WORDS?
- ✓/✗ Are you watching what they DO, not just what they SAY?
- Fix: "Users lie" — observe actions, not stated preferences

### 6. Not iterating
- ✓/✗ Are you planning multiple rounds of testing?
- ✓/✗ Will you update the design between sessions?
- Fix: Plan 3+ iterations; design is done when feedback becomes predictable
```

2. **Score the test plan:**
   - 6/6 passes → ready to test
   - Any failures → fix before running sessions

3. **Define the "done" signal:**
```markdown
## Design Completion Criteria

Design is DONE when:
- [ ] Feedback from users is predictable (you can guess what they'll say)
- [ ] You can correctly predict what users will do at each step
- [ ] 3+ iterations have been completed
- [ ] Hidden benefits have been captured and priced
- [ ] Price anchors support the planned pricing model
```

## Rules

- Review BEFORE running any test sessions
- Fix anti-patterns in the test plan before proceeding
- The predictability test is the real "done" signal — not a fixed number of sessions
- Design completion feeds directly into `/architect` for implementation planning

## Output

Append to `test-plan.md`: Six Mistakes checklist with pass/fail, completion criteria.
