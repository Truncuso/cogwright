---
name: e-v5-complete-goal-present-dep
title: Fixture E - v5 complete goal plus present-target optional_depends_on
status: draft
created: 2026-07-08
feature: e-v5-complete-goal-present-dep
work_packages: [wp-01-x, wp-02-target]
relationships: []
sources: []
---

<!-- Fixture: schema-v5 case (e) — feature shell for wp-01-x + wp-02-target -->

## Problem

Fixture feature — case (e) exercises the positive direction: a v5-marked WP
WITH a complete goal: block at status:ready must be ACCEPTED, and an
optional_depends_on entry whose target EXISTS must emit no WARN. Without this
case an over-blocking validator (one that flags goal-mandatory or
optional_depends_on unconditionally) would still pass the suite.

## Goal

n/a — fixture.

## Scope

**In:** validator behavior on wp-01-x and wp-02-target.
**Out:** everything else.

## Work Packages

| WP | Title | Status |
|---|---|---|
| wp-01-x | v5, complete goal, present-target dep | ready |
| wp-02-target | optional_depends_on target | draft |
