---
name: wp-01-arbitrated-bet
title: Hard-to-reverse bet, arbitrated
status: ready
stage_updated: 2026-09-02
severity: HIGH
parallel: false
depends_on: []
plan: arbitrated-bet-feat
tags: []
task_type: analysis
goal:
  outcome: "The decision memo names the chosen direction, the rejected alternatives, and the verification gates"
  verification:
    strategy: judge
    check:
      artifact: "decision-memo.md"
      rubric: "chosen direction, rejected alternatives, verification gates, rollback"
      block_on: "FAIL"
  constraints: []
  boundaries: []
  iteration_policy: "iterate"
  blocked_stop: "stop"
relationships: []
sources: []
---
<!-- Template: wp-overview v4 (frontmatter-first, flat layout) -->

## Goal

A judgment goal MUST be routed out to arbitration — never decided by the pure router.
