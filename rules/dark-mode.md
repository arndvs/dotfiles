---
description: "Dark Mode Design System (DMDS) — required dark variants and surface tokens for prototyping components."
paths:
  - "**/*.{tsx,jsx,css,scss}"
---

# Dark Mode Requirements

**CRITICAL:** All components MUST support dark mode using the Dark Mode Design System (DMDS) tokens.

## Required Dark Mode Support

1. **Always include dark mode variants:**

   ```tsx
   // ✅ CORRECT
   <section className='bg-white dark:bg-surface-1'>

   // ❌ WRONG - Missing dark mode
   <section className='bg-white'>
   ```

2. **Use surface tokens, never hardcoded colors:**

   ```tsx
   // ✅ CORRECT
   <div className='bg-white dark:bg-surface-1'>
   <Card className='bg-card dark:bg-surface-2'>

   // ❌ WRONG - Hardcoded colors
   <div className='bg-white dark:bg-gray-900'>
   <Card className='bg-card dark:bg-slate-800'>
   ```

3. **Use semantic text tokens:**

   ```tsx
   // ✅ CORRECT
   <p className='text-foreground'>Primary text</p>
   <p className='text-muted-foreground'>Secondary text</p>

   // ❌ WRONG - Hardcoded colors
   <p className='dark:text-white'>Primary text</p>
   <p className='dark:text-gray-400'>Secondary text</p>
   ```

4. **Surface token decision matrix:**
   - Standard sections: `bg-white` → `dark:bg-surface-1`
   - Raised cards: `bg-card` → `dark:bg-surface-2`
   - Page background: `bg-background` → `dark:bg-surface-0` (handled globally)
   - Brand CTAs: `bg-primary/10` → `dark:bg-surface-accent`

## Reference Documentation

- **Complete guide:** `docs/dark-mode-design-system.md`
- **Token reference:** `src/lib/styles/dark-mode-tokens.ts`
- **Migration helpers:** `src/lib/utils/dark-mode-helpers.ts`

## Testing Requirements

- Test all components in both light and dark modes
- Verify WCAG AA contrast compliance
- Check for visual consistency across themes
