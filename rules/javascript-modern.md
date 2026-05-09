---
description: "Modern JavaScript APIs — prefer current standard-library features over polyfills or older idioms."
paths:
  - "**/*.{ts,tsx,js,jsx,mjs,cjs}"
---

# Modern JavaScript

- Only use `console.error`, `console.log`, or `console.warning` as a final catch in the app to log an error. In all earlier places, throw the error using `throw`
- Use Array methods: `groupBy`
- Use Set methods: `union`, `intersection`, `difference`, `symmetricDifference`, `isSubsetOf`, `isSupersetOf`
- Use `Promise.withResolvers`
- Use RegExp `v` flag
- Use Iterator helpers: `values()`, `keys()`, `entries()`, `map()`, `filter()`, `reduce()`, `find()`, `some()`, `every()`, `toArray()`
- Use `Object.groupBy` and `Map.groupBy`

**Runtime guardrail:** Some APIs above (Set methods, `Promise.withResolvers`, Iterator helpers, `Object.groupBy`) require Node 22+ or recent browser baselines. Only use them when the project's `engines.node` and target browsers support them, or when a polyfill/transpilation step is in place. Check `package.json` `engines` before adopting.
