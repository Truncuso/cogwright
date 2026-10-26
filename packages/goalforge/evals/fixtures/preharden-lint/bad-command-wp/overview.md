---
name: bad-command-wp
title: "known-bad V5 fixture: prose verification.command"
status: spec
schema_version: 6
register: spike
severity: LOW
task_type: code
depends_on: []
owned_files: []
parallel: false
contract_slice: [C1, C3]
human_required: null
plan: preharden-lint-fixtures
goal:
  outcome: "fixture outcome"
  verification:
    strategy: deterministic
    command: "Run the test suite and confirm everything looks good — no failures"
    behaviors: []
goal_approved_version: null
---

## Goal

fixture outcome

## Verification

Run the test suite and confirm everything looks good.

## Owned Files

none

## Depends On

None

## Checklist

- [ ] T1 do a thing {files: a} [b1]

## Open Questions

None

## Decisions

- none yet

## Goal Changelog

- v1 2026-09-09 — created
