# fixture: bad-indented-duplicate-row
# known-bad for b1 (F3) — a trailing row, indented two spaces, duplicates
# `correctness`. Pre-fix, the row guards `^\|`/`^\| *-` are anchored flush
# left and never see an indented row (false GREEN, the class is not seen as
# owned twice). Post-fix, the guards accept leading whitespace
# (`^[ \t]*\|`), so the indented row is parsed and the duplicate is caught
# (RED). Every other row is valid so this fixture's sole defect is that
# trailing indented duplicate.

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
  | `correctness` | code | harden G3 | Gate B |
