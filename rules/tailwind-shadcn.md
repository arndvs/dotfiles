---
description: "Tailwind + shadcn conventions — color variables, class grouping, component imports, responsive design."
paths:
  - "**/*.{tsx,jsx}"
---

# Tailwind Usage with shadcn Theme

- Use the defined color scheme from shadcn — CSS variables for colors instead of hardcoded Tailwind colors:

  ```tsx
  <div className="
      bg-background text-foreground
      border-border
      ring-ring
  ">
  ```

- Group related Tailwind classes together by category (Layout, Typography, Visual, States), in that order:

  ```tsx
  // Layout · Typography · Visual · States
  <div className="flex flex-col gap-4 p-6 text-foreground font-medium bg-background rounded-lg shadow-md hover:shadow-lg transition-shadow duration-200">
  ```

- Avoid arbitrary values (`[w-327px]`) when possible; use standard Tailwind spacing
- Use consistent shadcn color variables from the Tailwind config
- Implement responsive design using Tailwind breakpoints (`md:`, `lg:`)

# shadcn Component Integration

- Import and use shadcn components for consistent UI:

  ```tsx
  import { Button } from "@/components/ui/button";
  import {
    Card,
    CardContent,
    CardHeader,
    CardTitle,
  } from "@/components/ui/card";
  import { Input } from "@/components/ui/input";
  ```

- Use shadcn variants for consistent styling:

  ```tsx
  <Button variant="default">Primary Action</Button>
  <Button variant="secondary">Secondary Action</Button>
  <Button variant="destructive">Delete</Button>
  ```

- Maintain shadcn's component prop structure
- Use shadcn's design tokens for spacing, typography, and colors
- Follow the dark mode rules in `rules/dark-mode.md`

# Responsive Design

- Design mobile-first, then add responsive variants
- Use Tailwind breakpoints consistently
- Test on multiple viewport sizes
- Consider touch interactions for mobile devices
