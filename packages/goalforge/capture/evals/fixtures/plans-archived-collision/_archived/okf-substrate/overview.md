---
name: okf-substrate
title: An Archived Feature Whose Slug Is Free At The Active Root
status: archived
created: 2026-05-01
updated: 2026-07-20
feature: okf-substrate
work_packages: [wp-01-x]
relationships: []
sources: []
---
<!-- Template: feature-overview v4 (frontmatter-first, flat layout) -->

## Problem

Fixture: a feature already archived and moved to `_archived/`. Its slug is now
ABSENT from the active plans root, so a naive `Folder absent → create it`
idempotency check reads it as a fresh slug and stamps a second `status: draft`
node for the same feature (live defect, 2026-08-03).

## Goal

Exercise the goalforge-capture Step 2 archived-collision probe: capture must
HALT and present restore-vs-new-slug, never stamp a fresh draft.
