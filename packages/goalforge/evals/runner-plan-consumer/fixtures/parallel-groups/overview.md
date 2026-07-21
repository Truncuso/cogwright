---
name: parallel-groups
title: "Parallel-groups fixture — parallel:[[spec],[decompose,harden]] read as two sequential batches"
route: standard
execution_plan:
  steps: [spec, decompose, harden]
  parallel: [[spec], [decompose, harden]]
---

<!-- runner-plan-consumer eval fixture (task-04). Exercises WP goal.verification
     case (c): a parallel: [[a],[b,c]] group is read as two sequential batches,
     the second containing two concurrent members. No dispatch/tiers hints — the
     plain parallel primitive only. -->

## Goal

Fixture feature exercising the generic parallel-groups primitive: a satisfiable
contiguous 3-step path whose parallel declaration yields exactly two ordered
batches — batch 1 = [spec], batch 2 = [decompose, harden] (two concurrent
members).
