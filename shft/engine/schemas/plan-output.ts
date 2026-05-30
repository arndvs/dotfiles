import { z } from "zod";

export const PlanOutput = z.object({
  issues: z.array(
    z.object({
      number: z.number(),
      title: z.string(),
      branch: z.string(),
    }),
  ),
});

export type PlanOutput = z.infer<typeof PlanOutput>;
