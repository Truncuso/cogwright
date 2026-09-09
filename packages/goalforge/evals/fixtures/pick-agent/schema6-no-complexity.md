---
name: wp-99-fixture
title: "Fixture WP for goalforge-pick-agent.test.sh"
status: ready
schema_version: 6
register: production
severity: MEDIUM
task_type: code
depends_on: []
owned_files: ["packages/goalforge/scripts/goalforge-pick-agent.py"]
parallel: false
contract_slice: [C1, C2]
human_required: null
plan: goalforge-overhaul
tags: []
relationships: []
sources: []
goal:
  outcome: "Fixture only — not a real WP."
  verification:
    strategy: deterministic
    command: "true"
    behaviors: []
goal_approved_version: null
---

## Goal

Fixture only.

## Verification

`true`

## Owned Files

packages/goalforge/scripts/goalforge-pick-agent.py

## Depends On

None

## Checklist

- [ ] T1 Fixture only.

## Open Questions

None

## Decisions

None

## Goal Changelog

None
