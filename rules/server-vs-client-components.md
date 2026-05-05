---
description: "Next.js App Router — default to Server Components; scope Client Components minimally; error handling patterns."
paths:
  - "**/app/**/*.{tsx,jsx}"
  - "**/components/**/*.{tsx,jsx}"
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
// ✅ CORRECT - Server component with minimal client component
// Parent (Server Component)
export default function FeatureSection({ data }: Props) {
  return (
    <section>
      <h2>{data.title}</h2>
      <p>{data.description}</p>
      <InteractiveButton onClick={data.handleClick} />
    </section>
  );
}

// Child (Client Component - minimal scope)
("use client");
function InteractiveButton({ onClick }: { onClick: () => void }) {
  return <button onClick={onClick}>Click Me</button>;
}

// ❌ WRONG - Entire component marked as client when only button needs it
("use client");
export default function FeatureSection({ data }: Props) {
  return (
    <section>
      <h2>{data.title}</h2>
      <p>{data.description}</p>
      <button onClick={data.handleClick}>Click Me</button>
    </section>
  );
}
```

## Pattern for Data

- Server components fetch data directly
- Pass data to client components via props
- Never fetch data in client components

```tsx
// ✅ CORRECT - Server component fetches, client component receives
export default async function Page() {
  const data = await fetchData();
  return <InteractiveComponent data={data} />;
}

("use client");
function InteractiveComponent({ data }: { data: Data }) {
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
