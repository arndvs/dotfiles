import path from "node:path";
import { execSync, execFileSync } from "node:child_process";
import { run, Output, StructuredOutputError, claudeCode } from "@ai-hero/sandcastle";
import { noSandbox } from "@ai-hero/sandcastle/sandboxes/no-sandbox";
import { ImplementPrOutput } from "../schemas/implement-pr-output.js";
import { fetchPrComments } from "../lib/fetch-pr-comments.js";
import { parseDiffLines } from "../lib/parse-diff-lines.js";

export async function runImplementPr(opts: { prNumber: string; repoDir: string; model: string; promptsDir: string }): Promise<void> {
  const { prNumber, repoDir, model, promptsDir } = opts;

  console.log(`[implement-pr] Fetching PR #${prNumber} data...`);
  const prContext = fetchPrComments({ prNumber, cwd: repoDir });

  const branch = execSync(`gh pr view ${prNumber} --json headRefName --jq .headRefName`, {
    encoding: "utf8",
    cwd: repoDir,
    stdio: ["ignore", "pipe", "pipe"],
  }).trim();

  const issueNumber = prContext.issueNumber || "(none)";
  const issueTitle = prContext.issueTitle || "(no linked issue)";

  console.log(`[implement-pr] PR: ${prContext.prTitle}`);
  console.log(`[implement-pr] Branch: ${branch}`);
  console.log(`[implement-pr] Linked issue: ${issueNumber === "(none)" ? "none" : `#${issueNumber} — ${issueTitle}`}`);
  console.log(`[implement-pr] Unresolved threads: ${prContext.comments.review_threads.length}`);

  try {
    const result = await run({
      agent: claudeCode(model),
      sandbox: noSandbox(),
      cwd: repoDir,
      promptFile: path.join(promptsDir, "implement-pr.md"),
      promptArgs: {
        PR_NUMBER: prNumber,
        BRANCH: branch,
        ISSUE_NUMBER: issueNumber,
        ISSUE_TITLE: issueTitle,
        PR_COMMENTS_JSON: JSON.stringify(prContext.comments, null, 2),
      },
      output: Output.object({ tag: "output", schema: ImplementPrOutput }),
      logging: { type: "stdout" },
    });

    const commitsThisRun = result.commits.length;
    const replyCount = result.output.threadReplies.length + result.output.newInlineComments.length + result.output.topLevelComments.length;

    if (commitsThisRun === 0 && replyCount === 0) {
      console.error(`[implement-pr] FAILED: Agent produced no commits and no replies`);
      process.exit(1);
    }

    const headSha = execSync(`gh pr view ${prNumber} --json headRefOid --jq .headRefOid`, {
      encoding: "utf8",
      cwd: repoDir,
      stdio: ["ignore", "pipe", "pipe"],
    }).trim();

    const diffOutput = (() => {
      try {
        return execSync(`gh pr diff ${prNumber}`, { encoding: "utf8", cwd: repoDir, stdio: ["ignore", "pipe", "pipe"] });
      } catch {
        return "";
      }
    })();
    const diffLines = parseDiffLines(diffOutput);

    const validInlineComments = result.output.newInlineComments.filter((c) => {
      const fileLines = diffLines.get(c.path);
      if (!fileLines) {
        console.warn(`[implement-pr] Dropping inline comment for ${c.path}:${c.line} — file not in diff`);
        return false;
      }
      if (!fileLines.has(c.line)) {
        console.warn(`[implement-pr] Dropping inline comment for ${c.path}:${c.line} — line not in diff hunks`);
        return false;
      }
      return true;
    });

    const validReplyIds = new Set(prContext.comments.review_threads.map((c) => c.commentId));
    const threadIdByCommentId = new Map(prContext.comments.review_threads.map((c) => [c.commentId, c.threadId]));
    const validThreadReplies = result.output.threadReplies.filter((r) => {
      if (!validReplyIds.has(r.commentId)) {
        console.warn(`[implement-pr] Dropping reply for commentId=${r.commentId} — not in fetched threads`);
        return false;
      }
      return true;
    });

    for (const reply of validThreadReplies) {
      const threadId = threadIdByCommentId.get(reply.commentId)!;
      console.log(`[implement-pr] Posting reply to thread ${threadId}...`);
      execFileSync(
        "gh",
        [
          "api", "graphql",
          "-F", `nodeId=${threadId}`,
          "-f", `body=${reply.body}`,
          "-f", "query=mutation($nodeId:ID!,$body:String!){addPullRequestReviewThreadReply(input:{pullRequestReviewThreadId:$nodeId,body:$body}){comment{id}}}",
        ],
        { cwd: repoDir, stdio: ["ignore", "pipe", "pipe"] },
      );
    }

    if (validInlineComments.length > 0 || result.output.topLevelComments.length > 0) {
      const reviewBody = result.output.topLevelComments.map((c) => c.body).join("\n\n") || "Addressed review feedback.";
      const reviewPayload = JSON.stringify({
        commit_id: headSha,
        event: "COMMENT",
        body: reviewBody,
        comments: validInlineComments.map((c) => ({ path: c.path, line: c.line, side: c.side, body: c.body })),
      });
      execSync(`gh api repos/{owner}/{repo}/pulls/${prNumber}/reviews --input -`, {
        input: reviewPayload,
        encoding: "utf8",
        cwd: repoDir,
        stdio: ["pipe", "pipe", "pipe"],
      });
      console.log(`[implement-pr] Posted review with ${validInlineComments.length} inline comments`);
    }

    console.log(`\n[implement-pr] Complete`);
    console.log(`  commits: ${commitsThisRun}`);
    console.log(`  thread replies: ${validThreadReplies.length}`);
    console.log(`  inline comments: ${validInlineComments.length}`);
    console.log(`  top-level comments: ${result.output.topLevelComments.length}`);
  } catch (error) {
    if (error instanceof StructuredOutputError) {
      console.error(`[implement-pr] Failed: malformed agent output`);
      console.error(`[implement-pr] Tag: <${error.tag}>`);
      console.error(`[implement-pr] Raw matched: ${error.rawMatched ?? "(no match found)"}`);
      if (error.cause) console.error(`[implement-pr] Cause:`, error.cause);
      process.exit(1);
    }
    throw error;
  }
}
