---
name: frontend-component-style
description: "Frontend component file structure and naming. Use when CREATING a new component, REFACTORING an existing one, SPLITTING a large file, EXTRACTING data or logic, or DECIDING where a piece of code should live. Triggers on phrases like 'build a component', 'scaffold this', 'sketch a layout', 'prototype this', 'extract this into', 'split this component', 'is this file too big', 'where should this live', 'promote to production'. Do NOT use for small edits, bug fixes, or style tweaks — path-gated rules cover those."
---

# Frontend Component Style

Output "Read Frontend Component Style skill." to chat to acknowledge you read this file.

This skill answers two structural questions: **where does each piece of code live**, and **what is each piece named**. Style concerns (Tailwind tokens, dark-mode variants, server/client split, animation, prop typing) are owned by the path-gated rules listed at the bottom — trust them; don't duplicate.

---

## Step 1 — Determine the mode

Single self-contained TSX files and four-layer split files are **opposite** structures. Always pick mode FIRST.

### Detection priority

1. **Explicit word in user request**
   - "prototype" / "sketch" / "draft" / "throwaway" / "experiment" / "mock up" → **Prototype**
   - "production" / "ship" / "real" / "extract" / "refactor" / "promote" → **Production**

2. **Context signals** (only if no explicit word)
   - File is in `prototypes/`, `sandbox/`, `experiments/`, `demos/` → Prototype
   - File is in `app/`, `src/components/`, `src/features/`, `lib/` → Production
   - Repo already has separated `*-content.ts` / `format-*.ts` files → Production
   - Repo has only inline-JSON single-file components → Prototype

3. **Ask** (if neither signal is decisive — DO NOT GUESS)
   > "Is this a prototype/sketch (single file with inline data) or production code (separated into data, logic, primitives, composed)?"

### Recording the choice

The first reply after invoking this skill MUST start with one line:

```
Mode: prototype
```
or
```
Mode: production
```

The choice persists for the rest of the conversation. The user overrides with one word ("make it production", "this is a prototype actually").

---

## Mode: Prototype

**When to use:** sketching an idea, exploring a layout, throwaway experiments, components destined for CMS handoff where speed matters more than long-term maintainability.

### File structure

- One self-contained `.tsx` file
- All content data in a single `componentData` JSON object at the top
- Helper functions inline below the data
- Subcomponents nested inside the same file

```tsx
// user-dashboard-card.tsx

import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";

// ===== Component Data =====
const componentData = {
  title: "User Dashboard",
  metrics: [
    { id: "users", label: "Active Users", value: "5,234", trend: "+12%" },
    { id: "revenue", label: "Monthly Revenue", value: "$12,345", trend: "+8%" },
  ],
};

// ===== Helper Functions =====
const formatTrend = (trend: string) => {
  const isPositive = trend.startsWith("+");
  return {
    value: trend,
    className: isPositive ? "text-green-500" : "text-red-500",
    icon: isPositive ? "↑" : "↓",
  };
};

// ===== Component =====
const UserDashboardCard = () => (
  <Card>
    <CardHeader><CardTitle>{componentData.title}</CardTitle></CardHeader>
    <CardContent>
      {componentData.metrics.map((metric) => (
        <MetricRow key={metric.id} {...metric} />
      ))}
    </CardContent>
  </Card>
);

// ===== Subcomponents =====
const MetricRow = ({ label, value, trend }: { label: string; value: string; trend: string }) => {
  const trendData = formatTrend(trend);
  return (
    <div>
      <span>{label}</span>
      <span>{value}</span>
      <span className={trendData.className}>{trendData.icon} {trendData.value}</span>
    </div>
  );
};

export default UserDashboardCard;
```

### Prototype guardrails

- If a prototype crosses ~250 lines or has 4+ subcomponents, mention it. Suggest promoting to production. Do not auto-promote.
- If an external dataset is already imported in the file, use it — don't refactor the data shape just to match the inline-JSON convention.
- Don't change website copy unless told to.

---

## Mode: Production — The Four Layers

**When to use:** code going into the main app, components that will be tested, reused, or maintained by others.

