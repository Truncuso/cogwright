# Mutation-testing eval guards — house pattern

A deterministic check proves nothing until it has been shown to FAIL when the
fact it guards is violated. This reference is the house pattern for earning
that proof. It graduated from three feature laps of goalforge-prototype-native:
wp-04 (ad-hoc guard), wp-06 (committed `evals/interview-mutations.sh`, 6/6
mutations red), wp-07 (scratch-copy gate-fold checks).

## The pattern

1. **Scratch-copy** the package under test to a `mktemp -d` with a
   `trap 'rm -rf "$T"' EXIT` — never mutate the working tree.
2. **Baseline**: run the harness on the copy; require green (a red baseline
   invalidates every subsequent verdict).
3. **Mutate**: apply ONE targeted mutation per round — delete the guarded fact
   (a frontmatter line, a section, a note) or inject the forbidden state (the
   banned table row, the stale phrase). Assert the mutation actually landed
   (`assert new != text`) so a no-op mutation cannot fake a verdict.
4. **Assert RED**: the harness must exit non-zero. A check that stays green
   under its target mutation is **vacuous** — fix the check, not the test.
5. **Restore** (fresh copy per round) and repeat for each guarded fact.

Committed-harness form: `evals/interview-mutations.sh` (wp-06) — hermetic,
copies the package, runs N deletion mutations, exits 0 only if baseline is
green AND all N mutations are red. One-off form: a scratchpad script at
review/fold time (wp-07 gate fold).

## When it is REQUIRED

- Authoring a new eval-harness check block (the wp-04 F10 / wp-06 / wp-07
  additive-block pattern): every NEGATIVE check and every count assertion in
  the block gets one mutation round before the block is committed.
- A verification gate whose violation **cannot be red-baselined on HEAD**
  (the forbidden state does not exist yet): mutation-baseline it instead —
  inject the violation, watch the gate fire, ledger the result (wp-07
  findings.md §Mutation-baseline ledger).

## Corollary: judge-proposed checks get the same bar

A reviewer's PROPOSED check is a hypothesis, not a fix. At the wp-07 gate
fold, an opus/high reviewer's suggested Children-table row-count guard (count
`goalforge-` rows == 15) passed review logic but missed the unbackticked-row
bypass — the injected row did not change the counted class. Mutation-testing
the proposed check on a scratch copy exposed it in one round, and the fix
moved to the adjacent check (optional-backtick pattern). Apply step 3-4 to
every check a review proposes before folding it, with the same rigor as the
checks the review criticizes.

## Relation to red-baselining

Red-baselining (run the un-negated pattern on HEAD; require a match) proves a
negative grep is not vacuous **today**. Mutation-testing proves a check would
catch the violation **tomorrow**, after the WP closes and the guarded state is
the norm. Harden panels red-baseline; eval blocks mutation-test. Both ledger
into the WP's `findings.md`.
