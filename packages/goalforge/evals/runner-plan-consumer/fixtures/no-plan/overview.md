---
name: wp-no-plan-fixture
title: "no execution_plan: block — exercises the legacy standard-route, all-inline fallback"
status: executing
plan: goalforge
task_type: code
goal:
  outcome: "A feature overview with no execution_plan: block runs exactly as the pre-plan-consumer runner did — all chain steps, all inline, standard route."
  verification:
    strategy: deterministic
    check: "goalforge-plan-consumer.sh --route resolves to standard; --emit-batches emits one singleton batch per chain step in canonical order"
  constraints: []
  boundaries: []
inherits_from: goalforge
sources: []
---

<!-- Template: wp-overview v4 (frontmatter-first, flat layout) -->

## Goal

Deliberately carries NO `execution_plan:` block and NO `route:` field, so the
consumer must fall back to the canonical `standard` route and the full legacy
all-inline step list.

## Verification

```
bash skills/goalforge/run/scripts/goalforge-plan-consumer.sh --route skills/goalforge/evals/runner-plan-consumer/fixtures/no-plan/overview.md | grep -qx "standard"
```