### The four layers

| Layer | Job | File suffix | Example |
|---|---|---|---|
| **Data** | Static content, CMS text, config | `*-content.ts` | `dashboard-metrics-content.ts` |
| **Logic** | Pure functions, formatters, transformers | verb-noun `.ts` | `format-metric-trend.ts` |
| **Primitive** | Single-element UI, no internal state | descriptive `.tsx` | `trend-badge.tsx` |
| **Composed** | Assembles primitives into a section | descriptive `.tsx` | `metric-card.tsx` |

### Dependency arrow (one direction only)

```
Page-level view → Composed → Primitive → Logic + Data
```

- **Data files** import nothing local; export typed content
- **Logic files** import nothing local; export pure functions
- **Primitives** import only Logic + types; never other Primitives
- **Composed** imports Primitives + types; owns no formatting
- **Page-level views** import Composed + Data; no logic, no formatting

### What it looks like

```ts
// dashboard-metrics-content.ts
export type DashboardMetric = {
  id: string;
  label: string;
  value: string;
  trend: number;
};

export const dashboardMetrics: DashboardMetric[] = [
  { id: "active-users", label: "Active Users", value: "5,234", trend: 12 },
  { id: "monthly-revenue", label: "Monthly Revenue", value: "$12,345", trend: 8 },
];
```

```ts
// format-metric-trend.ts
export type TrendDirection = "up" | "down" | "flat";

export const getTrendDirection = (trend: number): TrendDirection => {
  if (trend > 0) return "up";
  if (trend < 0) return "down";
  return "flat";
};

export const formatTrendLabel = (trend: number): string =>
  trend === 0 ? "No change" : `${trend > 0 ? "+" : ""}${trend}%`;
```

```tsx
// trend-badge.tsx
import { getTrendDirection, formatTrendLabel } from "@/lib/format-metric-trend";

interface TrendBadgeProps {
  trend: number;
}

const TrendBadge = ({ trend }: TrendBadgeProps) => {
  const direction = getTrendDirection(trend);
  return <span data-direction={direction}>{formatTrendLabel(trend)}</span>;
};

export default TrendBadge;
```

```tsx
// metric-card.tsx
import { Card, CardContent } from "@/components/ui/card";
import TrendBadge from "@/components/trend-badge";
import type { DashboardMetric } from "@/content/dashboard-metrics-content";

interface MetricCardProps {
  metric: DashboardMetric;
}

const MetricCard = ({ metric }: MetricCardProps) => (
  <Card>
    <CardContent>
      <span>{metric.label}</span>
      <span>{metric.value}</span>
      <TrendBadge trend={metric.trend} />
    </CardContent>
  </Card>
);

export default MetricCard;
```

```tsx
// dashboard-metrics-section.tsx (page-level view)
import { dashboardMetrics } from "@/content/dashboard-metrics-content";
import MetricCard from "@/components/metric-card";

const DashboardMetricsSection = () => (
  <section>
    {dashboardMetrics.map((metric) => (
      <MetricCard key={metric.id} metric={metric} />
    ))}
  </section>
);

export default DashboardMetricsSection;
```

### Production guardrails — when NOT to split

The four-layer rule is a **constraint on dependencies**, not a **minimum file count**. A 30-line component that passes the SRP test stays in one file. Don't extract:

- A formatter used in exactly one place that's three lines long
- A primitive used in exactly one place that doesn't need its own tests
- An EmptyState that appears exactly once and has no logic

Extract when there is **a second consumer**, **non-trivial logic**, or **a real testing need**.

---

## Naming (both modes)

### Files
- kebab-case always
- `.tsx` for components, `.ts` for logic and data
- Named after what they render or do — never after where they live or how they're used
- No generic names: `card.tsx`, `utils.ts`, `helpers.ts`, `mgr.ts`, `widget.tsx`
- No abbreviations unless universally understood (`url`, `id`, `api`)

### Components
- Specific noun phrase: `MetricTrendBadge`, `InvoiceLineItemRow`, `PlanUpgradeCallout`
- A reviewer scanning a file tree should know what each component renders without opening the file
- Forbidden: `Card`, `Item`, `Widget`, `Section`, `DisplayComponent`

