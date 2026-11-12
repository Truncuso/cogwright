---
name: <feature>
title: "<human title>"
status: draft
schema_version: 6          # schema.md "Version lineage"; at 6 transition.sh
                            # admits spec -> ready only with --mode human
created: YYYY-MM-DD
feature: <feature>
# execution_plan:                  # optional; absent = standard route, all-inline
#   steps: [spec, decompose, harden, execute, verify]
#   dispatch: {spec: agent, decompose: agent, hygiene: agent}
#   parallel: [[spec], [decompose, hygiene]]
#   tiers: {explore: sonnet, spec_author: opus, judge: opus, boilerplate: haiku}
work_packages: []
relationships: []
sources: []
---

<!-- Template: feature-overview v4 (frontmatter-first, flat layout) -->

## Problem

<what problem does this feature solve>

## Goal

<one measurable sentence — what success looks like>

## Scope

**In:** <what is included>
**Out:** <what is explicitly excluded>

## Work Packages

| WP | Title | Status |
|---|---|---|
| | | |

## Links

- Spec: [spec.md](spec.md)
