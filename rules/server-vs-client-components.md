---
description: "Next.js App Router — default to Server Components; scope Client Components minimally; error handling patterns."
paths:
  - "**/app/**/*.{tsx,jsx}"
---

# Server Components vs Client Components

**CRITICAL: Default to Server Components**

- **Use Server Components everywhere possible** — they are the default in Next.js App Router
- Server components render on the server, improving performance and reducing client-side JavaScript
- Only use Client Components (`'use client'`) when absolutely necessary

## When to Use Client Components

- Interactive elements requiring browser APIs (onClick, useState, useEffect)
- Components using Framer Motion animations (content sections only, not hero)
- Form inputs and interactive widgets
- Components that need to respond to user input in real-time

## Client Component Best Practices

- **Scope client components as small as possible** — only mark the minimal component that needs interactivity
- Extract interactive logic into the smallest possible client component
- Pass data down from server components as props
- Keep most of the component tree as server components

```tsx
// ✅ CORRECT - Server component renders a tiny client island.
// The Client Component owns its own handler; the Server Component
// passes only serializable data (or a Server Action) across the boundary.

// interactive-button.tsx
'use client';
export function InteractiveButton({ label }: { label: string }) {
  return <button onClick={() => console.log('clicked')}>{label}</button>;
}

// feature-section.tsx (Server Component)
import { InteractiveButton } from './interactive-button';

export default function FeatureSection({ data }: Props) {
  return (
    <section>
      <h2>{data.title}</h2>
      <p>{data.description}</p>
      <InteractiveButton label={data.cta} />
    </section>
  );
}

// ❌ WRONG - Entire section marked client just for one button.
'use client';
export default function FeatureSection({ data }: Props) {
  return (
    <section>
      <h2>{data.title}</h2>
      <p>{data.description}</p>
      <button onClick={() => console.log('clicked')}>{data.cta}</button>
    </section>
  );
}
```

> **Note:** functions are not serializable across the server→client boundary. To trigger server work from a Client Component, use a Server Action (a function exported from a `'use server'` module) and pass that as the prop, not an inline closure.
>
> The `'use client'` directive must be the first statement at the top of the file (a bare string literal). `("use client");` written as an expression statement is **not** a directive and will silently leave the file as a Server Component.

## Pattern for Data

- Server components fetch data directly
- Pass data to client components via props
- Never fetch data in client components

```tsx
// ✅ CORRECT - Server component fetches, Client Component receives via props
// page.tsx (Server Component)
import { InteractiveComponent } from './interactive-component';

export default async function Page() {
  const data = await fetchData();
  return <InteractiveComponent data={data} />;
}

// interactive-component.tsx (Client Component)
'use client';
import { useState } from 'react';

export function InteractiveComponent({ data }: { data: Data }) {
  const [state, setState] = useState();
  return <div>{/* Use data and state */}</div>;
}
```

# Error Handling

- Implement graceful fallbacks for missing data
- Use conditional rendering to handle undefined states
- Add helpful error boundaries where appropriate
- Provide user-friendly error messages
- Use shadcn's Alert component for error states:

  ```tsx
  import { Alert, AlertDescription, AlertTitle } from "@/components/ui/alert";

  <Alert variant="destructive">
    <AlertTitle>Error</AlertTitle>
    <AlertDescription>
      There was a problem loading your data. Please try again.
    </AlertDescription>
  </Alert>;
  ```
