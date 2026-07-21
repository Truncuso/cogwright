---
name: wp-01-x
title: dangling optional_depends_on target
status: ready
stage_updated: 2026-07-08
severity: LOW
cross_wp_contract: false
parallel: false
depends_on: []
optional_depends_on: [wp-99-ghost]
plan: d-dangling-optional-dep
tags: []
task_type: code
inherits_from: null
goal_approved_version: null
relationships: []
sources: []
---

<!-- Fixture: schema-v5 case (d) — optional_depends_on names a WP slug that does
     not exist anywhere in the walked plans tree. Expect: non-fatal WARN
     ("target not found ... non-gating"), never ERROR, exit 0. -->

## Goal

Fixture — no schema_version marker, so goal-mandatory does not apply here;
this case is purely about optional_depends_on existence-checking.

## Verification

n/a — fixture.

## Tasks

| Task | Title | Status | Complexity |
|---|---|---|---|

## Open Questions

(none)

## Decisions

## Goal Changelog
