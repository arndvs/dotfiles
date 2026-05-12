# Enforcement Coverage Matrix

Maps failure modes to their enforcement mechanisms. Use this to identify gaps and prioritize new hooks.

## Legend

| Symbol | Meaning |
|--------|---------|
| ✅ | Enforced mechanically (hook blocks/warns) |
| 📋 | Documented in instructions (model compliance) |
| ⚠️ | Partial coverage (some cases handled) |
| ❌ | No enforcement |

## Git Safety

| Failure Mode | Mechanism | Type | Coverage |
|---|---|---|---|
| Direct commit to protected branch | `git-workflow-gate.sh` Gate 1 | PreToolUse/Block | ✅ |
| Non-conventional commit message | `git-workflow-gate.sh` Gate 1 | PreToolUse/Block | ✅ |
| Force push without `--force-with-lease` | `git-workflow-gate.sh` Gate 2 | PreToolUse/Block | ✅ |
| Push when behind remote | `git-workflow-gate.sh` Gate 2 | PreToolUse/Block | ✅ |
| Branch switch with dirty tree | `git-workflow-gate.sh` Gate 3 | PreToolUse/Block | ✅ |
| `cd` + `git` in one command (wrong repo) | `git-workflow-gate.sh` Gate 0 | PreToolUse/Block | ✅ |
| Push without PR | `git-post-push.sh` | PostToolUse/Info | ✅ |
| Stale/merged branches accumulating | `stale-branches.sh` | SessionStart/Info | ✅ |
| Work stranded (not pushed) | `global.instructions.md` | Instruction | 📋 |

## Security

| Failure Mode | Mechanism | Type | Coverage |
|---|---|---|---|
| Credential exposure via echo/cat | `secret-guard.sh` | PreToolUse/Block | ✅ |
| Bare env/printenv dumps all vars | `secret-guard.sh` | PreToolUse/Block | ✅ |
| Direct read of secrets files | `secret-guard.sh` | PreToolUse/Block | ✅ |
| Piped installs (curl \| sh) | `secret-guard.sh` | PreToolUse/Block | ✅ |
| Hardcoded secrets in source | `env-security.md` rule | Path-gated instruction | 📋 |

## Database Safety

| Failure Mode | Mechanism | Type | Coverage |
|---|---|---|---|
| Migration targeting production | `migration-guard.sh` | PreToolUse/Block | ✅ |
| Migration without rollback plan | `migration-safety.md` rule | Path-gated instruction | 📋 |
| Destructive schema changes | `migration-safety.md` rule | Path-gated instruction | 📋 |

## Code Quality

| Failure Mode | Mechanism | Type | Coverage |
|---|---|---|---|
| TypeScript type errors on stop | `typecheck.sh` | Stop/Block | ✅ |
| Formatting drift on stop | `format-check.sh` | Stop/Info | ✅ |
| Scaffolding without a plan | `plan-quality-gate.sh` | PreToolUse/Info | ✅ |
| Over-engineering / gold-plating | `global.instructions.md` | Instruction | 📋 |

## Context Management

| Failure Mode | Mechanism | Type | Coverage |
|---|---|---|---|
| Auto-compaction losing context | `compaction-guard.sh` | PreCompact/Block | ✅ |
| Context warning at capacity | `context-warning.sh` | UserPromptSubmit | ⚠️ (stub) |
| No handoff on session end | `handoff.instructions.md` | Instruction | 📋 |

## Gaps (Identified, Not Yet Addressed)

| Failure Mode | Proposed Mechanism | Status |
|---|---|---|
| Session ends without quality check | Session Close Skill (`/check`) | Slice 4 — planned |
| Cross-session errors repeating | Error Audit Skill | Slice 7 — planned |
| Tests not run before push | QA integration hook | Slice 12 — planned |
