---
name: goalloop-feat
title: Goal-loop fixture feature — spec
status: ready
created: 2026-06-07
feature: goalloop-feat
task_type: code
goal:
  outcome: "the parent feature goal (cascade source for inheriting WPs)"
  verification:
    strategy: deterministic
    check: "true"
  constraints: ["spec-safety-constraint"]
  boundaries: ["spec-boundary"]
  iteration_policy: "spec-iteration-policy"
  blocked_stop: "spec-blocked-stop"
---

<!-- Template: feature-spec v4 (frontmatter-first, flat layout) -->

## Design

Fixture spec — the cascade source for `wp-cascade` in the goalforge-execute goal-loop evals.
