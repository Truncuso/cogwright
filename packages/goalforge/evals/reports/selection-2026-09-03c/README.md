# selection-2026-09-03c/d/e — the corrected record

This directory is the correction lap for `2bfc0a8` and `77fb3bd`. It exists
because those two commits made claims that the committed evidence does not
support, and because the evidence itself was taken on a surface no commit
reproduces. **No history was rewritten** — the record is corrected here.

Everything below is re-derivable from the JSON in this tree. The jq that
produced each number is given; nothing is asserted from memory.

---

## 0. Why a report needs a surface hash

A trigger-eval report measures a **selection surface**, not a commit. The
runner stamps that surface as `config_dir.content_hash`. If the working tree
moved between the run and the commit — a transient uncommitted edit live during
the run, a later description change — the numbers describe a surface that no
commit reproduces, and every gain claimed from them is unfalsifiable.

The current-tree hash for a suite is what this prints, offline and free:

```
evals/trigger-run.sh --suite <name> --dry-run --with-siblings \
  | grep -o 'sha256:[0-9a-f]\{64\}'
```

`evals/selection.test.sh` now gates it: every report in the **newest** dated
`evals/reports/selection-*` directory must carry the hash the current tree
emits. Older directories are skipped out loud (`skip stale: historical — …`),
never silently.

## 1. Surface hashes, per commit

Computed in throwaway `git worktree` checkouts, one dry-run per suite:

| tree | implement | goalforge-run | verify |
|---|---|---|---|
| `2bfc0a8^` (baseline) | `00062ab5…` | `e6459af4…` | `51aa6967…` |
| `2bfc0a8` = `77fb3bd` (HEAD at lap start) | `f9ad7a2c…` | `503d1e2f…` | `3828b66e…` |
| this lap's tree (goalforge-run reverted) | `fe1985c3…` | `140535b2…` | `d0d55409…` |

## 2. What the committed reports actually measured

```
jq -r '.config_dir.content_hash' selection-2026-09-03*/**.json
```

| report | hash | reproduces |
|---|---|---|
| `03a/implement.json` | `00062ab5…` | **`2bfc0a8^`** |
| `03a/goalforge-run.json` | `e6459af4…` | **`2bfc0a8^`** |
| `03a/verify.json` | `51aa6967…` | **`2bfc0a8^`** |
| `03b/implement.json` | `edb4a491…` | **neither `2bfc0a8^` nor `2bfc0a8`** |
| `03b/goalforge-run.json` | `e3de29ed…` | **neither `2bfc0a8^` nor `2bfc0a8`** |
| `03b/verify.json` | `67dcab14…` | **neither `2bfc0a8^` nor `2bfc0a8`** |
| `03b/verify-reverted.json` | `3828b66e…` | **`2bfc0a8`** (both edits PRESENT) |

`2bfc0a8^` and `2bfc0a8` are the only two states this lap could have committed,
so every "after" number in `77fb3bd` — implement, goalforge-run and verify alike
— was taken on a surface that is not in the history. A transient uncommitted
`verify.md` edit was live during those runs.

**The one clean A/B on record** is therefore `03a/verify.json` (`51aa6967…`,
`2bfc0a8^`) against `03b/verify-reverted.json` (`3828b66e…`, `2bfc0a8`).

## 3. Corrections to the commit bodies

History is intact; these are the corrections.

### `2bfc0a8` — *fix(goalforge): disambiguate implement vs goalforge-run descriptions*

> "Baseline 2026-09-03a: implement 0/3 positives (all three routed to
> goalforge-run), goalforge-run 1/4."

**Wrong on the routing.** Two of the three went to `goalforge-run`; the third
went to `wayfind`, and one of the two was mixed.

```
jq -r '.cases[] | select(.should_trigger) | .case_id + " -> " +
       ([.trials[] | (.observed // "ABSTAIN")] | join(","))' \
   selection-2026-09-03a/implement.json
sel-pos-execute-named-wp -> goalforge-run,goalforge-run,goalforge-run
sel-pos-next-ready-wp    -> wayfind,wayfind,wayfind
sel-pos-run-subcycle     -> goalforge-run,implement,goalforge-run
```

`0/3 positives` and `goalforge-run 1/4` are correct.

> "After 2026-09-03b: implement positives 0/3 -> 1/3, negatives 1/4 -> 2/4;
> goalforge-run positives 1/4 held, negatives 1/4 -> 2/4."

