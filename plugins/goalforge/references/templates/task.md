---
name: task-01-<slug>
title: <one-line goal>
status: pending
complexity: medium
route: api
parallel: false
depends_on: []
# verify: use a block scalar (|). In it, ' and \ are literal — so grep BRE like
# 'a\|b' or 'a\.b' is safe. NEVER a double-quoted "verify:" — \| \. are invalid
# YAML escapes and break frontmatter parsing (status then reads as empty).
verify: |
  <exact cmd or check that proves the task done>
# commit: <sha>  # set by sdd-execute after the task's commit (required for verified under --strict)
# checkpoint:
#   last_step: 0
#   specialist: ""
#   model: ""
#   route: api
#   worktree: ""
#   discovered_by: ""
#   resumable: true
---

<!-- Template: task v4 (frontmatter-first, flat layout) -->

## Goal

<what this task delivers — one measurable sentence>

## Steps

1. <step>
2. <step>

## Verification

```
<verify command>
```
