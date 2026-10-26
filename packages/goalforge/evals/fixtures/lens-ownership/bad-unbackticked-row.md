# fixture: bad-unbackticked-row
# known-bad for b1 (S12) — an extra unbackticked class row duplicates
# `correctness`. The pre-fix, backtick-only extract_rows skips it (GREEN);
# the fixed extract_rows counts every `|` data row and catches the
# duplicate (RED). This fixture's sole defect is that trailing unbackticked
# row — every backticked row above it is valid.

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
| `depends-on-direction` | docs | harden G3 | Gate C |
| correctness | code | harden G3 | Gate B |
