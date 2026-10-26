---
name: wp-harden-high
title: "Fixture WP for goalforge-harden-stop.sh (b7)"
status: hardened
schema_version: 6
register: production
severity: HIGH
task_type: code
stage_updated: 2026-09-10
depends_on: []
owned_files:
  - src/fixture/
parallel: false
contract_slice: [C4]
plan: fixture
tags: []
goal:
  outcome: "Fixture WP whose severity/register select the 300k panel soft threshold in harden-stop."
  verification:
    strategy: deterministic
    command: "bash scripts/tests/goalforge-harden-stop.test.sh"
    behaviors:
      - id: f1
        given: "this WP at severity HIGH, register production"
        when: "goalforge-harden-stop.sh reads the trace"
        then: "the 300k panel soft threshold applies, not the 60k single-pass one"
        oracle: "scripts/tests/goalforge-harden-stop.test.sh"
---

## Goal

Fixture only. `severity: HIGH` + `register: production` is the combination
that selects the 300k panel soft threshold; the round cap stays the hard park.

## Verification

Copied into a `mktemp -d` root by `scripts/tests/goalforge-harden-stop.test.sh`
together with one of the `trace-b7-*.jsonl` fixtures; never executed in place.

## Owned Files

See frontmatter `owned_files`.

## Checklist

- [ ] T1 fixture placeholder {files: src/fixture/one.py} [f1]

## Open Questions

- none (fixture).

## Decisions

- Fixture authored by wp-03/T2 for behavior b7.
