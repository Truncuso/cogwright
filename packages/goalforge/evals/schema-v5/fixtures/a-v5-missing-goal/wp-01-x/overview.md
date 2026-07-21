---
name: wp-01-x
title: v5 marked WP missing goal
status: ready
schema_version: 5
stage_updated: 2026-07-08
severity: LOW
cross_wp_contract: false
parallel: false
depends_on: []
plan: a-v5-missing-goal
tags: []
task_type: code
inherits_from: null
goal_approved_version: null
relationships: []
sources: []
---

<!-- Fixture: schema-v5 case (a) — schema_version:5 at status:ready with NO
     goal: block. Expect: goal_err (fatal), sys.exit(1) regardless of --strict. -->

## Goal

Deliberately absent (this fixture proves the goal-mandatory rejection path).

## Verification

n/a — fixture.

## Tasks

| Task | Title | Status | Complexity |
|---|---|---|---|

## Open Questions

(none)

## Decisions

## Goal Changelog
