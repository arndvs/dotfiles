#!/usr/bin/env bash
# FAIL_MODE: closed
# compaction-guard.sh — PreCompact hook: block automatic compaction, enforce handoff.
#
# Receives Claude Code PreCompact JSON on stdin (matcher: "auto").
# Exits 2 (block) to prevent auto-compaction and direct the agent to handoff.
#
# Rationale: compaction loses nuance and accumulates errors. The policy in
# global.instructions.md says "prefer clearing context and starting fresh over
# compacting." This hook enforces that mechanically instead of relying on the
# model to remember the instruction.
#
# Manual /compact is unaffected — the matcher only fires on "auto" triggers.
# If compaction was triggered to recover from a context-limit API error,
# blocking it surfaces the underlying error and fails the current request.
# At 95%+ context, the session should end anyway.

set -euo pipefail

# --- Fail-closed trap: any unhandled error = block compaction ---
_fail_closed() {
    echo 'compaction-guard: unhandled error — blocking (fail-closed)' >&2
    exit 2
}
trap '_fail_closed' ERR

cat > /dev/null  # consume stdin

cat >&2 <<'EOF'
⛔ Auto-compaction blocked by compaction-guard hook.

Context window is nearly full. Do NOT compact — follow the handoff protocol:

1. Commit all current work (atomic commits, one logical change each)
2. Write remaining plan to working/<topic>.md
3. Tell the user: "Context is full. Here's the pickup command for a fresh session:"
4. Provide the pickup command with file references

Manual /compact is still available as an escape hatch if needed.
EOF
exit 2
