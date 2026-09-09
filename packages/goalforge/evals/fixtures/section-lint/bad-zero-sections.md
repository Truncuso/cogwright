---
name: wp-01-bad-zero
title: "known-bad: zero H2 sections"
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

No H2 sections at all — just body prose.