### Functions
- **Returns a value** → noun phrase: `formatCurrency`, `getTrendDirection`, `buildInvoiceRows`
- **Performs an action** → verb phrase: `handlePlanUpgrade`, `submitBillingForm`, `downloadInvoicePdf`
- Event handlers name the action, not the event: `handlePlanUpgrade` not `handleClick`, `handleInvoiceDownload` not `handleSubmit`

### Types and interfaces
- Props interface = `<ComponentName>Props`
- Types named after the thing: `TrendDirection`, `PlanTier`, `InvoiceStatus`
- Forbidden: `Props` (collides), `ICard` (Hungarian), `T` (meaningless)

---

## File layout (within every file, both modes)

```
1. Imports
2. Types and interfaces
3. Content data (only if this file owns data)
4. Helper functions / hooks (Prototype mode only)
5. Component or function body
6. Subcomponents (Prototype mode only)
7. Default export
```

A reviewer should always know where to look for each kind of thing.

---

## SRP test (both modes)

> Describe what this does in one sentence without using "and".

- ✅ "Displays a metric value with a trend indicator"
- ✅ "Renders a list of invoice line items"
- ❌ "Shows the metric, handles the click, and formats the trend" → split into three

If you can't, split.

---

## Anti-patterns (both modes)

| Pattern | Problem | Fix |
|---|---|---|
| `const data = { ... }` inline in production code | Hides content inside presentation | Move to `<feature>-content.ts` |
| `utils.ts` with many unrelated functions | Impossible to navigate | One function (or one tightly related group) per file, named after what it does |
| `<Card />` as a component name | No hint of what it renders | `<UserBillingCard />`, `<MetricSummaryCard />` |
| `handleClick` / `handleSubmit` on a specific component | No hint of what is being acted on | `handlePlanUpgrade`, `handleInvoiceDownload` |
| Formatting logic inside JSX | Mixes concerns, hard to test | Extract to a named function in a logic file |
| Mixed `isLoading` / `isError` / `isEmpty` in one render block | Tangled conditional logic | Each state gets its own named branch or component |
| Production component with inline JSON data | Should have been promoted | Run the Promote workflow below |

---

## Promote: prototype → production

Triggered by phrases like *"promote to production"*, *"clean this up"*, *"extract this properly"*, *"this is going live"*.

1. **Extract content** — move the inline `componentData` object to `<feature>-content.ts` with a typed export.
2. **Extract logic** — move formatting/transformation functions to `<verb>-<noun>.ts` files (e.g. `format-metric-trend.ts`).
3. **Extract subcomponents** — each nested subcomponent becomes its own file, named after what it renders.
4. **Re-aim the original file** — it becomes a Composed or page-level view that imports content + primitives only. No formatting, no inline data.
5. **Apply path-gated rules** — server/client split, dark-mode tokens, Tailwind grouping etc. (these auto-load when you edit the new files).
6. **Update mode** — record `Mode: production` in your next reply so the rest of the conversation uses production rules.

---

## Path-gated rules already in effect

These auto-load when you edit matching files. **Do not duplicate their content here.** Trust them.

| Rule | Scope |
|---|---|
| `rules/dark-mode.md` | `**/*.{tsx,jsx,css,scss}` — DMDS tokens, dark variants |
| `rules/tailwind-shadcn.md` | `**/*.{tsx,jsx}` — Tailwind grouping, shadcn imports, responsive |
| `rules/server-vs-client-components.md` | `**/app/**/*.{tsx,jsx}` — server-first, error handling |
| `rules/framer-motion.md` | `**/*.{tsx,jsx}` — animation philosophy, reduced motion |
| `rules/typescript-conventions.md` | `**/*.{ts,tsx}` — props/types, parameter style |
| `rules/frontend-conventions.md` | `**/*.{ts,tsx,js,jsx,...}` — browser baseline |

If a question is covered by a path-gated rule (Tailwind syntax, dark-mode tokens, when to use `'use client'`), defer to the rule. This skill answers structure and naming only.
