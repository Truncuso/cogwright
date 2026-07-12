---
name: feature-active
title: An Active Feature That Must Not Be Archived
status: active
created: 2026-01-01
updated: 2026-01-05
feature: feature-active
work_packages: [wp-01-x]
relationships: []
sources: []
---
<!-- Template: feature-overview v4 (frontmatter-first, flat layout) -->

## Problem

Fixture: a feature still `active` (not all WPs verified). sdd-archive MUST
REFUSE to archive this — the fail-close case.

## Goal

Exercise the sdd-archive precondition gate (status != completed → refuse).
