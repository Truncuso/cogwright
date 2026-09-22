---
name: wp-reset-decision-ref
title: "fixture: parked WP for the b6 --decision-ref freshness gate"
status: hardened
schema_version: 6
register: spike
severity: LOW
task_type: code
depends_on: []
owned_files: []
parallel: false
contract_slice: [C1]
human_required: null
plan: harden-stop-fixtures
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
