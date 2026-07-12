---
name: goal-cascade-feat-spec
title: Goal Cascade Feature — spec
status: spec
created: 2026-06-07
feature: goal-cascade-feat
task_type: code
goal:
  outcome: "the feature is delivered with every WP goal validating and cascading"
  verification:
    strategy: deterministic
    check: "bash run-all-tests.sh"
  constraints: ["no regression in existing tests"]
  boundaries: ["src/", "tests/"]
  iteration_policy: "fix the first failing check, then re-run the whole suite"
  blocked_stop: "halt and report after 3 consecutive failed attempts"
---
<!-- Template: feature-spec v4 (frontmatter-first, flat layout) -->

## Design

The feature goal block is the parent; each WP derives its own goal block and
cascades unset scalars / unioned lists via inherits_from.

## Interface Contract

- WP goal blocks set their own outcome + verification (never inherited).

## Non-Goals

- Anything outside goal-block derivation.

## Open Questions

- none
