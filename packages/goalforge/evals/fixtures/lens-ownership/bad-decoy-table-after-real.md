# fixture: bad-decoy-table-after-real
# known-bad for b1 (gate B N1) — the real table lacks `depends-on-direction`
# and a later table supplies it. Kills the mutant that re-arms after a blank
# line instead of exiting: it would union the later row into the real table
# (false GREEN); stopping for good at the first blank catches the gap (RED).

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

## Example

| Concern class | 3x-panel owner | Single-pass owner | Verify-cluster owner |
| --- | --- | --- | --- |
| `depends-on-direction` | docs | harden G3 | Gate C |
