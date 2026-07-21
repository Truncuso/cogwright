---
name: wp-01-x
title: v5 marked WP with complete goal and present-target optional dep
status: ready
schema_version: 5
stage_updated: 2026-07-08
severity: LOW
cross_wp_contract: false
parallel: false
depends_on: []
optional_depends_on: [wp-02-target]
plan: e-v5-complete-goal-present-dep
tags: []
task_type: code
goal:
  outcome: "fixture WP goal is well-formed and complete"
  verification:
    strategy: deterministic
    check: "true"
  constraints: []
  boundaries: []
  iteration_policy: "n/a — fixture"
  blocked_stop: "n/a — fixture"
inherits_from: null
goal_approved_version: null
relationships: []
sources: []
---

<!-- Fixture: schema-v5 case (e), positive direction — schema_version:5 at
     status:ready WITH a complete goal: block (outcome + verification.strategy
     + verification.check all present) AND optional_depends_on pointing at
     wp-02-target, which EXISTS in this same feature. Expect: accepted
     (exit 0) AND zero WARN lines about optional_depends_on. -->

## Goal

Fixture WP goal is well-formed and complete.

## Verification

n/a — fixture (goal.verification.check is the fixture-internal check).

## Tasks

| Task | Title | Status | Complexity |
|---|---|---|---|

## Open Questions

(none)

## Decisions

## Goal Changelog
