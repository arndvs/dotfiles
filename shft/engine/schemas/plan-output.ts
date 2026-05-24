import { z } from "zod";

export const PlanOutput = z.object({
  issues: z.array(
    z.object({
      number: z.number(),
      title: z.string(),
      branch: z.string(),
    }),
  ).min(1),
});

export type PlanOutput = z.infer<typeof PlanOutput>;
