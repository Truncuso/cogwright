---
name: parallel-omits-step
title: "Parallel-omits-step fixture — parallel groups omit a declared step (harden dropped)"
route: standard
execution_plan:
  steps: [spec, decompose, harden]
  parallel: [[spec], [decompose]]
---

<!-- runner-plan-consumer eval fixture (task-04). Exercises WP goal.verification
     case (f): a structurally-valid plan whose parallel groups fail to COVER a
     declared step (harden) must be a HARD, non-silent rejection [D-PINS] — never
     a silent drop of the uncovered step from execution. -->

## Goal

Fixture feature: steps declare [spec, decompose, harden] but the parallel groups
cover only [spec, decompose]. The consumer must reject (non-zero exit), not
silently emit two batches and drop `harden`.
