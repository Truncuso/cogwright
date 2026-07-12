---
name: wp-met-deterministic
title: Goal-loop fixture — met via deterministic check
status: ready
stage_updated: 2026-06-07
task_type: code
goal:
  outcome: "the deterministic check passes (exit 0)"
  verification:
    strategy: deterministic
    check: "true"
---

<!-- Template: wp-overview v4 (frontmatter-first, flat layout) -->

## Goal

Deterministic strategy: `sdd-goal-eval` decides met=True in-script (exit 0).
