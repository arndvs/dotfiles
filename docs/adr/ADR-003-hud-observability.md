# ADR-003 — HUD observability architecture

**Status:** Accepted
**Date:** 2026-05-12
**Author:** Aaron Davis
**Deciders:** Maintainer (sole, at this stage)

---

## Context

AI coding sessions are opaque. Once an agent starts working, there is no visibility into which instructions it loaded, which rules it followed or violated, how many events occurred, or what compliance state the session is in. When something goes wrong — a rule was ignored, a secret was nearly exposed, a session ran longer than intended — the only diagnostic tool was scrolling through chat history.

This problem compounds with autonomous (AFK) execution, where no human is watching. An AFK loop that silently ignores rules or leaks credentials produces damage that is only discovered after the fact.

---

## Decision

A lightweight **HUD (Heads-Up Display) daemon** provides real-time observability into agent sessions via three transport layers and a browser-based UI.

### Architecture

```
Event Producers                      HUD Daemon (hud-daemon.js)             Consumers
─────────────                        ──────────────────────────             ─────────
hooks/hud-session.sh    ──┐          port 7823 (HTTP REST API)      ──►    Browser UI (hud/index.html)
hooks/hud-reads.sh      ──┤          port 7822 (WebSocket)          ──►    Real-time dashboard
detect-context.sh       ──┼──►       Named pipe (working/hud.pipe)         SQLite persistence
detect-client.sh        ──┤          JSONL fallback (events.jsonl)         In-memory buffers
skills (write_hud_event)──┤
ctrlshft-claude wrapper ──┘
```

### Transport cascade

Events are emitted via `write-hud-state.sh` (sourced, not executed). The emitter tries three transports in priority order — never blocks, never fails loudly:

1. **Named pipe** (`working/hud.pipe`) — <1ms latency, real-time
2. **HTTP POST** to `/api/event` — ~5ms fallback
3. **JSONL append** to `working/events.jsonl` — file-based fallback for Docker/AFK environments

### Persistence

- **Primary:** SQLite via optional `better-sqlite3` (tables: `events`, `sessions`, `violations`, `loaded_files`)
- **Fallback:** In-memory ring buffers + JSONL file if SQLite is unavailable

### Event types

| Type | Meaning |
|------|---------|
| `context` | Context detection result on `cd()` |
| `read` | Instruction, skill, or rule file loaded |
| `info` | Milestone event (skill started, commit made, audit complete) |
| `compliance_update` | Compliance audit result |
| `pass` / `fail` / `warn` | Individual compliance check outcomes |

### UI

`hud/index.html` — single-page dark-themed dashboard with WebSocket live updates, search, and project filtering.

---

## Consequences

**Positive:**

- Real-time visibility into what the agent loaded and what it's doing
- Compliance violations are surfaced immediately, not discovered in post-mortem
- AFK loops become auditable — every event is persisted and queryable
- Zero-dependency daemon (Node.js only) — no external services required

**Negative:**

- Another process to manage — the daemon must be running for observability (graceful fallback to JSONL when it's not)
- SQLite dependency is optional but recommended for persistence across daemon restarts
- Named pipe transport is not available on all platforms (falls back to HTTP/JSONL)

**Neutral:**

- The HUD is read-only — it observes but does not influence agent behavior. Enforcement stays in hooks and rules.
- Event emission is fire-and-forget — agent performance is not affected by HUD availability

---

## Alternatives considered

**Log file only:** Append events to a structured log, analyze post-session. Rejected because it provides no real-time visibility — the primary use case is watching AFK loops live.

**External observability service (Datadog, Sentry):** Adds a cloud dependency and credential management for a local development tool. Rejected to maintain the zero-dependency, self-contained design principle.

**VS Code extension:** Build observability into the editor. Rejected because it would not work for CLI-only sessions or AFK loops running on a VPS.
