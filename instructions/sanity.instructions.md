---
description: "Sanity CMS conventions — v5 schema design, GROQ queries, TypeGen, Visual Editing, and Studio configuration."
---
Output "Read Sanity instructions." to chat to acknowledge you read this file.

## Sanity v5 Version Awareness

- Sanity v5 requires React 19.2+.
- Node.js 20+ is required (introduced as a requirement in the v4 generation and still applies).
- Studio APIs are stable across v3 → v4 → v5 for most common integrations, so migration is usually dependency and tooling focused rather than API-breakage focused.

## Sanity + Next.js Live Content API

- Use `defineLive` from `next-sanity/live` (not `next-sanity`).
- Use `sanityFetch` for Server Component data fetching instead of calling `client.fetch()` directly in pages/routes.
- Render `<SanityLive />` in the root layout so live updates and presentation tooling can stream updates.
- For `generateMetadata` and `generateStaticParams`, set `stega: false`.
- In `generateStaticParams`, use `perspective: 'published'` to avoid draft-aware behavior during static path generation.
- For optimized live editing in app code, use `usePresentationQuery` from `next-sanity/hooks` where appropriate.

Recommended pattern:

```typescript
// src/sanity/lib/live.ts
import { defineLive } from "next-sanity/live";
import { client } from "./client";

export const { sanityFetch, SanityLive } = defineLive({
  client,
  serverToken: token,
  browserToken: token,
});

// Usage in a page
const { data } = await sanityFetch({ query: POST_QUERY, params });

// Metadata
export async function generateMetadata({ params }) {
  const { data } = await sanityFetch({
    query: SEO_QUERY,
    params,
    stega: false,
  });
}

// Static params
export async function generateStaticParams() {
  const { data } = await sanityFetch({
    query: SLUGS_QUERY,
    perspective: "published",
    stega: false,
  });
}
```

## Commands

```bash
# MCP Setup
npx sanity@latest mcp configure  # Configure MCP for your AI editor

# Schema & Types
npx sanity schema deploy     # Deploy schema to Content Lake (REQUIRED before MCP!)
npx sanity schema extract    # Extract schema for TypeGen
npx sanity typegen generate  # Generate TypeScript types

# Development
npx sanity dev               # Start Studio dev server
npx sanity build             # Build Studio for production
npx sanity deploy            # Deploy Studio to Sanity hosting

# Help
npx sanity docs search "query"  # Search Sanity documentation
npx sanity --help               # List all CLI commands
```

## MCP Server Setup

The Sanity MCP server is remote-hosted — no local npm install required.
Server URL: `https://mcp.sanity.io`
Authentication: OAuth (default) or scoped API token.

Always verify the server is active before any Sanity task. If tools are unavailable or you get a 401 error, the OAuth session may have expired (sessions last ~7 days). To fix, run:

```bash
npx sanity@latest mcp configure
```

Then re-select your editor. To configure for the first time on an existing project:

```bash
sanity mcp configure
```

## Knowledge Router

If the Sanity MCP server is available, use `list_sanity_rules` and `get_sanity_rules` to load always up-to-date rules on demand. Otherwise, use the sanity-best-practices skill reference files.

**Before modifying any Sanity code:**

1. Identify which topics apply to your task
2. Read the corresponding reference file(s) from `skills/sanity-best-practices/references/`
3. Follow the patterns and constraints defined in those references

See `skills/sanity-best-practices/SKILL.md` for the full reference index.

## Agent Behavior

- Specialize in **Structured Content**, **GROQ**, and **Sanity Studio** configuration.
- Write best-practice, type-safe code using **Sanity TypeGen**.
- Build scalable content platforms, not just websites.
- **Detect the user's framework** from `package.json` and consult the appropriate reference file.

## First Call Guidance

Start by calling `get_schema` before queries or mutations so field names, types, and references are verified from the source of truth.

## Key Concepts

