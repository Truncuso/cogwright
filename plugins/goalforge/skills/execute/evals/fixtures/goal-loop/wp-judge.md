---
name: wp-judge
title: Goal-loop fixture — met via judge (dispatch directive)
status: ready
stage_updated: 2026-06-07
task_type: writing
goal:
  outcome: "the design doc has no blocking findings"
  verification:
    strategy: judge
    check:
      artifact: "docs/design.md"
      rubric: "internal consistency, no contradictions"
      block_on: [CRITICAL, HIGH]
---

<!-- Template: wp-overview v4 (frontmatter-first, flat layout) -->

## Goal

Judge strategy: `sdd-goal-eval` returns met=null + a `{dispatch: judge, ...}` directive.
The eval MOCKS the judge dispatch (no live model) and asserts the agent maps a
no-blocking-findings verdict → met=True (design §8.3).
