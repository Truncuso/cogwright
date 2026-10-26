---
name: wp-01-fixture
title: goal-changelog fixture
status: hardened
stage_updated: 2026-09-09
severity: LOW
parallel: false
depends_on: []
plan: tmpfeat
goal_approved_version: null
---

# goal-changelog fixture

Static schema-example fixture for scripts/tests/goalforge-goal-changelog.test.sh —
copied to a throwaway temp dir before every append so this file itself never
mutates.

## Goal Changelog

<!-- Append-only. Each row: - v<N> <date> facet=<facet> <old>→<new>; reason: <text> -->
