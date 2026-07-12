---
name: task-01-scaffold
title: scaffold /health
status: pending
complexity: low
route: api
parallel: false
depends_on: []
verify: "test -f src/routes/health.ts"
---

<!-- Template: task v4 (frontmatter-first, flat layout) -->

## Goal

Scaffold the `/health` route (fixture task for the cascading-goal validation test).

## Verification

```
test -f src/routes/health.ts
```
