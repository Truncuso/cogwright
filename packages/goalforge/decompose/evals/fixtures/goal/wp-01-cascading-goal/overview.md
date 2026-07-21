---
name: wp-01-cascading-goal
title: Cascading goal WP
status: spec
stage_updated: 2026-06-07
severity: MEDIUM
parallel: false
depends_on: []
plan: goal-cascade-feat
tags: []
task_type: code
goal:
  outcome: "the api scaffold returns 200 on GET /health"
  verification:
    strategy: deterministic
    check: "curl -sf localhost:8080/health"
  constraints: ["no new external dependency"]
  boundaries: ["src/api/"]
  iteration_policy: ""
  blocked_stop: ""
inherits_from: goal-cascade-feat
relationships: []
sources: []
---
<!-- Template: wp-overview v4 (frontmatter-first, flat layout) -->

## Goal

The api scaffold returns 200 on GET /health.

## Verification

curl -sf localhost:8080/health

## Tasks

| Task | Title | Status | Complexity |
|---|---|---|---|
| task-01 | scaffold /health | pending | low |

## Open Questions

- none
