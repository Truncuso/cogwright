# fixture: bad-duplicate-owner
# known-bad for b1 — `correctness` has two rows (two owners in the same mode).

| Concern class | 3x-panel owner | Single-pass owner | Verify-cluster owner |
| --- | --- | --- | --- |
| `correctness` | code | harden G3 | Gate B |
| `correctness` | eval | harden G3 | Gate C |
| `error-handling` | code | harden G3 | Gate B |
| `complexity-delta` | code | harden G3 | Gate B |
| `root-cause-ai-slop` | code | harden G3 | Gate B |
| `goal-measurability` | eval | harden G3 | Gate C |
| `verification-coverage` | eval | harden G3 | Gate C |
| `owned-files-scope` | docs | harden G3 | Gate B |
| `contract-slice` | docs | harden G3 | Gate C |
| `depends-on-direction` | docs | harden G3 | Gate C |
