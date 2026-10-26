# WP status state machine — legal transition edges

Single source of truth for which WP `status:` transitions are legal, which
require a `--reason`, and which are human-gated. Consumed by
`scripts/goalforge-transition.sh` (the write mechanism) and
`hooks/goalforge-transition-guard.sh` (the advisory guard). Machine-parseable: the
`## Edges` table uses `|` as the stable delimiter; a row exists **iff** the edge
is legal.

## Policy (FREE-REVERSE)

WP states are linearly ordered (C2, wp-01 T6/T10 — a WP is born `spec`, there
is no WP-level `draft`; `implemented`/`abandoned` are new):

| state | order |
|---|---|
| spec | 0 |
| hardened | 1 |
| ready | 2 |
| executing | 3 |
| implemented | 4 |
| verified | 5 |

A schema-5 WP still carrying the legacy `draft` status is read-only
compatible: it sorts before `spec` (order -1) for any script that must order
it, but no goalforge script writes `draft` to a WP going forward.

- **Forward** edge (`order(to) > order(from)`): legal, `reason_required: no`.
- **Reverse** edge (`order(to) < order(from)`, e.g. `verified→spec`,
  `ready→spec`): legal, `reason_required: yes`. Every
  later→earlier edge is sanctioned — the `goalforge-validate.sh` integrity invariants
  and the WP monotonicity check are the guardrails, not a hand-curated
  reverse subset.
- **Human-gated**: `hardened→ready` (WP gate) carries `human_gated: yes`. The
  gate is enforced by the calling skill (it must obtain human approval before
  invoking the mechanism); the mechanism only records it. `human_gated` does
  not change edge legality or `reason_required`. A WP whose frontmatter sets
  `human_required:` is never auto-advanced regardless of signal (C7).
- **Signal-scoped auto-advance exception (`hardened→ready` only).** The calling
  skill may advance `hardened→ready` WITHOUT human approval **iff** all hold:
  `severity ≤ MEDIUM`, `human_required:` is unset, and — where a `task_type`
  is declared — `task_type ≠ migration`. The transition MUST be written with
  `--mode auto` and a `--reason` naming the rule + signal evidence — the
  ledger row is the audit record. HIGH/CRITICAL severity, a set
  `human_required:`, or a migration `task_type` keeps the human gate.
  *(Deliberate guardrail change — ADR: adaptive-chain-routing; narrowed at
  wp-01 T6 with the complexity-route removal.)*
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

For a WP, `abandoned` and `archived` are terminal states reached only by an
explicit out-of-band edit: they are intentionally **not** edge targets here,
so the transition mechanism never moves a WP to/from either, and no goalforge
script writes them either — `goalforge-archive` flips FEATURE overviews only
(`set_field('status','archived')` is invoked on the feature overview and,
under `--supersedes`, the superseded feature's overview; never on a
`wp-*/overview.md`). Both **are** dep-satisfying: `goalforge-frontier.sh` and
`goalforge-validate.sh` treat an `abandoned`/`archived` dep exactly as
`verified` when resolving a sibling's `depends_on`.

## Edges

| from | to | reason_required | human_gated |
|---|---|---|---|
| spec | hardened | no | no |
| spec | ready | no | no |
| spec | executing | no | no |
| spec | implemented | no | no |
| spec | verified | no | no |
| hardened | spec | yes | no |
| hardened | ready | no | yes |
| hardened | executing | no | no |
| hardened | implemented | no | no |
| hardened | verified | no | no |
| ready | spec | yes | no |
| ready | hardened | yes | no |
| ready | executing | no | no |
| ready | implemented | no | no |
| ready | verified | no | no |
| executing | spec | yes | no |
| executing | hardened | yes | no |
| executing | ready | yes | no |
| executing | implemented | no | no |
| executing | verified | no | no |
| implemented | spec | yes | no |
| implemented | hardened | yes | no |
| implemented | ready | yes | no |
| implemented | executing | yes | no |
| implemented | verified | no | no |
| verified | spec | yes | no |
| verified | hardened | yes | no |
| verified | ready | yes | no |
| verified | executing | yes | no |
| verified | implemented | yes | no |

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

