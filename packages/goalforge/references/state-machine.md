# WP status state machine — legal transition edges

Single source of truth for which WP `status:` transitions are legal, which
require a `--reason`, and which are human-gated. Consumed by
`skills/sdd/scripts/sdd-transition.sh` (the write mechanism) and
`hooks/sdd-transition-guard.sh` (the advisory guard). Machine-parseable: the
`## Edges` table uses `|` as the stable delimiter; a row exists **iff** the edge
is legal.

## Policy (FREE-REVERSE)

WP states are linearly ordered:

| state | order |
|---|---|
| draft | 0 |
| spec | 1 |
| hardened | 2 |
| ready | 3 |
| executing | 4 |
| verified | 5 |

- **Forward** edge (`order(to) > order(from)`): legal, `reason_required: no`.
- **Reverse** edge (`order(to) < order(from)`, e.g. `verified→spec`,
  `verified→draft`, `ready→spec`): legal, `reason_required: yes`. Every
  later→earlier edge is sanctioned — the `sdd-validate.sh` integrity invariants
  and the WP/task monotonicity check are the guardrails, not a hand-curated
  reverse subset.
- **Human-gated**: `draft→ready` (feature gate) and `hardened→ready` (WP gate)
  carry `human_gated: yes`. The gate is enforced by the calling skill (it must
  obtain human approval before invoking the mechanism); the mechanism only
  records it. `human_gated` does not change edge legality or `reason_required`.
- **Signal-scoped auto-advance exception (`hardened→ready` only).** The calling
  skill may advance `hardened→ready` WITHOUT human approval **iff** all three
  hold: complexity verdict `simple` (zero S1–S5 tripped, per
  `sdd-wp-complexity.sh`), `severity ≤ MEDIUM`, and `task_type ≠ migration`.
  The transition MUST be written with `--mode auto` and a `--reason` naming the
  rule + signal evidence — the ledger row is the audit record. Any tripped
  signal, HIGH/CRITICAL severity, or migration WP keeps the human gate. The
  feature `draft→ready` gate has NO auto-advance exception. *(Deliberate
  guardrail change — ADR: adaptive-chain-routing.)*

`archived` is a terminal state reached only by explicit user action via
`sdd-archive` — it is intentionally **not** an edge target here, so the
transition mechanism never moves a WP to/from `archived`.

## Edges

| from | to | reason_required | human_gated |
|---|---|---|---|
| draft | spec | no | no |
| draft | hardened | no | no |
| draft | ready | no | yes |
| draft | executing | no | no |
| draft | verified | no | no |
| spec | draft | yes | no |
| spec | hardened | no | no |
| spec | ready | no | no |
| spec | executing | no | no |
| spec | verified | no | no |
| hardened | draft | yes | no |
| hardened | spec | yes | no |
| hardened | ready | no | yes |
| hardened | executing | no | no |
| hardened | verified | no | no |
| ready | draft | yes | no |
| ready | spec | yes | no |
| ready | hardened | yes | no |
| ready | executing | no | no |
| ready | verified | no | no |
| executing | draft | yes | no |
| executing | spec | yes | no |
| executing | hardened | yes | no |
| executing | ready | yes | no |
| executing | verified | no | no |
| verified | draft | yes | no |
| verified | spec | yes | no |
| verified | hardened | yes | no |
| verified | ready | yes | no |
| verified | executing | yes | no |

## Reverse-edge note

A reverse (regression) edge is a legitimate operation — e.g. `sdd-verify`
sending a WP back to `executing`, or a harden re-open `ready→spec`. It is logged
(ledger row with the `--reason`) and never deletes prior evidence: tasks keep
their `verified` status and `commit:` as superseded evidence; the ledger reverse
row is the supersession record.

# Feature status state machine — legal transition edges

Everything below governs FEATURE-level `status:` (a `plans/<feature>/overview.md`
whose frontmatter has `work_packages:`/`feature:` and NO `plan:` key), distinct
from the WP state machine above. `sdd-transition.sh` selects this table when the
target overview classifies as a feature. Same `|`-delimited machine-parseable
format; a row exists **iff** the feature edge is legal.

## Feature policy (FREE-REVERSE)

Feature states are linearly ordered:

| state | order |
|---|---|
| draft | 0 |
| spec | 1 |
| ready | 2 |
| active | 3 |
| executing | 4 |
| completed | 5 |

- **Forward** edge (`order(to) > order(from)`): legal, `reason_required: no`.
- **Reverse** edge (`order(to) < order(from)`): legal, `reason_required: yes` —
  mirrors the WP FREE-REVERSE policy (every later→earlier edge is sanctioned; a
  reverse feature transition needs a `--reason`).
- **Human-gated**: `draft→ready` and `spec→ready` (the feature review gate) carry
  `human_gated: yes`. The gate is enforced by the calling skill; the mechanism
  only records it.
- **`completed`** is reached from `executing` or `active` (and, forward-skipping,
  from any earlier state). `archived` is a terminal state reached ONLY via
  `sdd-archive` — it is intentionally **not** an edge target here, so the
  transition mechanism never moves a feature to/from `archived`.

## Feature edges

| from | to | reason_required | human_gated |
|---|---|---|---|
| draft | spec | no | no |
| draft | ready | no | yes |
| draft | active | no | no |
| draft | executing | no | no |
| draft | completed | no | no |
| spec | draft | yes | no |
| spec | ready | no | yes |
| spec | active | no | no |
| spec | executing | no | no |
| spec | completed | no | no |
| ready | draft | yes | no |
| ready | spec | yes | no |
| ready | active | no | no |
| ready | executing | no | no |
| ready | completed | no | no |
| active | draft | yes | no |
| active | spec | yes | no |
| active | ready | yes | no |
| active | executing | no | no |
| active | completed | no | no |
| executing | draft | yes | no |
| executing | spec | yes | no |
| executing | ready | yes | no |
| executing | active | yes | no |
| executing | completed | no | no |
| completed | draft | yes | no |
| completed | spec | yes | no |
| completed | ready | yes | no |
| completed | active | yes | no |
| completed | executing | yes | no |

## Feature reverse-edge note

A reverse feature edge (e.g. re-opening a `completed` feature back to `executing`
for a follow-up WP) is legitimate: logged as a ledger row with its `--reason`,
never deleting prior WP evidence. `archived` remains out of scope — use
`sdd-archive` for the terminal move.
