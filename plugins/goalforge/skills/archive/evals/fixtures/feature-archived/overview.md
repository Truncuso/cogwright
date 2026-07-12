---
name: feature-archived
title: A Stranded Archived Feature At The Active Root
status: archived
created: 2026-01-01
updated: 2026-01-10
feature: feature-archived
work_packages: [wp-01-x]
relationships: []
sources: []
---
<!-- Template: feature-overview v4 (frontmatter-first, flat layout) -->

## Problem

Fixture: a feature already `status: archived` but still physically at the active
plans root (status set out-of-band, never moved). The default archive gate REFUSES
it (not `completed`); `--relocate` is the handler that moves it into `_archived/`.

## Goal

Exercise the sdd-archive `--relocate` gate (requires `status: archived`).
