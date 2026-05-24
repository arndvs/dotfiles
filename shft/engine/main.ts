import path from "node:path";
import { fileURLToPath } from "node:url";
import { parseArgs } from "node:util";
import { run, Output, StructuredOutputError, claudeCode, createSandbox } from "@ai-hero/sandcastle";
import { noSandbox } from "@ai-hero/sandcastle/sandboxes/no-sandbox";
import { PlanOutput } from "./schemas/plan-output.js";
import { MergeOutput } from "./schemas/merge-output.js";
import { runImplementPr } from "./workflows/implement-pr.js";
import { runReview } from "./workflows/review.js";
import { runToIssuesPrd } from "./workflows/to-issues-prd.js";
import { Semaphore } from "./lib/semaphore.js";

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
    "max-parallel": { type: "string", default: "4" },
    "dry-run": { type: "boolean", default: false },
  },
  strict: true,
});

if (!values.repo) {
  throw new Error("--repo is required");
}

const repoDir = path.resolve(values.repo);
const maxIterations = parseInt(values["max-iterations"] ?? "1", 10);
const maxParallel = parseInt(values["max-parallel"] ?? "4", 10);

if (Number.isNaN(maxIterations) || maxIterations < 1) {
  throw new Error(`--max-iterations must be a positive integer, got: ${values["max-iterations"]}`);
}

if (Number.isNaN(maxParallel) || maxParallel < 1) {
  throw new Error(`--max-parallel must be a positive integer, got: ${values["max-parallel"]}`);
}

const workflow = values.workflow ?? "implement";
const promptsDir = path.resolve(__dirname, "prompts");
const promptFile = path.resolve(promptsDir, `${workflow}.md`);

console.log(`[shft-engine] repo: ${repoDir}`);
console.log(`[shft-engine] workflow: ${workflow}`);
console.log(`[shft-engine] model: ${MODEL}`);
console.log(`[shft-engine] maxIterations: ${maxIterations}`);

const promptArgs: Record<string, string> = {};
if (values.issue) promptArgs["ISSUE_NUMBER"] = values.issue;
if (values.branch) promptArgs["BRANCH"] = values.branch;
if (values["max-issues"]) promptArgs["MAX_ISSUES"] = values["max-issues"];

interface IssueResult {
  issue: { number: number; title: string; branch: string };
  status: "completed" | "failed";
  commits: string[];
  error?: string;
}

