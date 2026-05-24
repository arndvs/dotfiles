import path from "node:path";
import { fileURLToPath } from "node:url";
import { parseArgs } from "node:util";
import { run, claudeCode } from "@ai-hero/sandcastle";
import { noSandbox } from "@ai-hero/sandcastle/sandboxes/no-sandbox";

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

const promptFile = path.resolve(__dirname, "prompts", "implement.md");

console.log(`[shft-engine] repo: ${repoDir}`);
console.log(`[shft-engine] workflow: ${values.workflow}`);
console.log(`[shft-engine] model: ${MODEL}`);
console.log(`[shft-engine] maxIterations: ${maxIterations}`);

const promptArgs: Record<string, string> = {};
if (values.issue) promptArgs["ISSUE_NUMBER"] = values.issue;
if (values.branch) promptArgs["BRANCH"] = values.branch;

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
