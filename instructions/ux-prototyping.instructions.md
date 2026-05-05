---
description: "UX/UI prototyping orchestrator — component design philosophy, CMS-replaceable static data, file naming. Path-gated rules cover dark mode, Tailwind/shadcn, server/client components, and Framer Motion."
---
Output "Read UX Prototyping instructions." to chat to acknowledge you read this file.

# UX/UI Prototyping Guidelines

- Never change website copy unless told to

## Objective

Develop isolated components that developers can easily implement within a large headless CRM project. Each component should be self-contained with all utilities, Tailwind styles, and functionality in a single TSX file. Include JSON data at the top to populate text and images, facilitating future integration with a headless CMS. The caveat here is that if an external component data set is already being brought in, use that data set rather than refactoring the data set to then bring it into the component.

Be sure to review the Source Lib folder which contains hooks, styles, types, and utils for existing reusable functionality rather than creating from scratch. It's okay to create from scratch, however, if it already exists in the lib or any of this lib subdirectories, we should be using those pre-existing components rather than recreating new ones from scratch.

## File Naming Conventions

- Use kebab-case for all file names
  - ✅ `user-profile.tsx`, `auth-layout.tsx`, `api-utils.ts`
  - ❌ `userProfile.tsx`, `AuthLayout.tsx`, `apiUtils.ts`
- Use `.tsx` extension for React components
- Use `.ts` extension for utility files
- Use lowercase for all file names
- Separate words with hyphens
- Do not use spaces or underscores

## Path-Gated Rules

The following path-gated rules auto-load when editing matching files. Trust them; do not duplicate their contents here.

- `rules/dark-mode.md` — DMDS tokens and dark variants (`**/*.{tsx,jsx,css,scss}`)
- `rules/tailwind-shadcn.md` — Tailwind/shadcn conventions and responsive design (`**/*.{tsx,jsx}`)
- `rules/server-vs-client-components.md` — Server-first defaults, client-component scope, error handling (`**/app/**/*.{tsx,jsx}`)
- `rules/framer-motion.md` — Animation philosophy, scroll-triggered reveals, performance (`**/*.{tsx,jsx}`)
- `rules/typescript-conventions.md` — Props/TS interfaces, parameter style (`**/*.{ts,tsx}`)

## Component Structure Best Practices

### 1. DRY (Don't Repeat Yourself)

- Extract repeated logic into helper functions
- Create reusable UI elements for patterns that appear multiple times
- Use loops for rendering similar elements rather than duplicating JSX
- Maintain a single source of truth for data and configuration

### 2. Data Management

- Place all content data in a JSON object at the top of the file (unless a JSON object is already being imported into the file):

  ```tsx
  const componentData = {
    title: "Dashboard Overview",
    description: "View all your key metrics in one place",
    ctaText: "Explore Features",
    metrics: [
      { label: "Active Users", value: "5,234", icon: "users" },
      { label: "Conversion Rate", value: "3.2%", icon: "chart" },
    ],
    images: {
      hero: "/images/dashboard-hero.png",
      background: "/images/pattern-bg.svg",
    },
  };
  ```

- Separate data structure from presentation
- Include all text, labels, URLs, and image paths in this data object
- Use descriptive keys that align with their purpose in the UI

### 3. Component Organization

- Follow a logical structure:
  1. Data/configuration objects
  2. Helper functions/hooks
  3. Main component
  4. Subcomponents
- Export only the main component as default
- Keep subcomponents nested within the file scope

### 4. State Management

- Use appropriate React hooks for state:
  - `useState` for simple component state
  - `useReducer` for complex state logic
  - `useContext` for deeply nested component requirements
- Minimize state; derive values where possible
- Handle loading, error, and empty states explicitly

### 5. Accessibility Considerations

- Include proper ARIA attributes
- Ensure keyboard navigation works correctly
- Maintain sufficient color contrast (WCAG AA minimum)
- Use semantic HTML elements appropriately
- Implement proper focus management
- Ensure animations don't interfere with accessibility
- Always use helper hooks from `@/lib/hooks/use-animation-variants` for automatic accessibility support
- Above-fold content must use CLS-safe variants to prevent layout shift

### 6. Component Documentation

- Add JSDoc comments describing the component's purpose:

  ```tsx
  /**
   * Dashboard card component that displays key metrics with icons.
   * Supports customization through the componentData object.
   * Uses shadcn components and Framer Motion animations.
   *
   * @example
   * <DashboardCard />
   */
  ```

- Document any complex logic with inline comments
- Include usage examples in comments
- Note any dependencies or requirements

## Implementation Example

```tsx
// user-dashboard-card.tsx
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import {
  useContainerVariants,
  useItemVariants,
} from "@/lib/hooks/use-animation-variants";
import { AnimatePresence, motion } from "framer-motion";

// ===== Component Data =====
const componentData = {
  title: "User Dashboard",
  subtitle: "Welcome back to your dashboard",
  metrics: [
    { id: "users", label: "Active Users", value: "5,234", trend: "+12%" },
    { id: "revenue", label: "Monthly Revenue", value: "$12,345", trend: "+8%" },
    {
      id: "conversion",
      label: "Conversion Rate",
      value: "3.2%",
      trend: "-0.5%",
    },
  ],
  cta: {
    text: "View Detailed Analytics",
    url: "/analytics",
  },
  images: {
    background: "/images/dashboard-bg.svg",
    avatar: "/images/user-avatar.png",
  },
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
const UserDashboardCard: React.FC = () => {
  const containerVars = useContainerVariants();
  const itemVars = useItemVariants();

  return (
    <motion.div
      initial="hidden"
      whileInView="visible"
      viewport={{ once: true, margin: "-100px" }}
      variants={containerVars}
    >
      <Card className="mx-auto max-w-2xl overflow-hidden">
        <CardHeader className="bg-card text-card-foreground">
          <CardTitle>{componentData.title}</CardTitle>
          <p className="text-muted-foreground">{componentData.subtitle}</p>
        </CardHeader>

        <CardContent className="p-6">
          <motion.div
            className="grid grid-cols-1 gap-4 md:grid-cols-3"
            variants={containerVars}
          >
            {componentData.metrics.map((metric) => (
              <MetricCard key={metric.id} {...metric} />
            ))}
          </motion.div>

          <motion.div className="mt-8" variants={itemVars}>
            <Button variant="default" asChild>
              <a href={componentData.cta.url}>{componentData.cta.text}</a>
            </Button>
          </motion.div>
        </CardContent>
      </Card>
    </motion.div>
  );
};

// ===== Subcomponents =====
interface MetricProps {
  id: string;
  label: string;
  value: string;
  trend: string;
}

const MetricCard: React.FC<MetricProps> = ({ label, value, trend }) => {
  const trendData = formatTrend(trend);
  const itemVars = useItemVariants();

  return (
    <motion.div
      variants={itemVars}
      whileHover={{ scale: 1.03, transition: { duration: 0.2 } }}
      className="bg-secondary border-border flex flex-col rounded-lg border p-4"
    >
      <span className="text-muted-foreground text-sm">{label}</span>
      <span className="text-foreground mt-1 text-2xl font-bold">{value}</span>
      <span className={`mt-2 flex items-center text-sm ${trendData.className}`}>
        {trendData.icon} {trendData.value}
      </span>
    </motion.div>
  );
};

export default UserDashboardCard;
```
