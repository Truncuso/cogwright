---
name: v6-live-root-exempt-wp
title: "known-good V6 fixture: live-root literal plus a shipped fixture root (exemption conjunct)"
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
    behaviors:
      - id: b2
        given: "packages/goalforge/evals/fixtures/roster/ ships the map; resolution root ${CLAUDE_CONFIG_DIR:-$HOME/.claude} is overridden to the fixtures/ tree"
        when: "the map test runs"
        then: "every value resolves"
        oracle: "known-bad maps (bare name, missing path) exit 2, the map exits 0"
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

- [ ] T1 do a thing {files: a} [b2]

## Open Questions

None

## Decisions

- none yet

## Goal Changelog

- v1 2026-09-09 — created
