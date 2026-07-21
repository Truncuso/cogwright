---
name: parallel-duplicate-step
title: "Parallel-duplicate-step fixture — a step listed in two parallel groups (double dispatch)"
route: standard
execution_plan:
  steps: [spec, decompose, harden]
  parallel: [[spec, decompose], [decompose, harden]]
---

<!-- runner-plan-consumer eval fixture (task-04). Exercises WP goal.verification
     case (f): a parallel declaration that lists the same step (decompose) in two
     groups must be a HARD, non-silent rejection [D-PINS] — never a plan that
     dispatches the duplicated step twice. -->

## Goal

Fixture feature: `decompose` appears in two parallel groups, so a naive consumer
would dispatch it in two separate batches. The consumer must reject (non-zero
exit) on the cross-group duplicate.
