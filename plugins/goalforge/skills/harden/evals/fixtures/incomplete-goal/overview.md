---
name: incomplete-goal-feat
title: Incomplete Goal Feature
status: ready
created: 2026-06-07
feature: incomplete-goal-feat
work_packages: [wp-01-incomplete-goal]
relationships: []
sources: []
---
<!-- Template: feature-overview v4 (frontmatter-first, flat layout) -->

## Problem

A WP whose goal block is incomplete must be caught at hardening, not at runtime.

## Goal

The hardened→ready gate refuses a WP with an invalid/incomplete goal block.

## Scope

**In**: goal-facet completeness gating.
**Out**: everything else.

## Work Packages

| WP | Title | Status |
|---|---|---|
| wp-01-incomplete-goal | Incomplete goal WP | hardened |
