# fixture: bad-owned-files-scope-not-gate-a
# known-bad for b2 — `owned-files-scope`'s verify-cluster owner is `Gate B`
# instead of the pinned `Gate A` (Gate A step 3 is the owned_files boundary
# check; human ruling 2026-09-24).

| Concern class | 3x-panel owner | Single-pass owner | Verify-cluster owner |
| --- | --- | --- | --- |
| `correctness` | code | harden G3 | Gate B |
| `error-handling` | code | harden G3 | Gate B |
| `complexity-delta` | code | harden G3 | Gate B |
| `root-cause-ai-slop` | code | harden G3 | Gate B |
| `goal-measurability` | eval | harden G3 | Gate C |
| `verification-coverage` | eval | harden G3 | Gate C |
| `owned-files-scope` | docs | harden G3 | Gate B |
| `contract-slice` | docs | harden G3 | Gate C |
| `depends-on-direction` | docs | harden G3 | Gate C |
