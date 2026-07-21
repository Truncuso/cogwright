---
name: mixed-dispatch
title: "Mixed inline/agent dispatch fixture — decompose:agent, harden:inline within one parallel batch"
route: standard
execution_plan:
  steps: [spec, decompose, harden]
  dispatch:
    decompose: agent
    harden: inline
  parallel: [[spec], [decompose, harden]]
  tiers:
    decompose: opus
---

<!-- runner-plan-consumer eval fixture (task-02 authored). Exercises --dispatch-of:
     `decompose` resolves to `agent`, `harden` to explicit `inline`, and `spec`
     to the implicit legacy all-inline default — asserted via the consumer's
     stub dispatch log, never a live model call. Batch 2 mixes an agent member
     (decompose) with an inline member (harden) to confirm parallel batches with
     mixed dispatch are ordered correctly under declared-group semantics. -->

## Goal

Fixture feature exercising per-step inline-vs-agent dispatch resolution: a
contiguous 3-step path (spec → decompose → harden) whose second parallel batch
contains one agent-dispatched member and one inline-dispatched member.
