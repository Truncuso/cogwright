---
name: three-step
title: "Happy-path execution_plan fixture — satisfiable contiguous steps:[spec,decompose,harden]"
route: standard
execution_plan:
  steps: [spec, decompose, harden]
  dispatch:
    decompose: agent
  parallel: [[spec], [decompose, harden]]
  tiers:
    decompose: opus
---

<!-- runner-plan-consumer eval fixture (task-01 authored; task-04 reuses in the full suite). -->

## Goal

Fixture feature exercising the deterministic execution_plan consumer: a
satisfiable, contiguous 3-step path (spec → decompose → harden) with one
parallel batch containing two concurrent members, one agent-dispatch hint, and
one OPAQUE tier hint.
