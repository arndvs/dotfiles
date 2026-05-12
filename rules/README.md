# Rules

Path-gated coding conventions (Tier 3). Each rule loads only when the agent touches files matching its `paths` glob pattern.

## How Rules Load

Rules use YAML frontmatter with a `paths` field (list of globs). When the agent edits a file matching any glob, the rule is loaded automatically. Rules without a matching glob stay dormant — zero overhead for irrelevant stacks.

## Rule Inventory

| Rule | `paths` | Enforces |
|------|---------|----------|
| `dark-mode.md` | `**/*.{tsx,jsx,css,scss}` | DMDS surface tokens, dark variants for all components |
| `env-security.md` | `**/.env*`, `**/secrets/**`, `**/credentials*` | No hardcoded secrets; environment variables via `run-with-secrets.sh` |
| `framer-motion.md` | `**/*.{tsx,jsx}` | Scroll-triggered reveals, no hero animations, CLS-safe, reduced-motion |
| `frontend-conventions.md` | `**/*.{ts,tsx,js,jsx,mjs,cjs,css,scss,html,svelte,vue}` | Modern web APIs, baseline browser support (Feb 2026) |
| `git-conventions.md` | `**/*.{ts,tsx,js,jsx,mjs,cjs,py,rb,go,rs,java,php,sh,bash,md,yml,yaml,json}` | Atomic commits, conventional messages, clean diffs |
| `javascript-modern.md` | `**/*.{ts,tsx,js,jsx,mjs,cjs}` | Modern JS APIs — Set methods, `Object.groupBy`, Iterator helpers |
| `migration-safety.md` | `**/migrations/**`, `**/prisma/migrations/**` | Backwards-compatible migrations, rollback paths, nullable-first |
| `server-vs-client-components.md` | `**/app/**/*.{tsx,jsx}` | Default Server Components, minimal `'use client'`, server fetches |
| `tailwind-shadcn.md` | `**/*.{tsx,jsx}` | shadcn CSS variables, class grouping, mobile-first, component variants |
| `terminal-workarounds.md` | `**/bin/**`, `**/*.sh`, `**/*.bash` | VS Code heredoc workarounds, background server output redirect |
| `test-conventions.md` | `**/*.test.*`, `**/*.spec.*`, `**/__tests__/**`, `**/services/**` | describe/it structure, one assertion per behavior, mock at boundaries |
| `typescript-conventions.md` | `**/*.{ts,tsx}` | Object params, `satisfies`, explicit interfaces, `noUncheckedIndexedAccess` |

## Adding a Rule

1. Create `rules/your-rule.md`
2. Add YAML frontmatter:
   ```yaml
   ---
   description: "What this rule enforces"
   paths:
     - "**/*.{ts,tsx}"
   ---
   ```
3. Write the convention content below the frontmatter
4. Auto-discovered — no registration needed. Re-run `ctrl bootstrap` to propagate.
