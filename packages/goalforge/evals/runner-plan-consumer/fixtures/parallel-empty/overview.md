---
name: parallel-empty
title: "Parallel-empty fixture — parallel: [] with declared steps (all steps dropped)"
route: standard
execution_plan:
  steps: [spec, decompose, harden]
  parallel: []
---

<!-- runner-plan-consumer eval fixture (task-04). Exercises WP goal.verification
     case (f): parallel present but empty ([]) with a non-empty steps list would
     yield zero batches — silently executing NOTHING while exiting 0. This must
     be a HARD, non-silent rejection [D-PINS]. -->

## Goal

Fixture feature: steps declare [spec, decompose, harden] but parallel is an empty
list of groups, covering no step. The consumer must reject (non-zero exit), not
emit zero batches and report success.
