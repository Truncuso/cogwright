---
name: wp-fixture-compile
title: "Fixture WP for goalforge-workflow-compile.py (b3)"
status: ready
schema_version: 6
register: production
severity: MEDIUM
task_type: code
stage_updated: 2026-09-10
depends_on: []
owned_files:
  - src/alpha/
  - src/beta/
  - src/gamma/
parallel: true
contract_slice: [C5]
plan: fixture
tags: []
goal:
  outcome: "The compiler turns this checklist into a Workflow script whose node shape is decided by the {files:} groups alone."
  verification:
    strategy: deterministic
    command: "bash scripts/tests/goalforge-workflow-compile.test.sh"
    behaviors:
      - id: f1
        given: "this fixture"
        when: "goalforge-workflow-compile.py runs"
        then: "group A and group B become parallel nodes; group C becomes a pipeline edge after A"
        oracle: "scripts/tests/goalforge-workflow-compile.test.sh"
---

## Goal

Fixture only. Three `{files:}` groups: **A** (4 items) and **B** (4 items) are
pairwise disjoint, so both compile to `parallel` nodes of 3-5 items. **C** (3
items) overlaps A's file set, so it compiles to a `pipeline` edge ordered
after A.

## Verification

Consumed by `scripts/tests/goalforge-workflow-compile.test.sh`; never executed.

## Owned Files

See frontmatter `owned_files`.

## Checklist

- [ ] T1 group A first item {files: src/alpha/one.ts} [f1]
- [ ] T2 group A second item {files: src/alpha/two.ts} [f1]
- [ ] T3 group A third item {files: src/alpha/three.ts} [f1]
- [ ] T4 group A fourth item {files: src/alpha/four.ts} [f1]
- [ ] T5 group B first item {files: src/beta/one.ts} [f1]
- [ ] T6 group B second item {files: src/beta/two.ts} [f1]
- [ ] T7 group B third item {files: src/beta/three.ts} [f1]
- [ ] T8 group B fourth item {files: src/beta/four.ts} [f1]
- [ ] T9 group C first item, overlaps A {files: src/alpha/one.ts, src/gamma/one.ts} [f1]
- [ ] T10 group C second item, overlaps A {files: src/alpha/two.ts, src/gamma/two.ts} [f1]
- [ ] T11 group C third item, overlaps A {files: src/alpha/three.ts, src/gamma/three.ts} [f1]

## Open Questions

- none (fixture).

## Decisions

- Fixture authored by wp-03/T2 for behavior b3.
