---
name: c-execution-plan-roundtrip
title: Fixture C - execution_plan block round-trip
status: draft
created: 2026-07-08
feature: c-execution-plan-roundtrip
route: wave
execution_plan:
  steps: [spec, decompose, harden, execute, verify]
  dispatch:
    spec: agent
    decompose: agent
    hygiene: agent
  parallel: [[spec], [decompose, hygiene]]
  tiers: {explore: haiku, spec_author: sonnet, judge: opus, boilerplate: haiku}
work_packages: []
relationships: []
sources: []
---

<!-- Fixture: schema-v5 case (c) — a full execution_plan: block (4-route enum
     value `wave` + steps/dispatch/parallel/tiers keys) on the FEATURE overview.
     Expect: parses clean, round-trips through sdd-validate.sh with zero
     errors/warnings (exit 0). No WPs needed — the block is feature-level data,
     inert to the validator (no execution_plan-specific check exists; only
     FEATURE_REQUIRED + YAML-parses-clean apply). -->

## Problem

Fixture feature — case (c) only exercises frontmatter round-trip.

## Goal

n/a — fixture.

## Scope

**In:** execution_plan: block parsing.
**Out:** everything else.

## Work Packages

| WP | Title | Status |
|---|---|---|
