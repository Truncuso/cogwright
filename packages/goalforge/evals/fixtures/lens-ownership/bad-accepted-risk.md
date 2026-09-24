# fixture: bad-accepted-risk
# known-bad for b4 — `verification-coverage`'s single-pass cell records the
# concern as an accepted risk instead of folding it into the surviving pass.

| Concern class | 3x-panel owner | Single-pass owner | Verify-cluster owner |
| --- | --- | --- | --- |
| `correctness` | code | harden G3 | Gate B |
| `error-handling` | code | harden G3 | Gate B |
| `complexity-delta` | code | harden G3 | Gate B |
| `root-cause-ai-slop` | code | harden G3 | Gate B |
| `goal-measurability` | eval | harden G3 | Gate C |
| `verification-coverage` | eval | accepted risk | Gate C |
| `owned-files-scope` | docs | harden G3 | Gate A |
| `contract-slice` | docs | harden G3 | Gate C |
| `depends-on-direction` | docs | harden G3 | Gate C |
