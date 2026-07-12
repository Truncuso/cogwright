---
name: <wp-id>
title: <human title>
status: draft
schema_version: 5          # opt-in marker (schema.md "Version lineage"): makes
                            # goal: mandatory at ready/executing/verified
stage_updated: YYYY-MM-DD
severity: MEDIUM
cross_wp_contract: false   # set true at harden if this WP co-owns a file/section with another WP (complexity signal S5)
parallel: false
depends_on: []
plan: <feature>
tags: []
task_type: code            # code | research | ops | writing | optimization | analysis
goal:                      # optional goal object (Codex 6-part anatomy); omit for legacy WPs
  outcome: "<what is true when done — one measurable sentence>"
  verification:
    strategy: deterministic   # deterministic | numeric | judge | human
    check: "<command | metric spec | judge spec | gate prompt>"
  constraints: []
  boundaries: []
  iteration_policy: "<how to choose the next action after each attempt>"
  blocked_stop: "<when to halt and report paths exhausted>"
inherits_from: <feature-slug | null>   # cascade source for unset goal fields (WP-only)
goal_approved_version: null            # sha256[:12] of the goal block; set at harden gate; null until first approval
relationships: []
sources: []
---

<!-- Template: wp-overview v4 (frontmatter-first, flat layout) -->

## Goal

<one measurable sentence — what this WP delivers>

## Verification

<exact command or check that proves the WP done>

## Tasks

| Task | Title | Status | Complexity |
|---|---|---|---|
| | | | |

## Open Questions

<unresolved questions — answered entries move to findings.md>

## Decisions

<!-- Resolved design decisions (one `- ` item each). Count feeds complexity signal S2
     (decision_count). A decision usually starts as an Open Question that got answered. -->

## Goal Changelog

<!-- Append-only. Each row: - v<N> <date> facet=<facet> <old>→<new>; reason: <text> -->
