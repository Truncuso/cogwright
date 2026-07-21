---
name: wp-01-x
title: legacy WP with no schema_version marker
status: ready
stage_updated: 2026-07-08
severity: LOW
cross_wp_contract: false
parallel: false
depends_on: []
plan: b-legacy-no-marker
tags: []
task_type: code
inherits_from: null
goal_approved_version: null
relationships: []
sources: []
---

<!-- Fixture: schema-v5 case (b) — no schema_version marker at all, status:ready,
     no goal: block. Legacy (<=v4) semantics: goal stays optional. Expect:
     accepted, exit 0. -->

## Goal

Legacy WP — goal block intentionally omitted; exempt under absent marker.

## Verification

n/a — fixture.

## Tasks

| Task | Title | Status | Complexity |
|---|---|---|---|

## Open Questions

(none)

## Decisions

## Goal Changelog