**Unreproducible.** Those numbers are read off `03b` reports whose surface
hashes (`edb4a491…`, `e3de29ed…`) match neither `2bfc0a8^` nor `2bfc0a8`
(§2). They measure a tree that was never committed. The re-measurement on the
`2bfc0a8` surface is `03c` (§4).

> "A /verify description edit tried in the same lap regressed its suite and was
> reverted."

Accurate as to what was done; the surviving regression is §5.

### `77fb3bd` — *test(goalforge): selection reports 2026-09-03a/b*

> "verify-reverted.json is the control: verify's own files back at baseline,
> still pos 1/3 neg 0/4 ($0.116659). The verify negative drop reproduces with
> the surviving edits absent, so it is run-to-run drift on an abstain-heavy
> suite, not an effect of this lap's changes."

**Wrong on the control.** `verify-reverted.json` carries `3828b66e…`, which is
the `2bfc0a8` surface — the surviving `implement.md` and `goalforge-run.md`
edits were **PRESENT**, not absent. The control isolates the reverted
`verify.md` edit and nothing else, so it cannot license "not an effect of this
lap's changes"; it is precisely the run in which this lap's *surviving* changes
are live. The numbers quoted (`pos 1/3 neg 0/4`, `$0.116659`) are themselves
correct.

> "2026-09-03b — after the description edits: …"

**Unreproducible**, per §2 — the three `03b` suite reports measure an
uncommitted surface. The `03b` block should be read as a record of what was run,
not as an "after" measurement of `2bfc0a8`.

## 4. The measurements — a → c → d → e

Derived in one pass; the pipeline is the source of the table:

```
jq -r '"| \(input_filename | split("/")[0] | ltrimstr("selection-2026-09-")) | \(input_filename | split("/")[1] | rtrimstr(".json")) | \(.summary.trials_per_case) | \(.summary.positive_pass_k)/\(.summary.positive_cases) | \(.summary.negative_pass_k)/\(.summary.negative_cases) | \(.summary.hits) | \(.summary.abstains) | \(.summary.trial_errors) | \(.cost.total_usd) | \(.config_dir.content_hash[7:15]) |"' \
  selection-2026-09-03{a,b,c,d,e}/*.json
```

| lap | suite | k | pos pass^k | neg pass^k | hits | abstains | trial errors | cost USD | surface |
|---|---|---|---|---|---|---|---|---|---|
| 03a | goalforge-run | 3 | 1/4 | 1/4 | 5 | 9 | 3 | 0.092744 | `e6459af4` |
| 03a | implement | 3 | 0/3 | 1/4 | 1 | 7 | 0 | 0.083546 | `00062ab5` |
| 03a | verify | 3 | 1/3 | 2/4 | 7 | 6 | 0 | 0.085235 | `51aa6967` |
| 03b | goalforge-run | 3 | 1/4 | 2/4 | 5 | 8 | 3 | 0.098615 | `e3de29ed` |
| 03b | implement | 3 | 1/3 | 2/4 | 3 | 6 | 0 | 0.084498 | `edb4a491` |
| 03b | verify | 3 | 0/3 | 0/4 | 2 | 13 | 0 | 0.117680 | `67dcab14` |
| 03b | verify-reverted | 3 | 1/3 | 0/4 | 4 | 12 | 0 | 0.116659 | `3828b66e` |
| 03c | goalforge-run | 3 | 1/4 | 1/4 | 4 | 7 | 3 | 0.086196 | `503d1e2f` |
| 03c | implement | 3 | 1/3 | 1/4 | 3 | 8 | 0 | 0.092066 | `f9ad7a2c` |
| 03c | verify | 5 | 0/3 | 0/4 | 4 | 22 | 0 | 0.157019 | `3828b66e` |
| 03d | verify | 5 | 1/3 | 0/4 | 7 | 18 | 0 | 0.139323 | `7b10600f` |
| 03e | goalforge-run | 3 | 1/4 | 1/4 | 5 | 8 | 3 | 0.087694 | `140535b2` |
| 03e | implement | 3 | 0/3 | 2/4 | 2 | 6 | 0 | 0.081174 | `fe1985c3` |
| 03e | verify | 5 | 0/3 | 0/4 | 5 | 23 | 0 | 0.163218 | `d0d55409` |