| Concept           | Description                                                         |
| ----------------- | ------------------------------------------------------------------- |
| **Project ID**    | Unique identifier for a Sanity project (e.g. `abc123xy`)            |
| **Dataset**       | Named content store within a project (commonly `production`)        |
| **Document ID**   | Unique ID for a document; drafts are prefixed `drafts.`             |
| **GROQ**          | Sanity's query language — use `query_documents` to execute          |
| **Portable Text** | Sanity's rich text format — complex; see caveats below              |
| **Release**       | A named batch of draft changes to publish together                  |
| **Schema**        | The content model — always check schema before querying or mutating |

## Extracting IDs from URLs

- Project: `https://www.sanity.io/manage/project/{PROJECT_ID}`
- Studio document: `https://{studio}.sanity.studio/structure/{type};{DOCUMENT_ID}`
- Dataset is shown in Studio URL or project settings

## Available Tools

### Rules & Documentation

| Tool                | Purpose                                          |
| ------------------- | ------------------------------------------------ |
| `list_sanity_rules` | List available Sanity best-practice rule sets    |
| `get_sanity_rules`  | Load one or more rule sets for your current task |
| `search_docs`       | Search official Sanity documentation             |
| `read_docs`         | Read a specific Sanity doc page                  |
| `migration_guide`   | Get guides for migrating from other CMSs         |

### Querying

| Tool                      | Purpose                                                     |
| ------------------------- | ----------------------------------------------------------- |
| `get_schema`              | Fetch full schema or a specific schema type before querying |
| `query_documents`         | Execute GROQ queries against a dataset                      |
| `get_document`            | Retrieve a document by exact ID                             |
| `semantic_search`         | Semantic search against an embeddings index                 |
| `list_embeddings_indices` | List available semantic search indices                      |

### Document Operations

| Tool                             | Purpose                                          |
| -------------------------------- | ------------------------------------------------ |
| `create_documents_from_json`     | Create draft documents from JSON                 |
| `create_documents_from_markdown` | Create draft documents from Markdown             |
| `patch_document_from_json`       | Apply precise modifications to document fields   |
| `patch_document_from_markdown`   | Patch a field using markdown content             |
| `publish_documents`              | Publish one or more drafts                       |
| `unpublish_documents`            | Unpublish documents (move back to drafts)        |
| `discard_drafts`                 | Discard drafts while keeping published documents |

### Schema & Deployment

| Tool                     | Purpose                                   |
| ------------------------ | ----------------------------------------- |
| `get_schema`             | Get full schema of the current workspace  |
| `list_workspace_schemas` | List all available workspace schema names |
| `deploy_schema`          | Deploy schema types to the cloud          |

### Media & AI

| Tool              | Purpose                                  |
| ----------------- | ---------------------------------------- |
| `generate_image`  | AI image generation for a document field |
| `transform_image` | AI transformation of an existing image   |

### Releases & Versions

| Tool                         | Purpose                                           |
| ---------------------------- | ------------------------------------------------- |
| `list_releases`              | List dataset releases                             |
| `create_release`             | Create a new release                              |
| `create_version`             | Create a version document for a release           |
| `version_replace_document`   | Replace version contents from another document    |
| `version_discard`            | Discard document versions from a release          |
| `version_unpublish_document` | Mark document to be unpublished when release runs |

### Project & Dataset Management

| Tool                                                  | Purpose                                   |
| ----------------------------------------------------- | ----------------------------------------- |
| `list_projects` / `list_organizations`                | List projects and organizations           |
| `create_project`                                      | Create a new Sanity project               |
| `list_datasets` / `create_dataset` / `update_dataset` | Manage datasets                           |
| `add_cors_origin`                                     | Add CORS origins for client-side requests |

**Critical:** After schema changes, deploy with `deploy_schema` before using content tools.

## TypeGen (v5 CLI Config)

Use `sanity.cli.ts` (not `sanity-typegen.json`) for TypeGen configuration.

Minimum recommended baseline:

- `typegen.enabled: true` so generation runs automatically during `sanity dev` / `sanity build`
- `typegen.overloadClientMethods: true` for typed `client.fetch()` overloads
- `schemaExtraction.enabled: true` with a stable extraction path
- `schemaExtraction.enforceRequiredFields: true` (equivalent to `sanity schema extract --enforce-required-fields`)

