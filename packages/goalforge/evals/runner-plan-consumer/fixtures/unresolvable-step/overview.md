---
name: unresolvable-step
title: "Unresolvable step — steps names a member that is not a chain.yaml step basename (must be rejected)"
route: standard
execution_plan:
  steps: [spec, frobnicate, harden]
---

<!-- runner-plan-consumer eval fixture (task-04). Exercises WP goal.verification
     case (f), resolve-arm: `frobnicate` is not a chain.yaml step basename, so
     the consumer's semantic-consistency pass MUST reject the plan as a hard,
     non-silent failure (exit non-zero) — never a silent fallback [D-PINS]. -->

## Goal

Fixture feature whose `steps` names a phantom step (`frobnicate`) that resolves
to no chain.yaml step basename. The consumer must fail loudly.