Rows `03a`/`03b` are quoted from the committed reports; only `03a` reproduces
(§2). Every run: `haiku`, `--observe first`, `--with-siblings`,
`--max-cost-usd 0.20`, `capped=false` throughout.

What each lap is:

- **03c** — re-measurement on the `2bfc0a8` surface (hashes checked *before*
  the numbers were read). This is the honest "after" that `77fb3bd` claimed.
- **03d** — verify only, k=5, on a surface where `implement.md`'s when-NOT
  clause was narrowed (`the completion check is /verify` dropped).
- **03e** — the final tree, all three suites. It exists because the decisions in
  §5/§6 changed the surface *after* 03c/03d were taken; without it the newest
  committed reports would not reproduce, which is the exact defect this lap
  corrects.

## 5. The verify regression: real, and not caused by this lap's edits

`sel-neg-not-executed-yet` (owner `implement`, prompt asks to *dispatch a work
package's tasks*) is a `verify` negative that passed at baseline and has not
passed since:

```
jq -r '.cases[] | select(.case_id=="sel-neg-not-executed-yet") |
       [.trials[] | (.observed // "ABSTAIN")] | join(",")' \
   selection-2026-09-03{a,b,c,d,e}/verify*.json
```

| surface | observed |
|---|---|
| `03a/verify` — `2bfc0a8^` | `implement,implement,implement` (pass) |
| `03b/verify-reverted` — `2bfc0a8` | `ABSTAIN,ABSTAIN,ABSTAIN` |
| `03c/verify` — `2bfc0a8`, k=5 | `ABSTAIN ×5` |
| `03d/verify` — narrowed when-NOT, k=5 | `ABSTAIN ×5` |
| `03e/verify` — final tree, k=5 | `ABSTAIN ×5` |

The narrowing hypothesis — that `implement.md`'s `the completion check is
/verify` clause suppressed `implement` here — is **not supported**: dropping
that clause (03d) left the case at 5/5 abstain, so the narrowing was discarded
and `implement.md` stands at its `2bfc0a8` text. The case also stays abstained
at 03e, on a tree where `goalforge-run.md` is back at baseline. The regression
is therefore attributable to `implement.md`'s `2bfc0a8` rewrite as a whole, or
to drift on a suite that abstains 18–23 times out of 35; this lap did not
separate the two. It is an open finding, not a fixed one.

Note also that `verify` positives are unstable across every lap at this k:
`sel-pos-check-and-advance` is a `wayfind`/`recap` magnet on all five surfaces.

## 6. Decisions, and the rule that produced them

Rule applied per file: keep the `2bfc0a8` description only if the
`2bfc0a8`-surface re-measurement (03c) is ≥ the `2bfc0a8^` baseline (03a) on
**both** `summary.positive_pass_k` and `summary.hits`.

| file | 03a (baseline) | 03c (2bfc0a8 surface) | verdict |
|---|---|---|---|
| `commands/implement.md` | pos 0, hits 1 | pos 1, hits 3 | **kept** — 1 ≥ 0 and 3 ≥ 1 |
| `commands/goalforge-run.md` | pos 1, hits 5 | pos 1, hits 4 | **reverted** — pos held but hits 4 < 5 |

`commands/implement.md` is byte-identical to `2bfc0a8`;
`commands/goalforge-run.md` is byte-identical to `2bfc0a8^`. Both verified with
`git diff --stat <rev> -- <path>` returning empty. `plugins/goalforge/commands/`
regenerated via `scripts/goalforge-generate.sh`.

Read the implement verdict narrowly. `03e/implement` — same description, one lap
later, `goalforge-run.md` at baseline — is pos 0/3, hits 2. The decision rule
was applied as specified, but a k=3 haiku suite whose positives move 0→1→0
across three laps is not evidence that the description is better; it is evidence
that this suite has too little power to rank two descriptions. Treat "kept" as
"not shown to be worse", nothing more.

## 7. Spend

```
jq -s 'map(.cost.total_usd) | {n: length, total: (add*1000000|round/1000000)}' \
   selection-2026-09-03{c,d,e}/*.json
{"n": 7, "total": 0.80669}
```

**$0.806690** for this lap (03c + 03d + 03e), against a $1.20 ceiling. Prior
laps, unchanged: 03a `$0.261525`, 03b `$0.417452`.
