import path from "node:path";
import { fileURLToPath } from "node:url";
import { parseArgs } from "node:util";
import { run, Output, StructuredOutputError, claudeCode } from "@ai-hero/sandcastle";
import { noSandbox } from "@ai-hero/sandcastle/sandboxes/no-sandbox";
import { PlanOutput } from "./schemas/plan-output.js";
import { runImplementPr } from "./workflows/implement-pr.js";
import { runReview } from "./workflows/review.js";
import { runToIssuesPrd } from "./workflows/to-issues-prd.js";

const __dirname = path.dirname(fileURLToPath(import.meta.url));

const MODEL = process.env["ANTHROPIC_MODEL"] ?? "claude-sonnet-4-20250514";

const { values } = parseArgs({
  options: {
    repo: { type: "string" },
    "max-iterations": { type: "string", default: "1" },
    workflow: { type: "string", default: "implement" },
    issue: { type: "string" },
    branch: { type: "string" },
    pr: { type: "string" },
    "max-issues": { type: "string", default: "5" },
    "dry-run": { type: "boolean", default: false },
  },
  strict: true,
});

if (!values.repo) {
  throw new Error("--repo is required");
}

const repoDir = path.resolve(values.repo);
const maxIterations = parseInt(values["max-iterations"] ?? "1", 10);

if (Number.isNaN(maxIterations) || maxIterations < 1) {
  throw new Error(`--max-iterations must be a positive integer, got: ${values["max-iterations"]}`);
}

const workflow = values.workflow ?? "implement";
const promptFile = path.resolve(__dirname, "prompts", `${workflow}.md`);

console.log(`[shft-engine] repo: ${repoDir}`);
console.log(`[shft-engine] workflow: ${workflow}`);
console.log(`[shft-engine] model: ${MODEL}`);
console.log(`[shft-engine] maxIterations: ${maxIterations}`);

const promptArgs: Record<string, string> = {};
if (values.issue) promptArgs["ISSUE_NUMBER"] = values.issue;
if (values.branch) promptArgs["BRANCH"] = values.branch;
if (values["max-issues"]) promptArgs["MAX_ISSUES"] = values["max-issues"];

if (workflow === "plan") {
  try {
    const result = await run({
      agent: claudeCode(MODEL),
      sandbox: noSandbox(),
      cwd: repoDir,
      promptFile,
      maxIterations: 1,
      promptArgs,
      output: Output.object({ tag: "output", schema: PlanOutput }),
      logging: { type: "stdout" },
    });

    console.log(`\n[shft-engine] Plan phase complete`);
    console.log(`[shft-engine] Issues to work on:`);
    for (const issue of result.output.issues) {
      console.log(`  #${issue.number} ${issue.title} → ${issue.branch}`);
    }

    console.log(`\n[shft-engine] Plan output (JSON):`);
    console.log(JSON.stringify(result.output, null, 2));
  } catch (error) {
    if (error instanceof StructuredOutputError) {
      console.error(`[shft-engine] Plan phase failed: malformed agent output`);
      console.error(`[shft-engine] Tag: <${error.tag}>`);
      console.error(`[shft-engine] Raw matched: ${error.rawMatched ?? "(no match found)"}`);
      if (error.cause) console.error(`[shft-engine] Cause:`, error.cause);
      process.exit(1);
    }
    throw error;
  }
} else if (workflow === "implement-pr") {
  if (!values.pr) {
    throw new Error("--pr is required for implement-pr workflow");
  }
  await runImplementPr({
    prNumber: values.pr,
    repoDir,
    model: MODEL,
    promptsDir: path.resolve(__dirname, "prompts"),
  });
} else if (workflow === "review") {
  if (!values.pr) {
    throw new Error("--pr is required for review workflow");
  }
  await runReview({
    prNumber: values.pr,
    repoDir,
    model: MODEL,
    promptsDir: path.resolve(__dirname, "prompts"),
  });
} else if (workflow === "to-issues-prd") {
  if (!values.issue) {
    throw new Error("--issue is required for to-issues-prd workflow");
  }
  await runToIssuesPrd({
    issueNumber: values.issue,
    repoDir,
    model: MODEL,
    promptsDir: path.resolve(__dirname, "prompts"),
    dryRun: values["dry-run"] ?? false,
  });
} else {
  const result = await run({
    agent: claudeCode(MODEL),
    sandbox: noSandbox(),
    cwd: repoDir,
    promptFile,
    maxIterations,
    promptArgs,
    completionSignal: "<promise>COMPLETE</promise>",
    logging: { type: "stdout" },
  });

  console.log(`\n[shft-engine] Iterations: ${result.iterations.length}`);
  console.log(`[shft-engine] Commits: ${result.commits.map((c) => c.sha).join(", ") || "none"}`);
  console.log(`[shft-engine] Branch: ${result.branch}`);

  if (result.completionSignal) {
    console.log(`[shft-engine] Completion signal received`);
  }
}
