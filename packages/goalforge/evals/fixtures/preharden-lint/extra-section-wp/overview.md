---
name: extra-section-wp
title: "known-bad V5 fixture: command-shaped but an extra H2 section"
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
    command: "bash packages/goalforge/evals/run.sh"
    behaviors: []
goal_approved_version: null
---

## Goal

fixture outcome

## Verification

`bash packages/goalforge/evals/run.sh`

## Owned Files

none

## Depends On

None

## Checklist

- [ ] T1 do a thing {files: a} [b1]

## Notes

An extra section the C1 shape does not allow.

## Open Questions

None

## Decisions

- none yet

## Goal Changelog

- v1 2026-09-09 — created
