---
name: wp-01-bad-extra
title: "known-bad: extra H2 section"
status: spec
schema_version: 6
register: spike
severity: LOW
task_type: code
depends_on: []
owned_files: []
parallel: false
contract_slice: [C1]
human_required: null
plan: section-lint-fixtures
goal:
  outcome: "fixture outcome"
  verification:
    strategy: deterministic
    command: "true"
    behaviors: []
goal_approved_version: null
---

## Goal

fixture outcome

## Verification

`true`

## Owned Files

none

## Depends On

None

## Checklist

- [ ] T1 do a thing {files: a} [b1]

## Notes

An extra section not in the C1 8-section shape — must be rejected.

## Open Questions

None

## Decisions

- none yet

## Goal Changelog

- v1 2026-09-09 — created