async function runPlan(): Promise<PlanOutput> {
  console.log(`\n[shft-engine] Running plan phase...`);
  try {
    const result = await run({
      agent: claudeCode(MODEL),
      sandbox: noSandbox(),
      cwd: repoDir,
      promptFile: path.resolve(promptsDir, "plan.md"),
      maxIterations: 1,
      promptArgs,
      output: Output.object({ tag: "output", schema: PlanOutput }),
      logging: { type: "stdout" },
    });

    console.log(`\n[shft-engine] Plan phase complete — ${result.output.issues.length} issues selected`);
    for (const issue of result.output.issues) {
      console.log(`  #${issue.number} ${issue.title} → ${issue.branch}`);
    }
    return result.output;
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
}

async function implementIssue(issue: PlanOutput["issues"][number]): Promise<IssueResult> {
  console.log(`[shft-engine] [#${issue.number}] Starting implementation on branch ${issue.branch}`);

  const sandbox = await createSandbox({
    branch: issue.branch,
    sandbox: noSandbox(),
    cwd: repoDir,
  });

  try {
    const result = await sandbox.run({
      agent: claudeCode(MODEL),
      promptFile: path.resolve(promptsDir, "implement.md"),
      promptArgs: {
        ISSUE_NUMBER: String(issue.number),
        BRANCH: issue.branch,
      },
      maxIterations,
      completionSignal: "<promise>COMPLETE</promise>",
      logging: { type: "stdout" },
    });

    const shas = result.commits.map((c) => c.sha);
    console.log(`[shft-engine] [#${issue.number}] Complete — ${shas.length} commits`);

    return { issue, status: "completed", commits: shas };
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    console.error(`[shft-engine] [#${issue.number}] Failed: ${message}`);
    return { issue, status: "failed", commits: [], error: message };
  } finally {
    await sandbox.close();
  }
}

async function runMerge(completedBranches: string[]): Promise<MergeOutput> {
  console.log(`\n[shft-engine] Running merge phase for ${completedBranches.length} branches...`);
  try {
    const result = await run({
      agent: claudeCode(MODEL),
      sandbox: noSandbox(),
      cwd: repoDir,
      promptFile: path.resolve(promptsDir, "merge.md"),
      maxIterations: 1,
      promptArgs: {
        BRANCHES_JSON: JSON.stringify(completedBranches, null, 2),
      },
      output: Output.object({ tag: "output", schema: MergeOutput }),
      logging: { type: "stdout" },
    });

    console.log(`\n[shft-engine] Merge phase complete`);
    console.log(`  merged: ${result.output.merged.join(", ") || "none"}`);
    if (result.output.failed.length > 0) {
      for (const f of result.output.failed) {
        console.error(`  failed: ${f.branch} — ${f.reason}`);
      }
    }
    console.log(`  tests passed: ${result.output.testsPassed}`);
    return result.output;
  } catch (error) {
    if (error instanceof StructuredOutputError) {
      console.error(`[shft-engine] Merge phase failed: malformed agent output`);
      console.error(`[shft-engine] Tag: <${error.tag}>`);
      console.error(`[shft-engine] Raw matched: ${error.rawMatched ?? "(no match found)"}`);
      if (error.cause) console.error(`[shft-engine] Cause:`, error.cause);
      process.exit(1);
    }
    throw error;
  }
}

if (workflow === "plan") {
  const plan = await runPlan();
  console.log(`\n[shft-engine] Plan output (JSON):`);
  console.log(JSON.stringify(plan, null, 2));
} else if (workflow === "parallel") {
  console.log(`[shft-engine] maxParallel: ${maxParallel}`);

  const plan = await runPlan();
  const semaphore = new Semaphore(maxParallel);

  const settled = await Promise.allSettled(
    plan.issues.map((issue) =>
      semaphore.run(() => implementIssue(issue)),
    ),
  );

  const results: IssueResult[] = settled.map((s, i) => {
    if (s.status === "fulfilled") return s.value;
    const message = s.reason instanceof Error ? s.reason.message : String(s.reason);
    return { issue: plan.issues[i]!, status: "failed" as const, commits: [], error: message };
  });

  const completed = results.filter((r) => r.status === "completed" && r.commits.length > 0);
  const failed = results.filter((r) => r.status === "failed");

  console.log(`\n[shft-engine] ═══ Parallel Execution Report ═══`);
  console.log(`  completed: ${completed.length}`);
  console.log(`  failed: ${failed.length}`);
  for (const r of completed) {
    console.log(`  ✓ #${r.issue.number} ${r.issue.title} (${r.commits.length} commits)`);
  }
  for (const r of failed) {
    console.log(`  ✗ #${r.issue.number} ${r.issue.title} — ${r.error}`);
  }

  if (completed.length > 0) {
    const completedBranches = completed.map((r) => r.issue.branch);
    await runMerge(completedBranches);
  } else {
    console.log(`\n[shft-engine] No branches to merge — skipping merge phase`);
  }
} else if (workflow === "implement-pr") {
  if (!values.pr) {
    throw new Error("--pr is required for implement-pr workflow");
  }
  await runImplementPr({
    prNumber: values.pr,
    repoDir,
    model: MODEL,
    promptsDir,
  });
} else if (workflow === "review") {
  if (!values.pr) {
    throw new Error("--pr is required for review workflow");
  }
  await runReview({
    prNumber: values.pr,
    repoDir,
    model: MODEL,
    promptsDir,
  });
} else if (workflow === "to-issues-prd") {
  if (!values.issue) {
    throw new Error("--issue is required for to-issues-prd workflow");
  }
  await runToIssuesPrd({
    issueNumber: values.issue,
    repoDir,
    model: MODEL,
    promptsDir,
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
