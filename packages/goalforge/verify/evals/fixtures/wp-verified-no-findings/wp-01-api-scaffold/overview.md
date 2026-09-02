---
name: wp-01-api-scaffold
title: Scaffold API and routing layer
status: verified
stage_updated: 2026-09-02
severity: MEDIUM
parallel: false
depends_on: []
plan: no-findings-feat
tags: []
task_type: code
goal:
  outcome: "The /notify and /subscribe routes answer on the scaffolded router"
  verification:
    strategy: deterministic
    check: "true"
  constraints: []
  boundaries: []
  iteration_policy: "iterate"
  blocked_stop: "stop"
inherits_from: no-findings-feat
relationships: []
sources: []
---
<!-- Template: wp-overview v4 (frontmatter-first, flat layout) -->

## Goal

(intentionally broken — the WP is `verified` but `findings.md` is absent)

## Tasks

| Task | Title | Status | Complexity |
|---|---|---|---|
| task-01-router-setup | Set up Express router | verified | low |
