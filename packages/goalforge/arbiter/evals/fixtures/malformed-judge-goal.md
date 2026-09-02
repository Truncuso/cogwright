---
name: wp-01-malformed-bet
title: Hard-to-reverse bet, malformed arbitration input
status: ready
stage_updated: 2026-09-02
severity: HIGH
parallel: false
depends_on: []
plan: arbitrated-bet-feat
tags: []
task_type: analysis
goal:
  outcome: "The decision memo names the chosen direction and the rejected alternatives"
  verification:
    strategy: judge
    check: "a reviewer agrees the memo is complete"
  constraints: []
  boundaries: []
  iteration_policy: "iterate"
  blocked_stop: "stop"
relationships: []
sources: []
---
<!-- Template: wp-overview v4 (frontmatter-first, flat layout) -->

## Goal

(intentionally broken — `check` is a scalar, not the artifact/rubric/block_on mapping
the judge directive needs. The router must fail closed, never fabricate a verdict.)
