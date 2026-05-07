---
description: "Modern JavaScript APIs — prefer current standard-library features over polyfills or older idioms."
paths:
  - "**/*.{ts,tsx,js,jsx,mjs,cjs}"
---

# Modern JavaScript

- Only use `console.error`, `console.log`, or `console.warn` as a final catch in the app to log an error. In all earlier places, throw the error using `throw`
- Use Set methods: `union`, `intersection`, `difference`, `symmetricDifference`, `isSubsetOf`, `isSupersetOf`
- Use `Promise.withResolvers`
- Use RegExp `v` flag
- Use Iterator helpers: `values()`, `keys()`, `entries()`, `map()`, `filter()`, `reduce()`, `find()`, `some()`, `every()`, `toArray()`
- Use `Object.groupBy` and `Map.groupBy`
