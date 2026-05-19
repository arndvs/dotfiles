---
name: skill-scaffolder
description: "Meta-skill for creating new agent skills that involve multi-step automation, browser navigation, state tracking, evidence capture, and both local (VS Code Insiders) and VPS (Playwright) execution. Use when the user wants to 'create a skill', 'build a new skill', 'scaffold a skill', 'make a skill for X', or describes a multi-step agentic workflow they want to automate."
---

# Skill Scaffolder

Output "Read Skill Scaffolder skill." to chat to acknowledge you read this file.

Creates production-ready agent skills that follow the proven agentic pipeline architecture: Python scripts provide the scaffolding (state management, config, error handling), while the VS Code Copilot agent provides the runtime muscle (browser interactions, code analysis, decision-making).

---

## When to Use This Skill

- User says "create a skill", "build a skill", "scaffold a skill", "make a skill for X"
- User describes a multi-step workflow they want automated
- User wants a scraper, auditor, documenter, or any browser-automation pipeline
- User references the citation-builder-skill and wants something similar

## Pre-Scaffolding Interview

Before generating any files, ask the user these questions to determine which patterns the skill needs. Ask questions one at a time:

1. **Skill name** — kebab-case name (e.g., `repo-portfolio`, `competitor-scraper`)
2. **What it does** — one-sentence summary of the pipeline
3. **Skill type** — Is this an **automation pipeline** (browser, state, orchestrator) or a **knowledge/workflow skill** (instructions + optional references)?

