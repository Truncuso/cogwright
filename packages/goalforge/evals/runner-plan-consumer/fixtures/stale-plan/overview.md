---
name: stale-plan
title: "Stale/hand-edited plan — dispatch/parallel key names a step absent from steps (must be rejected)"
route: standard
execution_plan:
  steps: [spec, decompose, harden]
  dispatch:
    execute: agent
  parallel: [[spec], [decompose, harden]]
---

<!-- runner-plan-consumer eval fixture (task-04). Exercises WP goal.verification
     case (f): a stale/hand-edited plan whose dispatch key (`execute`) names a
     step absent from `steps`. The consumer's semantic-consistency pass MUST
     reject this as a hard, non-silent failure (exit non-zero) — never a silent
     fallback [D-PINS]. -->

## Goal

Fixture feature deliberately inconsistent: the dispatch map names `execute`, a
step that is not among the selected `steps`. The consumer must fail loudly.