- **Forward** edge (`order(to) > order(from)`): legal, `reason_required: no` —
  except out of `draft` and `spec`: for a feature that is not `route: fast`,
  the only forward edge out of `draft` is `draft -> spec` and the only one out
  of `spec` is `spec -> ready`. There is no `draft -> ready` row and no
  `draft|spec -> active|executing` or `spec -> completed` row, and the one
  `draft -> completed` row is scoped to `route: fast`, so every path from `draft` or `spec` onward passes `spec -> ready`.
- **Reverse** edge (`order(to) < order(from)`): legal, `reason_required: yes` —
  mirrors the WP FREE-REVERSE policy (every later→earlier edge is sanctioned; a
  reverse feature transition needs a `--reason`).
- **Human-gated**: `spec -> ready` is the single spec-approval gate (the
  ratification of a first spec and of a revision alike) and the only feature
  edge that carries `human_gated: yes`. `draft -> spec` is the ungated
  proposal edge. The gate is enforced by the calling skill; the mechanism
  only records it.
- **Respec edges**: `ready -> spec`, `active -> spec`, `executing -> spec` and
  `completed -> spec` are the reverse rows a spec-invalidating learning takes
  (`--reason "<learning>"`); a feature at `spec` means "a proposal awaits
  ratification". Proposal, ratification marker and apply:
  `references/respec.md`.
- **`completed`** is reached from `executing` or `active` (and, forward-skipping,
  from `ready` or later). One exit is route-scoped: `draft -> completed` is legal only for a `route: fast` feature with no `spec.md`
  (human ruling H3, "Scoped exit for fast": a fast feature is never specced,
  so this exit bypasses no spec-approval gate). `goalforge-transition.sh`
  takes a row whose `route` is not `any` only when the feature overview's
  top-level `route:` scalar (trailing ` # comment` and quotes stripped) equals
  it — a missing `route:` never matches — and, for `fast`, only when
  `<feature>/spec.md` is absent. `archived` is a terminal state reached ONLY via
  `goalforge-archive` — it is intentionally **not** an edge target here, so the
  transition mechanism never moves a feature to/from `archived`.

## Feature edges

The fifth column `route` scopes a row to features whose overview carries that
`route:` value; `any` applies to every feature. Every row here carries five
cells: a row with fewer is an `edge_lookup` error (refused), never read as
`any`. (The WP `## Edges` table above has four columns and reads as `any`.)

| from | to | reason_required | human_gated | route |
|---|---|---|---|---|
| draft | spec | no | no | any |
| draft | completed | no | no | fast |
| spec | draft | yes | no | any |
| spec | ready | no | yes | any |
| ready | draft | yes | no | any |
| ready | spec | yes | no | any |
| ready | active | no | no | any |
| ready | executing | no | no | any |
| ready | completed | no | no | any |
| active | draft | yes | no | any |
| active | spec | yes | no | any |
| active | ready | yes | no | any |
| active | executing | no | no | any |
| active | completed | no | no | any |
| executing | draft | yes | no | any |
| executing | spec | yes | no | any |
| executing | ready | yes | no | any |
| executing | active | yes | no | any |
| executing | completed | no | no | any |
| completed | draft | yes | no | any |
| completed | spec | yes | no | any |
| completed | ready | yes | no | any |
| completed | active | yes | no | any |
| completed | executing | yes | no | any |

## Feature reverse-edge note

A reverse feature edge (e.g. re-opening a `completed` feature back to `executing`
for a follow-up WP) is legitimate: logged as a ledger row with its `--reason`,
never deleting prior WP evidence. `archived` remains out of scope — use
`goalforge-archive` for the terminal move.
