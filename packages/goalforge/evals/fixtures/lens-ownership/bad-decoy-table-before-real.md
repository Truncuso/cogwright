# fixture: bad-decoy-table-before-real
# known-bad for b1 (F1 / codex second opinion) — a decoy pipe table, whose
# header row also reads "Concern class" but which sits under a different
# heading, appears before the real "## Concern-class ownership table"
# section. The decoy carries only the `depends-on-direction` row; the real
# table's own `depends-on-direction` row is deleted. Pre-fix, extract_rows
# re-armed on ANY header row containing "Concern class" text, so it unioned
# the decoy's one row with the real table's remaining rows and never noticed
# the real table was missing that class (false GREEN). Post-fix,
# extract_rows anchors strictly on the "## Concern-class ownership table"
# heading and ignores the decoy, so the real table's missing pinned class is
# caught (RED).

## Example

| Concern class | 3x-panel owner | Single-pass owner | Verify-cluster owner |
| --- | --- | --- | --- |
| `depends-on-direction` | docs | harden G3 | Gate C |

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
