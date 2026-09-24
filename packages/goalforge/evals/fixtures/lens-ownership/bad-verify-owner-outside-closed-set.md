# fixture: bad-verify-owner-outside-closed-set
# known-bad for b2 (F2) — `contract-slice`'s verify-cluster owner is `Gate D`,
# a value outside the closed set {Gate A, Gate B, Gate C}. Every other cell
# is valid so this fixture's sole defect is that one owner.

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
| `contract-slice` | docs | harden G3 | Gate D |
| `depends-on-direction` | docs | harden G3 | Gate C |
