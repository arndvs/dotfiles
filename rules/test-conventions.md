---
description: "Test conventions — describe/it structure, assertion patterns, mock boundaries, and async testing rules."
paths:
  - "**/*.test.{ts,tsx,js,jsx}"
  - "**/*.spec.{ts,tsx,js,jsx}"
  - "**/__tests__/**"
  - "**/*Service.{ts,tsx}"
  - "**/services/**/*.{ts,tsx}"
---

# Test Conventions

- Prefer `describe`/`it` blocks over bare `test()` calls
- Use descriptive test names that read as specifications: `it("returns 404 when user not found")`
- One assertion per test unless tightly related assertions test the same behavior
- Avoid `any` casts in test code — type the mocks properly
- Never use `sleep()` or fixed timeouts — use `waitFor`, polling, or event-driven assertions
- Keep test setup in `beforeEach`, not duplicated across tests
- Mock at the boundary (API, DB, filesystem), not internal modules
- Any file identified as a service (e.g. `authTokenService.ts`, or anything under a `services/` directory) MUST have an accompanying `.test.ts` file colocated with it. When creating or modifying a service, create or update its test file in the same change
