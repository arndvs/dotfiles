---
description: "Next.js conventions — App Router, Server Components, data fetching, proxy.ts, and breaking changes from v16+."
---
Output "Read NextJS instructions." to chat to acknowledge you read this file.

# This is NOT the Next.js you know

This version has breaking changes — APIs, conventions, and file structure may all differ from your training data. Read the relevant guide in `node_modules/next/dist/docs/` before writing any code. Heed deprecation notices. Next.js 16 uses proxy.ts (not middleware.ts).

Companion rules (loaded automatically by `applyTo` when editing matching files):
- Modern JS APIs → `rules/javascript-modern.md`
- TypeScript conventions and modern features → `rules/typescript-conventions.md`
- Sanity + Next.js Live Content API → `instructions/sanity.instructions.md` (loaded when sanity context is active)

<general_nextjs>

- Use icons from the `lucide-react` package.
- Do not overengineer solutions. Avoid creating new types unless absolutely needed and minimize changes. Check for duplicated types. Use a `types.ts` file to store all types.

</general_nextjs>

<nextjs_features>

- Next.js 16 uses Turbopack as the default bundler for development. No additional configuration is needed.
- Use Cache Components with `"use cache"` (requires Next.js 15+ with `dynamicIO` flag):

```typescript
async function ProductList() {
  "use cache";

  const products = await db.products.findMany();
  return <ul>{products.map((p) => <li key={p.id}>{p.name}</li>)}</ul>;
}
```

- Use `cacheLife` for cache duration:

```typescript
import { cacheLife } from "next/cache";
async function getData() {
  "use cache";
  cacheLife("hours");
  return fetch("https://api.example.com/data").then((r) => r.json());
}
```

- Use `proxy.ts` instead of `middleware.ts` (requires Next.js 15.3+)
- Always await dynamic APIs: `params`, `searchParams`, `cookies`, `headers`
- Use React 19 features:

```typescript
"use client";
import { useActionState, useOptimistic } from "react";
function Form() {
  const [state, formAction, isPending] = useActionState(submitForm, null);
  return (
    <form action={formAction}>
      <button disabled={isPending}>Submit</button>
    </form>
  );
}
```

- Use Server Actions:

```typescript
async function createPost(formData: FormData) {
  "use server";

  const title = formData.get("title") as string;
  await db.posts.create({ data: { title } });
  revalidatePath("/posts");
}
```

- Use Edge Runtime for latency-sensitive routes:

```typescript
// app/api/edge/route.ts
export const runtime = "edge";

export async function GET(request: Request) {
  return new Response("Hello from the edge!", {
    headers: { "content-type": "text/plain" },
  });
}
```

</nextjs_features>
