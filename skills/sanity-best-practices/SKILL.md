---
name: sanity-best-practices
description: "Sanity development best practices — schemas, GROQ, TypeGen, Visual Editing, Functions, Blueprints, and framework integrations. Use when working with Sanity content, schemas, queries, or Studio."
---

# Sanity Best Practices

Output "Read Sanity Best Practices skill." to chat to acknowledge you read this file.

Comprehensive best practices and integration guides for Sanity development, maintained by Sanity. Use the quick reference below to load only the one or two topic files that match the task.

## When to Apply

Reference these guidelines when working with: schema design, GROQ queries, TypeGen, Visual Editing, images, Portable Text, Studio structure, localization, migrations, Sanity Functions, Blueprints, or framework integrations (Next.js, Nuxt, Astro, Remix, SvelteKit, Angular, Hydrogen, App SDK). Triggered by: `defineType`, `defineField`, `defineQuery`, content modeling, Presentation/preview setups, `documentEventHandler`, `defineDocumentFunction`, `defineMediaLibraryAssetFunction`, `@sanity/functions`, `@sanity/blueprints`, `sanity.blueprint.ts`, event-driven content automation, or reviewing a Sanity codebase. More specifically, reference these guidelines when:
- Setting up a new Sanity project or onboarding
- Integrating Sanity with a frontend framework (Next.js, Nuxt, Astro, Remix, SvelteKit, Hydrogen)
- Writing GROQ queries or optimizing performance
- Designing content schemas
- Implementing Visual Editing and live preview
- Working with images, Portable Text, or page builders
- Configuring Sanity Studio structure
- Setting up TypeGen for type safety
- Implementing localization
- Migrating content from other systems
- Building custom apps with the Sanity App SDK
- Managing infrastructure with Blueprints
- Automating content workflows with Sanity Functions

## Version Notes (Sanity v5)

- Baseline: Sanity v5 with React 19.2+.
- Node.js 20+ is required.
- Validation chains like `.required().error().min().error()` are valid. Prefer the array-of-rules pattern when multiple constraints are present for readability and separation of concerns.
- In Next.js integrations, prefer `defineLive` from `next-sanity/live` and consume data via `sanityFetch` instead of scattering raw `client.fetch()` calls across app routes.
- Studio customizations can leverage modern React 19 capabilities, including `use()` and `<Activity>` where appropriate.

## Quick Reference

### Integration Guides

- `get-started` - Interactive onboarding for new Sanity projects
- `nextjs` - Next.js App Router, Live Content API, embedded Studio
- `nuxt` - Nuxt integration with @nuxtjs/sanity
- `angular` - Angular integration with @sanity/client, signals, resource API
- `astro` - Astro integration with @sanity/astro
- `remix` - React Router / Remix integration
- `svelte` - SvelteKit integration with @sanity/svelte-loader
- `hydrogen` - Shopify Hydrogen with Sanity
- `project-structure` - Monorepo and embedded Studio patterns
- `app-sdk` - Custom applications with Sanity App SDK
- `blueprints` - Infrastructure as Code with Sanity Blueprints
- `functions` - Automating content workflows with Sanity Functions

### Topic Guides

- `groq` - GROQ query patterns, type safety, performance optimization
- `schema` - Schema design, field definitions, validation, deprecation patterns
- `visual-editing` - Presentation Tool, Stega, overlays, live preview
- `page-builder` - Page Builder arrays, block components, live editing
- `portable-text` - Rich text rendering and custom components
- `image` - Image schema, URL builder, hotspots, LQIP, Next.js Image
- `studio-structure` - Desk structure, singletons, navigation
- `typegen` - TypeGen configuration, workflow, type utilities
- `seo` - Metadata, sitemaps, Open Graph, JSON-LD
- `localization` - i18n patterns, document vs field-level, locale management
- `migration` - Content import overview (see also `migration-html-import`)
- `migration-html-import` - HTML to Portable Text with @portabletext/block-tools

### Atomic Rules (by Priority)

| Priority | Category | Impact | Prefix |
|----------|----------|--------|--------|
| 1 | GROQ Performance | CRITICAL | `groq-` |
| 2 | Schema Design | HIGH | `schema-` |
| 3 | Visual Editing | HIGH | `visual-` |
| 4 | Images | HIGH | `image-` |
| 5 | Portable Text | HIGH | `pte-` |
| 6 | Page Builder | MEDIUM | `pagebuilder-` |
| 7 | Studio Configuration | MEDIUM | `studio-` |
| 8 | TypeGen | MEDIUM | `typegen-` |
| 9 | Localization | MEDIUM | `i18n-` |
| 10 | Migration | LOW-MEDIUM | `migration-` |

## How to Use

Start with the single framework or topic guide that best matches the request, then read additional references only when the task crosses concerns.

**Comprehensive guides** (references/) — full topic coverage with decision matrices, code examples, and framework-specific patterns:

```
references/groq.md
references/schema.md
references/nextjs.md
```

**Atomic rules** (rules/) — focused single-concern patterns with incorrect/correct examples:

```
rules/groq-optimizable-filters.md
rules/schema-data-over-presentation.md
rules/typegen-workflow.md
```

## Framework Integration

If the Sanity MCP server is available, use `list_sanity_rules` and `get_sanity_rules` to load always up-to-date rules on demand. If the MCP server is not configured, run `npx sanity@latest mcp configure` to set it up.
