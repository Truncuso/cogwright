---
name: <wp-id>
title: "<human title>"
status: spec               # spec|hardened|ready|executing|implemented|verified|abandoned|archived
schema_version: 6          # C1-C7 slim shape (schema.md "Version lineage")
register: spike             # spike|production
severity: MEDIUM            # LOW|MEDIUM|HIGH
task_type: code             # code|docs|research|ops
stage_updated: YYYY-MM-DD
depends_on: []
owned_files: []              # the WP's file boundary; verify gate A diff must be a subset
parallel: false
contract_slice: [C1, C2, C3, C4, C5, C6, C7]
human_required: null         # null, or "<reason>" naming why a human must gate this WP
plan: <feature>
tags: []
relationships: []
sources: []
goal:
  outcome: "<what is true when done — one measurable sentence>"
  verification:
    strategy: deterministic   # deterministic | judge | human
    command: "<the exact reproducible command — command-only, no prose>"
    behaviors: []             # optional; b1..bN oracle rows the Checklist tags reference
goal_approved_version: null   # sha256[:12] of outcome+verification; set at harden gate
---

<!-- Template: wp-overview v4 (frontmatter-first, flat layout) -->

## Goal

<mirror of goal.outcome>

## Verification

<rendered goal.verification: command, behaviors>

## Owned Files

<the boundary; diff paths at verify gate A must be a subset of frontmatter owned_files>

## Depends On

<WP ids this WP cannot start before, or "None">

## Checklist

<!-- - [ ] T1 <imperative outcome> {files: a, b} [b1,b2] -->

## Open Questions

<unresolved questions — answered entries move to findings.md>

## Decisions

<!-- Resolved design decisions (one `- ` item each). -->

## Goal Changelog

<!-- Append-only. Each row: - v<N> <date> facet=<facet> <old>→<new>; reason: <text> -->
