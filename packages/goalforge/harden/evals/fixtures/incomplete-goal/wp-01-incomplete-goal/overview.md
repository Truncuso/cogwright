---
name: wp-01-incomplete-goal
title: Incomplete goal WP
status: hardened
stage_updated: 2026-06-07
severity: MEDIUM
parallel: false
depends_on: []
plan: incomplete-goal-feat
tags: []
task_type: code
goal:
  outcome: ""
  verification:
    strategy: deterministic
    check: "pytest -q"
  constraints: []
  boundaries: []
  iteration_policy: "iterate"
  blocked_stop: "stop"
inherits_from: incomplete-goal-feat
relationships: []
sources: []
---
<!-- Template: wp-overview v4 (frontmatter-first, flat layout) -->

## Goal

(intentionally incomplete — goal.outcome is empty; harden must NOT advance this to ready)

## Verification

pytest -q

## Tasks

| Task | Title | Status | Complexity |
|---|---|---|---|
| task-01 | placeholder | pending | low |

## Open Questions

- What is the measurable outcome? (UNRESOLVED — blocks hardened→ready)
