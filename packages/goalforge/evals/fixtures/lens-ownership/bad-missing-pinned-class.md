# fixture: bad-missing-pinned-class
# known-bad for b1 — omits the T1-pinned `depends-on-direction` row entirely.

## Concern-class ownership table

| Concern class | 3x-panel owner | Single-pass owner | Verify-cluster owner |
| --- | --- | --- | --- |
| `correctness` | code | harden G3 | Gate B |
| `error-handling` | code | harden G3 | Gate B |
| `complexity-delta` | code | harden G3 | Gate B |
| `root-cause-ai-slop` | code | harden G3 | Gate B |
| `goal-measurability` | eval | harden G3 | Gate C |
| `verification-coverage` | eval | harden G3 | Gate C |
| `owned-files-scope` | docs | harden G3 | Gate A |
| `contract-slice` | docs | harden G3 | Gate C |
