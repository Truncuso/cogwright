---
name: good-wp
title: "known-good V5 fixture: command-shaped verification, C1 sections"
status: spec
schema_version: 6
register: spike
severity: LOW
task_type: code
depends_on: []
owned_files: [packages/goalforge/scripts/goalforge-preharden-lint.sh]
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

packages/goalforge/scripts/goalforge-preharden-lint.sh

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
