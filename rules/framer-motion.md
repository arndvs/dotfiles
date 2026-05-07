---
description: "Framer Motion animation conventions — instant render, scroll-triggered reveals, reduced-motion support, performance."
paths:
  - "**/*.{tsx,jsx}"
---

# Animation with Framer Motion

## Modern Animation Philosophy

Our animation system prioritizes **instant content visibility** with **subtle, purposeful motion**:

- **Instant Initial Render**: Content appears immediately without animation delays
- **Subtle Motion**: Ultra-refined animations (4px movement, refined easing) for premium feel
- **Strategic Use**: Motion for interactions and meaningful feedback, not decoration
- **Performance First**: GPU-accelerated, CLS-safe, respects `prefers-reduced-motion`

**When to Animate:**

- ✅ Scroll-triggered content reveals (below the fold)
- ✅ Interactive feedback (hover, tap, focus)
- ✅ State changes (modals, dialogs, form states)
- ❌ Page-load animations (delays content visibility)
- ❌ Hero sections (must be server components, instant render)
- ❌ Above-fold content (use CLS-safe or instant variants)

- Use the existing variants from `@/lib/hooks/use-animation-variants` rather than creating new animations from scratch
- Import and use Framer Motion as the primary animation library:

  ```tsx
  import { motion } from "framer-motion";
  ```

- **CRITICAL: Hero components MUST NOT use Framer Motion animations**
  - Hero sections should load immediately without animation delays
  - Hero components must be server components
  - Use only CSS transitions for hover states and subtle interactions

- **CRITICAL: Use scroll-triggered animations for content sections (non-hero)**

  ```tsx
  'use client';
  import { motion } from 'framer-motion';
  import {
    useContainerVariants,
    useItemVariants,
  } from '@/lib/hooks/use-animation-variants';

  export function RevealList({ items }: { items: React.ReactNode[] }) {
    // Hooks must be called inside a component or another custom hook.
    const containerVars = useContainerVariants();
    const itemVars = useItemVariants();

    return (
      <motion.ul
        initial="hidden"
        whileInView="visible"
        viewport={{ once: true, margin: '-100px' }}
        variants={containerVars}
      >
        {items.map((item, i) => (
          <motion.li key={i} variants={itemVars}>{item}</motion.li>
        ))}
      </motion.ul>
    );
  }
  ```

- **CRITICAL: Above-fold content MUST use CLS-safe or instant variants**

  ```tsx
  import { useItemVariants } from "@/lib/hooks/use-animation-variants";

  const variants = useItemVariants({ clsSafe: true });

  <motion.section
    initial="hidden"
    whileInView="visible"
    viewport={{ once: true, margin: "-100px" }}
    variants={variants}
  >
    Above-fold content
  </motion.section>;
  ```

- **Animation Patterns by Use Case:**

  **Hero Components (NO Framer Motion, Server Components Only):**

  ```tsx
  export default function HeroSection({ data }: Props) {
    return (
      <div className="hero-section">
        <h1>{data.title}</h1>
        <div className="transition-all hover:shadow-lg">
          {/* Only CSS transitions for hover states */}
        </div>
      </div>
    );
  }
  ```

  **Content Sections (use `whileInView`):**

  ```tsx
  import { useContainerVariants } from "@/lib/hooks/use-animation-variants";

  const containerVars = useContainerVariants();

  <motion.div
    initial="hidden"
    whileInView="visible"
    viewport={{ once: true, margin: "-100px" }}
    variants={containerVars}
  >
    {/* Page sections, cards, lists */}
  </motion.div>;
  ```

  **Interactive Elements (instant render + interaction-only):**

  ```tsx
  import { useInteractionVariants } from "@/lib/hooks/use-animation-variants";

  const buttonVars = useInteractionVariants("button");
  const microVars = useInteractionVariants("micro");

  <motion.button
    initial={{ opacity: 1 }}
    variants={buttonVars}
    whileHover="hover"
    whileTap="tap"
  >
    Click me
  </motion.button>;
  ```

  **Staggered lists:**

  ```tsx
  import {
    useContainerVariants,
    useItemVariants,
  } from "@/lib/hooks/use-animation-variants";

  const containerVars = useContainerVariants();
  const itemVars = useItemVariants();

  <motion.div
    initial="hidden"
    whileInView="visible"
    viewport={{ once: true, margin: "-50px" }}
    variants={containerVars}
  >
    {items.map((item) => (
      <motion.div key={item.id} variants={itemVars}>
        {/* Item content */}
      </motion.div>
    ))}
  </motion.div>;
  ```

- Use exit animations for elements being removed:

  ```tsx
  <AnimatePresence>
    {isVisible && (
      <motion.div
        initial={{ opacity: 0, height: 0 }}
        animate={{ opacity: 1, height: "auto" }}
        exit={{ opacity: 0, height: 0 }}
      >
        Content
      </motion.div>
    )}
  </AnimatePresence>
  ```

- **CRITICAL: Always respect user preferences for reduced motion:**

  ```tsx
  // ✅ REQUIRED - Use helper hooks (automatic accessibility)
  import {
    useContainerVariants,
    useInteractionVariants,
    useItemVariants,
  } from "@/lib/hooks/use-animation-variants";

  // Helper hooks automatically respect prefers-reduced-motion
  const containerVars = useContainerVariants();
  const itemVars = useItemVariants();
  const interactionVars = useInteractionVariants("button");
  ```

# Performance Optimization

- Memoize expensive calculations with `useMemo`
- Prevent unnecessary re-renders with `useCallback` for handlers
- Optimize lists with proper `key` props
- Lazy-load offscreen or heavy components
- Use Framer Motion's LazyMotion for code-splitting animations:

  ```tsx
  import { LazyMotion, domAnimation, m } from "framer-motion";

  <LazyMotion features={domAnimation}>
    <m.div animate={{ scale: 1.2 }}>Lazy loaded animation</m.div>
  </LazyMotion>;
  ```
