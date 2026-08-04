---
name: feature-inbound-edge
title: A Live Feature Holding A Typed Relation Edge Into The Archive Target
status: active
created: 2026-01-01
updated: 2026-01-10
feature: feature-inbound-edge
work_packages: [wp-01-x]
relationships:
  - depends_on: [[feature-completed]]
sources: []
---
<!-- Template: feature-overview v4 (frontmatter-first, flat layout) -->

## Problem

Fixture: a live feature whose `relationships` hold a typed wikilink edge into
`feature-completed` — the feature under archival. Typed relation edges are graph
edges: they SURVIVE archiving and resolve to the archived target. Only PATH refs
(`<slug>/`) dangle on the move and gate under `--strict-refs`.

## Goal

Pin the design against over-tightening: the reference-gate must NOT be widened
to refuse archiving because inbound `[[<slug>]]` edges exist.
