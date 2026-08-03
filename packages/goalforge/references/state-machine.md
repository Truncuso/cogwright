# WP status state machine — legal transition edges

Single source of truth for which WP `status:` transitions are legal, which
require a `--reason`, and which are human-gated. Consumed by
`skills/goalforge/scripts/goalforge-transition.sh` (the write mechanism) and
`hooks/goalforge-transition-guard.sh` (the advisory guard). Machine-parseable: the
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
  later→earlier edge is sanctioned — the `goalforge-validate.sh` integrity invariants
  and the WP/task monotonicity check are the guardrails, not a hand-curated
  reverse subset.
- **Human-gated**: `draft→ready` (feature gate) and `hardened→ready` (WP gate)
  carry `human_gated: yes`. The gate is enforced by the calling skill (it must
  obtain human approval before invoking the mechanism); the mechanism only
  records it. `human_gated` does not change edge legality or `reason_required`.
- **Signal-scoped auto-advance exception (`hardened→ready` only).** The calling
  skill may advance `hardened→ready` WITHOUT human approval **iff** all three
  hold: complexity verdict `simple` (zero S1–S5 tripped, per
  `goalforge-wp-complexity.sh`), `severity ≤ MEDIUM`, and `task_type ≠ migration`.
  The transition MUST be written with `--mode auto` and a `--reason` naming the
  rule + signal evidence — the ledger row is the audit record. Any tripped
  signal, HIGH/CRITICAL severity, or migration WP keeps the human gate. The
  feature `draft→ready` gate has NO auto-advance exception. *(Deliberate
  guardrail change — ADR: adaptive-chain-routing.)*
- **Evidence-gated revert exception (`ready→hardened` only).** This one reverse
  edge — re-opening a `ready` WP back to `hardened` to re-develop its goals — is
  NOT a bare FREE-REVERSE move. The edge row stays legal
  (`| ready | hardened | yes | no |`), but the calling stage MUST write the
  transition with `mode: evidence` plus a validated re-harden evidence file
  (`--mode evidence --evidence <path>`; frontmatter `kind`/`locator`/`summary`
  per `references/templates/reharden-evidence.md`,
  `plans/<feature>/<wp>/reharden/<YYYY-MM-DD>-<slug>.md`). A bare-`--reason`
  revert for THIS specific edge is **refused** by the guard: `--reason` alone
  satisfies `reason_required: yes` for every other reverse edge, but the
  `ready→hardened` revert additionally requires the evidence gate. The re-harden
  is PROPOSED with typed evidence attached and recorded via the `reharden.proposed`
  / `reharden.accepted` trace events (see `references/trace-events.md`). The
  reverse `hardened→ready` **re-promotion keeps its human gate unchanged** — this
  exception adds NO new autonomous edge; goals are revised while the WP sits at
  `hardened`, then re-promoted through the same `human_gated: yes` WP gate (or its
  signal-scoped auto-advance) as before. *(Evidence MANDATORY on `ready→hardened`
  — ledgered decision; ADR: prototype-native-goalforge re-harden edge.)*

For a WP, `archived` is a terminal state reached only by an explicit out-of-band
edit: it is intentionally **not** an edge target here, so the transition mechanism
never moves a WP to/from `archived`, and no goalforge script writes it either —
`goalforge-archive` flips FEATURE overviews only (`set_field('status','archived')`
is invoked on the feature overview and, under `--supersedes`, the superseded
feature's overview; never on a `wp-*/overview.md`). It **is**
dep-satisfying: `goalforge-frontier.sh` and `goalforge-validate.sh` treat an
`archived` dep exactly as `verified` when resolving a sibling's `depends_on`.

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

A reverse (regression) edge is a legitimate operation — e.g. `goalforge-verify`
sending a WP back to `executing`, or a harden re-open `ready→spec`. It is logged
(ledger row with the `--reason`) and never deletes prior evidence: tasks keep
their `verified` status and `commit:` as superseded evidence; the ledger reverse
row is the supersession record.

# Feature status state machine — legal transition edges

Everything below governs FEATURE-level `status:` (a `plans/<feature>/overview.md`
whose frontmatter has `work_packages:`/`feature:` and NO `plan:` key), distinct
from the WP state machine above. `goalforge-transition.sh` selects this table when the
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
  `goalforge-archive` — it is intentionally **not** an edge target here, so the
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
`goalforge-archive` for the terminal move.
