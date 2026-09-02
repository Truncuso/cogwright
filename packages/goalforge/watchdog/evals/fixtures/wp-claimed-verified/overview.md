---
name: claimed-verified-feat
title: Claimed-Verified WP
status: ready
created: 2026-09-02
feature: claimed-verified-feat
work_packages: [wp-01-gap-audit]
relationships: []
sources: []
---
<!-- Template: feature-overview v4 (frontmatter-first, flat layout) -->

## Problem

A WP can claim `verified` while a child task is still only `implemented` — the
claimed-vs-implemented gap class.

## Goal

The validator catches the claimed-vs-implemented gap deterministically, so the
watchdog's semantic pass never has to.

## Scope

**In**: the claimed-vs-implemented gap class, in its mechanical form.
**Out**: the semantic gap classes (missing tests/docs, deviations).

## Work Packages

| WP | Title | Status |
|---|---|---|
| wp-01-gap-audit | Gap audit WP | verified |
