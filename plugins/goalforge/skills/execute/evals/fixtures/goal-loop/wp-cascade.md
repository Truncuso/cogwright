---
name: wp-cascade
title: Goal-loop fixture — cascade inheritance from feature spec
status: ready
stage_updated: 2026-06-07
task_type: code
goal:
  outcome: "this WP declares its own outcome (never inherited)"
  verification:
    strategy: deterministic
    check: "true"
  constraints: ["wp-own-constraint"]
inherits_from: goalloop-feat
---

<!-- Template: wp-overview v4 (frontmatter-first, flat layout) -->

## Goal

Cascade: `resolve_effective_goal(wp, spec_fm=spec)` keeps the WP's own outcome/
verification, unions constraints (wp-own ∪ spec-safety), and inherits the spec's
scalars (iteration_policy, blocked_stop) + boundaries since the WP leaves them unset.
