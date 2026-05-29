import { z } from "zod";

export const MergeOutput = z.object({
  merged: z.array(z.string()),
  failed: z.array(
    z.object({
      branch: z.string(),
      reason: z.string(),
    }),
  ),
  testsPassed: z.boolean(),
});

export type MergeOutput = z.infer<typeof MergeOutput>;