Recommended CLI config shape:

```ts
import { defineCliConfig } from "sanity/cli";

export default defineCliConfig({
  reactStrictMode: true,
  typegen: {
    enabled: true,
    path: "./src/**/*.{ts,tsx,js,jsx}",
    schema: "./src/sanity/extract.json",
    generates: "./src/sanity/types.ts",
    overloadClientMethods: true,
  },
  schemaExtraction: {
    enabled: true,
    path: "./src/sanity/extract.json",
    enforceRequiredFields: true,
  },
});
```

## Next.js Integration Caveats

For Next.js Live Content API setup (`defineLive`, `sanityFetch`, `<SanityLive />`), see `nextjs.instructions.md`.

## Rule/Docs Conflict Caveat

When MCP rules conflict with actual package exports, verify against the package `exports` map in `package.json` and follow the package exports as source of truth.

## Common Workflows

**Explore content:**

1. `get_schema` → understand the content model before querying
2. `query_documents` with GROQ → retrieve content

**Create or edit a document:**

1. `get_schema` for the relevant type
2. `create_documents_from_json` or `patch_document_from_json` for targeted field edits
3. Documents are created as **drafts** by default — publish with `publish_documents` or via a release

**Batch publish with a release:**

1. `list_releases` → find or create a release
2. `create_version` → stage documents into the release
3. Publish the release from Sanity Studio or via the releases API

**Debug a missing document:**

1. `get_document` with the document ID
2. Check publish state, required fields, and schema validation

**Set up a new project from scratch:**

1. `create_project` → auto-adds `localhost:3333` CORS origin
2. `deploy_schema` → define the content model
3. `create_documents_from_json` → seed content

## GROQ Quick Reference

```groq
// All published documents of a type
*[_type == "post"]

// With specific fields
*[_type == "post"]{ _id, title, slug, publishedAt }

// Filter + order
*[_type == "post" && defined(publishedAt)] | order(publishedAt desc)[0..9]

// Dereference a reference field
*[_type == "post"]{ title, "authorName": author->name }

// Draft documents are prefixed "drafts."
*[_id in path("drafts.**")]
```

## Important Caveats

- **Check schema first.** Always call `get_schema` for the relevant type before writing queries or mutations — don't guess field names.
- **Portable Text (Block content).** Some models struggle to write valid Portable Text. If you're having issues with rich text fields, avoid `create_documents_from_markdown` and use `patch_document_from_json` with explicit block structures instead. You can also instruct the agent to skip Portable Text fields and fill them manually in Studio.
- **Drafts vs. published.** Creating a document via MCP produces a draft (`drafts.` prefix). It is not live until published.
- **AI credits.** Tool calls that create or modify documents count as Agent Action requests and consume AI credits. Monitor usage in project settings.
- **Token budgeting.** Large queries are paginated automatically. Responses include a count like "12 of 847 documents" — paginate if you need more.
- **Permissions.** If you get a 403, check that your OAuth account or API token has the correct role (Editor or Developer) for the project and dataset.

## Boundaries

- **Always:**
  - Use `defineQuery` for all GROQ queries.
  - Prefer MCP tools for content operations (query, create, update, patch). For bulk migrations or when MCP is unavailable, NDJSON scripts are a valid alternative. Never use NDJSON scripts when MCP tools can accomplish the same task more simply.
  - Run `deploy_schema` after schema changes — required before using content tools. If a local Studio exists, update schema files first to keep them in sync with the deployed schema.
  - Follow the "Deprecation Pattern" when removing fields (ReadOnly → Hidden → Deprecated).
  - Run `npm run typegen` after schema or query changes (or enable automatic generation with `typegen.enabled: true` in `sanity.cli.ts`).
- **Ask First:**
  - Before modifying `sanity.config.ts`.
  - Before deleting any schema definition file.
- **Never:**
  - Hardcode API tokens (use `process.env`).
  - Use loose types (`any`) for Sanity content.
