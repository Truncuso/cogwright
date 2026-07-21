---
name: precondition-inconsistent
title: "Precondition-inconsistent plan — non-contiguous steps:[spec,harden] (unsatisfiable path, must be rejected)"
route: standard
execution_plan:
  steps: [spec, harden]
  parallel: [[spec], [harden]]
---

<!-- runner-plan-consumer eval fixture (task-04). Exercises WP goal.verification
     case (f): steps:[spec,harden] skip the intervening `decompose`, so the path
     is non-contiguous / unsatisfiable in canonical chain order. The consumer's
     semantic-consistency pass MUST reject this as a hard, non-silent failure
     (exit non-zero) — never a silent fallback [D-PINS]. -->

## Goal

Fixture feature deliberately unsatisfiable: `steps` selects spec and harden but
skips decompose, breaking the contiguous-path precondition. The consumer must
fail loudly.
