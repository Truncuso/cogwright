---
name: fixture-wave-execution-plan
route: wave
execution_plan:
  route: wave
  steps:
    - explore-fan-out
    - parallel-spec-authors
    - cross-spec-judge
    - fixer
---

<!-- Positive fixture: a route: wave feature whose execution_plan.steps lists the
     ACTIVE four-stage choreography in order. Asserted by evals/wave-route/run.sh
     check (a). The four active stages are explore fan-out, parallel spec authors,
     the cross-spec judge, and the fixer. Cold tier-1 audits and the hygiene agent
     are deferred and intentionally absent. route: is pinned explicitly above. -->
