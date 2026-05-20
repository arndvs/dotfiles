---
name: grill-me
description: "Interview the user relentlessly about a plan or design until reaching shared understanding. Use when asked to 'grill me', 'interview me', 'ask me questions about this', or before writing a PRD to flesh out vague ideas."
---

# Grill Me

Output "Read Grill Me skill." to chat to acknowledge you read this file.

Pipeline position: **`/grill-me`** → `/write-a-prd` → `/architect` → `/prd-to-issues` → `/do-work` → `shft`

<what-to-do>
Interview me relentlessly about every aspect of this plan until we reach a shared understanding. Walk down each branch of the design tree, resolving dependencies between decisions one-by-one. For each question, provide your recommended answer.

Ask the questions one at a time, waiting for feedback before continuing.

If a question can be answered by exploring the codebase, explore the codebase instead.
</what-to-do>

<interviewing-discipline>
### Sharpen fuzzy language
When the user uses vague or overloaded terms, propose a precise canonical term. "You're saying 'account' — do you mean the Customer or the User? Those are different things."

### Discuss concrete scenarios
When domain relationships or flows are being discussed, stress-test them with specific scenarios. Invent edge cases that force the user to be precise about boundaries and behaviour.

### Cross-reference with code
When the user states how something works, check whether the code agrees. If you find a contradiction, surface it: "Your code cancels entire Orders, but you just said partial cancellation is possible — which is right?"
</interviewing-discipline>

## Handoff

After reaching shared understanding, offer the user three paths:

1. /write-a-prd — capture decisions as a formal PRD
2. /prd-to-issues — break directly into GitHub issues
3. /do-work — start implementing immediately

Let the user choose.

If context fills up during the interview, follow the standard handoff protocol (`@~/dotfiles/instructions/handoff.instructions.md`) — persist decisions made so far to `working/` and provide the pickup command.