If skill type = **knowledge/workflow**, skip to the [Lightweight Skill Path](#lightweight-skill-path) section below.

If skill type = **automation pipeline**, continue:

4. **Work unit** — What does each iteration process? (a URL, a file, a repo, a feature, a page)
5. **Phases** — What are the major steps? (user describes in plain language, you formalize into phases)
6. **Browser needed?** — Does the skill need to navigate web pages?
7. **State tracking?** — Does the user want Google Sheets tracking, local JSON, or SQLite?
8. **Authentication?** — Does the skill need to create/manage accounts on external services?
9. **Evidence capture?** — Does the skill need screenshots or video?
10. **Execution environment** — Local VS Code only, VPS only, or dual-mode?
11. **Data source** — What's the input data? (JSON file, CSV, Google Sheet, git repo, URL list)

Skip questions where the answer is obvious from context. For example, if the user says "scrape these 50 URLs and screenshot each", you know: work unit = URL, browser = yes, evidence = yes.

---

## Lightweight Skill Path

For knowledge/workflow skills that don't need scripts, state stores, or orchestrators. Use this path when:

- The skill encodes **process knowledge** (how to do X)
- Operations are **non-deterministic** (require agent judgment)
- There's no iteration loop or batch processing
- The same code would NOT be generated repeatedly

**Structure:**

```
{skill-name}/
├── SKILL.md           # Main instructions (required, ≤100 lines)
├── REFERENCE.md       # Detailed docs (if SKILL.md would exceed 100 lines)
├── EXAMPLES.md        # Usage examples (if patterns are complex)
└── scripts/           # Only if deterministic operations exist
    └── helper.js
```

**When to add scripts** (even in lightweight skills):

- Operation is deterministic (validation, formatting, linting)
- Same code would be generated repeatedly without it
- Errors need explicit handling that the agent shouldn't improvise

Scripts save tokens and improve reliability vs. regenerated code.

**When to split into separate files:**

- SKILL.md exceeds 100 lines
- Content has distinct domains (different audiences or contexts)
- Advanced features are rarely needed by the agent

After generating a lightweight skill, proceed to the [Quality Checklist](#quality-checklist) section.

---

## Architecture Decision Matrix

Based on the interview answers, select which modules to include:

| Question                 | If YES, include                         | If NO, skip                        |
| ------------------------ | --------------------------------------- | ---------------------------------- |
| Browser needed?          | `browser_adapter.py` + screenshot tools | Omit browser modules               |
| State tracking = Sheets? | `sheets_client.py` + `setup_sheet.py`   | Use `state_store.py` (JSON/SQLite) |
| Authentication?          | `credential_vault.py`                   | Omit vault                         |
| Evidence capture?        | `screenshot_manager.py`                 | Omit screenshots                   |
| Dual-mode execution?     | `browser_adapter.py` with both adapters | Single adapter only                |
| Email verification?      | `email_handler.py`                      | Omit email                         |

**Always include** (every skill gets these):

- `SKILL.md`
- `config.example.json` + `config.json`
- `scripts/__init__.py`
- `scripts/shared_utils.py`
- `scripts/session_logger.py`
- `scripts/preflight.py`
- `scripts/run_{name}.py` (main orchestrator)

---

## Skill Directory Structure

Every generated skill follows this layout:

```
{skill-name}/
├── SKILL.md                          ← agent instructions (most important file)
├── config.json                       ← user's actual config (gitignored if has secrets)
├── config.example.json               ← committed template with placeholders
├── references/
│   ├── setup.md                      ← environment setup guide
│   └── {domain-specific}.md          ← domain knowledge docs
└── scripts/
    ├── __init__.py                   ← makes scripts/ a package
    ├── shared_utils.py               ← env loading, config, paths, circuit breaker
    ├── session_logger.py             ← JSONL audit trail
    ├── preflight.py                  ← Phase 0 validation
    ├── run_{name}.py                 ← main orchestrator
    └── {domain-specific modules}     ← varies per skill
```

---

## File Generation Order

Generate files in this exact order. Each file must be complete, production-ready, with no TODOs or placeholders in code (config templates may have `YOUR_*_HERE` placeholders).

**Code generation rules (apply to ALL generated Python files):**

- No `# comment` lines — do not comment generated code (by convention)
- No `pass` statements — every method must have a real implementation
- No commented-out code — if a pattern has `CUSTOMIZE:` markers, replace them with actual code
- All imports must resolve — no dangling references
- `self.state` must be initialized to a real state store instance (not None/commented-out)
- `self.browser` may be `None` in VS Code mode — the agent provides browser interaction via MCP tools
- Docstrings are allowed (they're documentation, not comments) — use them on phase methods for agent instructions

### Step 1: `config.example.json`

Template config with all required keys. Sensitive values use `YOUR_*_HERE` placeholders.

```json
{
  "skill_specific_section": {
    "key": "YOUR_VALUE_HERE"
  },
  "state_store": {
    "type": "sheets|json|sqlite",
    "spreadsheet_id": "YOUR_SPREADSHEET_ID_HERE",
    "tab_name": "Main",
    "summary_tab": "Summary"
  },
  "output": {
    "evidence_path": "./evidence/",
    "report_path": "./output/"
  },
  "session": {
    "max_items_per_session": 50,
    "item_cooldown_seconds": 5,
    "circuit_breaker_threshold": 5
  }
}
```

### Step 2: `scripts/__init__.py`

```python
"""Run entry points from the project root:
    python -m scripts.run_{name} --config config.json
    python -m scripts.preflight --config config.json
"""
```

### Step 3: `scripts/shared_utils.py`

Generate using **Patterns 1, 2, and 3** from `references/pattern-catalog.md`. Customize:

- `_ENV_FILES` paths (keep `~/dotfiles/secrets/.env.agent` as primary, `.env.secrets` for credentials)
- Env var names for config overrides (use `{SKILL_PREFIX}_*` naming)
- `REQUIRED_CONFIG` dict for `validate_config()`
- `NOTE_MAX_LEN` constant

Must include these functions:

- `load_env()` / `ensure_env()` — idempotent env loading from `~/dotfiles/secrets/.env.agent` and `.env.secrets`
- `resolve_path(p)` — expand `~` and resolve to absolute
- `discover_credentials(config)` — GCP service account auto-discovery (only if using Sheets)
- `load_config(config_path)` — JSON load + env var overlay
- `validate_config(config)` — required key validation
- `due_date(days)` — date offset helper

Must include these classes:

- `CircuitBreaker(threshold)` — consecutive failure tracking

### Step 4: `scripts/session_logger.py`

Generate using **Pattern 11** from `references/pattern-catalog.md`. The only customization: rename the `work_unit` parameter in `log_event()` and `log_error()` if a more specific name fits the skill's domain.

### Step 5: `scripts/screenshot_manager.py` (if evidence capture needed)

Generate using **Pattern 12** from `references/pattern-catalog.md`. Customize only:

- `STEP_ORDER` list — replace with the workflow steps for this skill's domain
- `unit_dir()` method name — rename if a more specific name fits (e.g., `repo_dir()`)

The class structure (timestamped filenames, step ordering, `capture()` that never throws) stays identical.

### Step 6: `scripts/sheets_client.py` + `scripts/setup_sheet.py` (if Google Sheets state store)

Generate the `SheetsClient` using **Pattern 4** from `references/pattern-catalog.md`. Customize:

- `COL` dict — column index mapping for the new skill's schema
- `HEADERS` list — column header names
- `STATUS_CODES` set — valid statuses for this skill
- `SKIP_ON_STARTUP` set — statuses that mean "done"
- `get_pending_items()` — filter + sort logic for work queue

Also generate `scripts/setup_sheet.py` — a one-time script that calls `SheetsClient.setup_headers()` and `write_summary()` to initialize the spreadsheet. Follow the citation-builder-skill's `scripts/setup_sheet.py` pattern: load config, create client, write headers, print spreadsheet URL.

### Step 7: `scripts/state_store.py` (if JSON/SQLite state store — alternative to Sheets)

Generate using **Pattern 5** from `references/pattern-catalog.md`. The `JsonStateStore` class is a drop-in replacement for `SheetsClient` — same interface (`get_all_items`, `get_pending_items`, `update_item`, `set_status`, `add_item`, `write_summary`) but backed by an atomic-write JSON file instead of Google Sheets API.

### Step 8: `scripts/browser_adapter.py` (if browser needed)

Generate using **Pattern 8** from `references/pattern-catalog.md`. Includes the `BrowserAdapter` ABC and `PlaywrightAdapter` concrete class.

**Important:** In VS Code mode, the agent does NOT instantiate a Python adapter. Instead, the agent directly uses VS Code browser tools (`open_browser_page`, `click_element`, `type_in_page`, `screenshot_page`, `read_page`) following the phase method docstrings. The `PlaywrightAdapter` is only used for VPS headless execution.

### Step 9: `scripts/credential_vault.py` (if authentication needed)

Generate using **Pattern 7** from `references/pattern-catalog.md`. Full AES-256 Fernet encrypted vault. Only include if the skill creates accounts on external services.

### Step 10: `scripts/preflight.py`

Generate using **Pattern 6** from `references/pattern-catalog.md`. Each check prints ✓/✗, collects all errors, fails at end with summary.

Standard checks for every skill:

1. Config structure valid
2. Required env vars set
3. Output directories writable
4. Data source accessible

Conditional checks:

- Google Sheets connectivity (if Sheets state store)
- Vault key valid (if credential vault)
- Playwright browsers installed (if VPS mode)
- Dev server port available (if starting a server)

### Step 11: `scripts/run_{name}.py` — Main Orchestrator

This is the most important generated file. The orchestrator follows the **Pattern 9 (Error Boundary Structure)** from `references/pattern-catalog.md`.

**Mandatory structure:**

1. `__init__` must assign `self.state` to the actual state store instance (SheetsClient or JsonStateStore) — never leave it as None or commented out
2. `__init__` must create `self.logger`, `self.breaker`, and set session limits from config
3. `run()` calls preflight, iterates pending items, enforces session limit and circuit breaker
4. `_run_item()` has three try/except zones: pre-execution → point-of-no-return → post-execution
5. Each `_phase_N_name()` method has a docstring starting with `Agent:` that tells the agent what to do
6. Phase methods return `{"skip": False, ...}` with agent-discovered values
7. State store is updated after every phase — never left un-persisted

**Generation rules:**

- Replace `{Name}` with PascalCase skill name (e.g., `PortfolioRunner`)
- Replace `{name}` with snake_case skill name (e.g., `portfolio`)
- Import the ACTUAL state store class (not a comment) — `from scripts.sheets_client import SheetsClient` or `from scripts.state_store import JsonStateStore`
- Import all domain-specific modules the phases need
- Write real phase methods with populated result dicts (not placeholder comments)
- No comment lines in generated code (by convention)
- Entry point uses `argparse` with `--config`, `--item`, `--dry-run` flags
- If browser-based: add `self.browser = None` and runtime check in `run()`

### Step 12: `SKILL.md`

The most critical file. This is what the agent reads to understand how to operate the skill. Follow this structure:

**Description formatting rules** (the description is the ONLY thing the agent sees when choosing skills):

- Max 1024 characters
- Write in third person
- Single sentence combining what the skill does and when to invoke it (e.g., "Builds X when the user asks to Y or mentions Z")
- Be specific enough to distinguish from other skills with similar domains

```markdown
---
name: { skill-name }
description: >
  {Single sentence: what it does and when to invoke it.
  Max 1024 chars. Third person. Specific enough to distinguish from similar skills.}
---

# {Skill Title}

{One-sentence summary of what this skill does.}

---

## First-Time Setup

{Step-by-step setup instructions. Include:

- Venv activation
- Dependency installation
- Config file creation
- Service account / API key setup
- State store initialization
- Pre-flight check}

---

## File Structure

{Complete directory listing with one-line descriptions}

---

## Config Template

{Full config.json example with all keys}

---

## Phase Overview

{Table: Phase | What it does}

---

## Running

{CLI commands for: full run, single item, dry run, preflight only}

---

## State Store Schema

{Table: columns/fields, types, descriptions}

## Status Codes

{List of all valid statuses with descriptions}

---

## Error Recovery & Circuit Breaker

{Table: error type → recovery action}

---

## Rate Limiting

{Delays, cooldowns, session limits}
```

**SKILL.md line budget:** If the generated SKILL.md exceeds 100 lines, move advanced sections (Error Recovery, Rate Limiting, State Store Schema) into `references/` and link to them from SKILL.md.

### Step 13: `references/setup.md`

Environment setup guide covering:

- Python venv activation
- Google credentials (if Sheets)
- Playwright installation (if VPS mode)
- Required env vars with export commands

### Step 14: `references/troubleshooting.md`

Common errors and fixes, organized by category. Follow the citation-builder-skill's `references/troubleshooting.md` structure:

- **Submission/Execution Errors** — domain-specific failures with remediation
- **Account/Auth Errors** — login, registration, credential issues
- **Browser/Automation Errors** — page load, JS errors, form state
- **State Store Errors** — Sheets API quota, JSON corruption, column mismatch
- **Circuit Breaker Triggers** — investigation steps and common systemic causes
- **Manual Queue Resolution** — table of manual items with typical resolution time

---

## Phase Method Guidelines

When writing phase methods for the orchestrator, follow these rules:

1. **Docstring is the agent interface.** The docstring tells the agent what to do. Start agent instructions with `Agent:` prefix.

2. **Return a dict with `skip: bool`.** Every phase can signal the orchestrator to skip remaining phases for this work unit.

3. **Initialize result with None/defaults.** The agent fills in discovered values.

4. **Update state store after processing.** Never leave state un-persisted between phases.

5. **Pre-execution phases wrap in try/except → mark failed.** Post-execution phases → append notes only, never revert status.

6. **Phase boundaries are the resume points.** If the skill crashes, it picks up at the last un-completed phase.

---

## Naming Conventions

| Item                 | Convention                  | Example                         |
| -------------------- | --------------------------- | ------------------------------- |
| Skill directory      | `kebab-case`                | `repo-portfolio`                |
| Python modules       | `snake_case.py`             | `feature_discovery.py`          |
| Orchestrator class   | `PascalCase + Runner`       | `PortfolioRunner`               |
| Config env prefix    | `UPPER_SNAKE`               | `PORTFOLIO_`                    |
| State store columns  | `snake_case`                | `feature_name`                  |
| Status codes         | `snake_case`                | `in_progress`                   |
| Evidence directories | `sanitized_domain`          | `github_com_user_repo`          |
| Session logs         | `session_{timestamp}.jsonl` | `session_20260402_143022.jsonl` |

---

## VS Code Browser Tools Reference

When a skill uses browser automation in VS Code mode, the agent uses these deferred tools (load via `tool_search` before first use):

| Tool                | Purpose                        |
| ------------------- | ------------------------------ |
| `open_browser_page` | Navigate to a URL              |
| `read_page`         | Get page DOM/text content      |
| `click_element`     | Click by selector or text      |
| `type_in_page`      | Fill form fields               |
| `screenshot_page`   | Capture page state             |
| `hover_element`     | Hover for tooltips/dropdowns   |
| `handle_dialog`     | Accept/dismiss browser dialogs |
| `navigate_page`     | Go back/forward/reload         |
| `drag_element`      | Drag and drop                  |

The SKILL.md must instruct the agent to load these tools before starting browser phases.

---

## Playwright VPS Reference

For VPS/headless mode, the generated skill includes `browser_adapter.py` with `PlaywrightAdapter`. The entry point script handles Playwright lifecycle:

```python
import os
MODE = os.environ.get("SKILL_MODE", "vscode")

if MODE == "playwright":
    from playwright.sync_api import sync_playwright
    from scripts.browser_adapter import PlaywrightAdapter

    with sync_playwright() as p:
        browser = p.chromium.launch(headless=True)
        page = browser.new_page()
        adapter = PlaywrightAdapter(page)
        runner = MyRunner(config_path)
        runner.browser = adapter
        runner.run()
        browser.close()
```

---

## Quality Checklist

After generating all files, run through `references/skill-checklist.md` — it contains the full 50+ item QA checklist covering structure, SKILL.md completeness, Python code quality, config/secrets, state management, error handling, browser automation, Google Sheets, and evidence/logging.

**Quick review (verify these regardless of skill type):**

- [ ] Description includes triggers ("Use when...")
- [ ] Description is ≤1024 chars, third person, distinguishable from similar skills
- [ ] SKILL.md is ≤100 lines (split to references/ if over)
- [ ] No time-sensitive info (dates, versions that will age)
- [ ] Consistent terminology (same noun for same concept throughout)
- [ ] Concrete examples included (not just abstract descriptions)
- [ ] References are one level deep (no reference chains)

---

## Example: Generating a Portfolio Skill

User says: _"Create a skill that audits a GitHub repo, identifies all features, spins up the frontend, screenshots each feature, and generates a portfolio document."_

**Interview answers (inferred):**

1. Name: `repo-portfolio`
2. Summary: Audit a repo, discover features, run locally, document with screenshots
3. Work unit: feature/route
4. Phases: clone → analyze → discover features → install deps → start server → screenshot features → generate report
5. Browser: Yes (need to navigate the running app)
6. State: Google Sheets (user wants visibility)
7. Auth: No (public repos, local server)
8. Evidence: Yes (screenshots at multiple viewports)
