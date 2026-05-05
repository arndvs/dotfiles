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

- No `||` or `??` fallbacks for required values. Throw an explicit error instead — fallbacks hide missing data and produce silent misbehavior. Exception: optional values where the fallback is the documented default.

## Modern TypeScript Features

- Use `satisfies` for type validation without losing inference
- Use Const Type Parameters for literal preservation
- Use Inferred Type Predicates
- Prefer types over enums when using `erasableSyntaxOnly`
- Use ESM path helpers
- Use modern module settings:

  ```json
  {
    "compilerOptions": {
      "target": "ES2024",
      "strict": true,
      "noUncheckedIndexedAccess": true
    }
  }
  ```

## Formatting

- Format all function or const parameters on one line: `export async function saveConversationDraft(type: 'idea' | 'builder', firstMessage: string, onSaved?: () => void): Promise<string | null> { ... }`
- Put an empty line after a const declaration. If there are multiple consecutive constants, only put an empty line after the last one.
