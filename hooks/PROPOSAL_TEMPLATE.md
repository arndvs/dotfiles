# Mechanism Proposal Template

Use this template when proposing a new hook or enforcement mechanism for ctrlshft.

---

## Proposal: [Hook Name]

### Problem Statement
_What failure mode, drift, or risk does this address? Link to a real incident or near-miss if possible._

### Mechanism Type
- [ ] PreToolUse (block before execution)
- [ ] PostToolUse (inspect after execution)
- [ ] SessionStart (session-level check)
- [ ] Stop (quality gate before session ends)
- [ ] PreCompact (context management)
- [ ] UserPromptSubmit (input-level check)

### Matcher
_Which tool does this hook match on? (e.g., Bash, Write, Read, or leave blank for unmatched events)_

### Fail Mode
- [ ] **Closed** — unhandled errors produce deny/block (for security-critical gates)
- [ ] **Open** — unhandled errors exit 0 (for advisory/info hooks with external deps)

### Behavior
_Describe the logic: what triggers it, what it checks, what outcome it produces._

### Decision: Block or Inform?
- [ ] **Block (exit 2)** — hard stop, agent cannot proceed
- [ ] **Inform (exit 0 + additionalContext)** — advisory, agent sees context but isn't blocked

_Justify: why is blocking/informing the right choice here?_

### Dependencies
_External tools required (jq, gh, git, etc.). If dependencies are optional, this must be fail-open._

### Per-Repo Config
_Does this need `.ctrlshft` overrides? If so, what keys?_

### Test Cases
1. **Should trigger:** _describe scenario_
2. **Should pass:** _describe scenario_
3. **Error path:** _describe what happens when deps are missing or input is malformed_

### Overlap Check
_Which existing hooks overlap? Could this be a gate added to an existing hook instead?_

---

## Acceptance Criteria
- [ ] Script has `FAIL_MODE:` on line 2
- [ ] Fail-closed hooks have `trap '_fail_closed' ERR`
- [ ] Registered in `settings-hooks.json`
- [ ] Row added to `hooks/README.md` table
- [ ] Tested with valid input, edge cases, and missing deps
- [ ] Committed and pushed
