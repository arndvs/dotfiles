---
description: "TypeScript code conventions — parameter style, typing patterns."
paths:
  - "**/*.{ts,tsx}"
---

# TypeScript Conventions

- When a function takes more than one parameter of the same type (e.g. multiple `string` params), use a single object parameter instead of positional parameters to prevent argument-order mistakes:

  ```ts
  // BAD
  const addUserToPost = (userId: string, postId: string) => {};

  // GOOD
  const addUserToPost = (opts: { userId: string; postId: string }) => {};
  ```
