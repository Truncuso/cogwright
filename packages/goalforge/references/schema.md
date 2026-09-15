# Plan & Work-Package Schema (frontmatter-first)

Schema version: **3** (status-in-frontmatter; supersedes v2 which required
`status:` to agree with a lifecycle folder).

Every artifact opens with a YAML frontmatter block, then a fixed section order.
Frontmatter carries all machine-readable fields so agents and the doc
knowledge-graph tool index without parsing prose.

### Version lineage — three distinct "version" concepts, not one

This doc's own header ("Schema version: 3") predates the goal layer and refers
to the **status-in-frontmatter era** (v2 → v3). The goal layer added later (see
`## Goal object (schema v4 — the goal layer)` below) is **v4**: the `goal:`
block is optional there — a plan without it validates via the legacy `## Goal`
+ task `verify:` fallback. **v5** adds one behavior on top of v4: when a plan
opts in via the `schema_version:` marker (below), the `goal:` block becomes
**mandatory** at the WP's `ready`+ gate (`ready`/`executing`/`verified`) instead
of optional. **v6** (spec.md Interface Contract C1-C7, "the slim chain") adds
the C1 8-section WP overview shape, `verification.command` (required, ERROR
under `--strict`), the C2 field set (`register`, `human_required`,
`contract_slice`, `owned_files`), the narrowed `goal_approved_version` hash,
and retires task files/briefs/checkpoints entirely.

`schema_version:` (an optional integer WP/feature frontmatter field, e.g.
`schema_version: 6`) is a **per-plan opt-in marker** — distinct from both of
the above:

- distinct from **this doc's version** (the "Schema version: 3" header above),
  which describes schema.md's own revision, not any single plan's behavior;
- distinct from the **template marker** (`<!-- Template: <name> v4 ... -->`,
  see `## Template marker` below), which flags a stale template file, not a
  plan's semantics.

A plan with no `schema_version:` field is **legacy (≤v4)** and stays fully
exempt from the v5/v6 goal-mandatory and command-required checks — absence is
not an error, it is the default. A plan carrying `schema_version: 5` opts into
goal-mandatory-at-ready only; `schema_version: 6` (or higher) additionally
opts into the C1 overview shape and the required `verification.command`.
`goalforge-validate.sh` gates strictly on the field's presence: no marker ⇒
the checks do not run at all (see `goalforge-validate.sh`'s
goal-mandatory-at-ready check, enforced under the Goal-block integrity
invariants).

**Folder layout is flat:** `plans/<feature>/<wp-id>/files`. There are no
lifecycle buckets. Lifecycle = the `status:` frontmatter field. Changing
lifecycle = edit frontmatter in place, never move files.

---

## PLANS_ROOT resolution

All skills write and read plan artifacts under `<PLANS_ROOT>/<feature>/`.
Resolve `PLANS_ROOT` at runtime in this priority order:

1. **`SDD_PLANS_DIR` env var** — if set, use it verbatim.
2. **Project-local `plans/`** — if the session is inside a git repository
   (i.e. `git rev-parse --show-toplevel` succeeds) OR a `plans/` directory
   already exists at CWD, use `<git-toplevel>/plans/` (or `<CWD>/plans/` when
   not in a git repo but `plans/` exists there).
3. **Global fallback** — `~/.claude/plans/` (used when there is no project
   context, e.g. pure agentic-OS planning sessions).

Skills reference `<PLANS_ROOT>` as a placeholder; they never hardcode
`~/.claude/plans` as the sole location. The global fallback is explicit so
agentic-OS planning continues to work unchanged.

---

## Retry budget resolution (`SDD_MAX_RETRIES`)

The per-task evaluation retry cap (inner cap; see `goalforge-execute` Step 6 and
`## Retry cap`) is resolved at runtime from the **`SDD_MAX_RETRIES`** env var:

1. **`SDD_MAX_RETRIES` env var** — if set to a positive integer, use it verbatim.
2. **Default** — `3` attempts per task before escalation.

This is the single authoritative resolution point; skills reference
`SDD_MAX_RETRIES` (default 3) rather than hardcoding the number. It is the
**inner** cap only — independent of the goal loop's `outer_max_iter`, which is
unaffected.

The `relationships:` edge vocabulary is shared with the memory-overhaul page
schema so the same Kuzu graph indexes both memory pages and work packages.

---

## WP stage vocabulary

Every work package moves through the C2 status enum, stored as `status:` in
frontmatter:

| Stage | Meaning | Evidence required |
|---|---|---|
| `spec` | Goal + verification defined | Measurable goal written; `## Checklist` items drafted |
| `hardened` | Reviewed, open questions resolved | One harden review pass recorded; zero `open` items in `## Open Questions` |
| `ready` | Approved for exec | Human approval recorded; `depends_on` WPs are `ready`+ |
| `executing` | `goalforge-execute` running | At least one checklist item checked in `## Checklist` |
| `implemented` | Deterministic eval passed + one commit landed | Gate A evidence recorded; not yet quality-signed-off |
| `verified` | Passed verification | `goalforge-verify` gates A/B/C PASS with evidence |
| `abandoned` | Terminal — explicitly dropped | Explicit user action only; never automatic |
| `archived` | Terminal — historical record | Explicit user action only; never automatic |

Transitions are forward by default. A regression (e.g. `hardened → spec`) is
allowed and must be logged in `findings.md`. `hardened → ready` (WP gate, in
`goalforge-harden`) is human-gated by default — except that it may
**auto-advance under the signal-scoped rule** (see `state-machine.md`
§Policy); a WP with `human_required:` set is never auto-advanced regardless of
signal. `abandoned` and `archived` are terminal.

---

## Frontmatter — feature `overview.md`

```yaml
---
name: <feature>                   # kebab, matches folder name
title: <human title>
status: draft|spec|ready|active|executing|completed|archived
# draft→spec→ready→active→executing→completed  (state-machine.md §Feature policy
# is the machine-parsed source of truth — goalforge-transition.sh reads it directly)
# completed: written by goalforge-verify (last-WP rule); archived: written by goalforge-archive
# active: reserved-for-future (no skill writes it yet; sdd-lifecycle-redesign)
created: YYYY-MM-DD
feature: <feature>
# route:, confidence:, execution_plan: RETIRED (T6) — no longer stamped or
# read; old plans may still carry `route:` in frontmatter, ignored.
# ticket-62: the DISPATCH sense of "route" is now `endpoint:` and lives in
#     references/dispatch.yaml (`endpoint: session | leaf`), never in
#     frontmatter. The chain sense of `route` (fast|standard|wave) is unrelated.
#     The frontmatter key `route:` stays RETIRED under both readings.
egress: overview                  # optional; read from the feature's `spec.md`
                                  # frontmatter (mirrored here when authored on
                                  # the overview). NARROW-ONLY override of the
                                  # stage's egress class in dispatch.yaml. Enum
                                  # none < diff-only < overview < full; a value
                                  # WIDER than the stage row is ignored with a
                                  # WARN row. See "dispatch.yaml" below.
work_packages: [wp-01-x, wp-02-y]
relationships:                    # optional typed edges
  - depends_on: [[other-feature]]   # cross-feature ordering (validated: target must be ready+; recorded, NOT auto-orchestrated)
  - blocks: [[other-feature]]       # inverse of depends_on
  - supersedes: [[other-plan]]
  - related_to: [[other-plan]]
sources: [SRC-01]
---
```

`status:` is the single source of truth for feature lifecycle. It lives here
in frontmatter. No folder move is ever required or meaningful.

---

## Frontmatter — WP `overview.md`

```yaml
---
name: wp-01-<slug>                # kebab, matches WP folder name
title: <human title>
status: spec|hardened|ready|executing|implemented|verified|abandoned|archived
# `abandoned`/`archived` are terminal, reached only by an explicit out-of-band
#     edit — NO goalforge script writes either to a WP (`goalforge-archive` flips
#     FEATURE overviews only; `goalforge-transition` rejects both as an edge
#     target). Both are dep-satisfying exactly like `verified`: `goalforge-frontier.sh`
#     and `goalforge-validate.sh` treat an `abandoned`/`archived` dep as satisfied.
#     See references/state-machine.md.
# NB: there is NO `superseded` WP status — supersession is expressed by the
#     `superseded_by` relationship edge (feature-level); a superseded WP stays
#     `verified`/`archived`. Adding a WP status here would double-own the concept.
schema_version: 6                 # the C1-C7 slim shape (see "Version lineage"
                                  # above) — DISTINCT from this doc's version and
                                  # the template marker. schema_version: 6 ⇒ the
                                  # goal: block is MANDATORY at every status, the
                                  # WP overview is the C1 8-section shape, and
                                  # `verification.command` is required (ERROR
                                  # under --strict). schema_version: 5 (or absent)
                                  # plans stay read-only compatible (WARN only).
stage_updated: YYYY-MM-DD
severity: HIGH|MEDIUM|LOW
task_type: code|docs|research|ops
register: spike|production        # required. `prototype` normalizes to `spike`
                                  # on READ only — never written. spike ⇒
                                  # declared (CLAUDE.md Principle 2, declared in
                                  # the WP — never post-hoc): the WP answers ONE
                                  # design question; goal strategy judge|human,
                                  # never deterministic-on-spike-code.
                                  # NB: register is NOT covered by the goal hash —
                                  # flipping it after goal_approved_version is set
                                  # changes execution semantics silently; treat a
                                  # register change as a goal change: re-run goalforge-harden.
                                  # Mechanically gated by goalforge-validate.sh check_register
                                  # (ERROR under --strict): enum ∈ {spike,production}.
depends_on: [wp-00-x]            # slug list; validator resolves them
owned_files: [packages/a/, packages/b/file.py]  # the WP's file boundary; diff
                                  # paths at verify gate A must be a subset
parallel: false                   # may a sibling WP run concurrently?
contract_slice: [C1, C3]          # spec.md `## Interface Contract` subsection
                                  # ids this WP depends on — see "Contract-slice
                                  # hash (per-WP)" below
human_required: null              # null, or "<reason>" naming why a human must
                                  # gate this WP (irreversible action, HIGH
                                  # severity + production, or any WP author
                                  # judgment call) — see spec.md Interface
                                  # Contract §C7. A set human_required: is never
                                  # auto-advanced by the signal-scoped rule.
plan: <feature>                   # parent feature slug
tags: [tag1, tag2]
relationships:
  - depends_on: [[wp-00-x]]
  - blocks: [[wp-03-y]]
  - related_to: [[wp-02-z]]
sources: [SRC-01]
goal_approved_version: null       # sha256[:12] of goal.outcome + goal.verification
                                  # only (NOT constraints/boundaries/iteration_policy/
                                  # blocked_stop); set at harden gate; null until
                                  # first approval
---
```

`status:` is the **single source of truth** for WP stage. The feature
`overview.md` WP table is *derived* from WP frontmatter by script, never
edited by hand.

---

## Risks block + `[risk-accepted]` marker (WP `overview.md` body)

A question may stay open past the `ready` gate **only** as an accepted,
recorded risk. Two coupled pieces, both in the WP `overview.md` body:

1. A `## Risks` section — one entry per accepted risk:

   ```
   ## Risks

   - id: <stable-kebab-id>        # the risk-accepted marker references this
     risk: <one-line statement of what could go wrong>
     impact: <HIGH|MEDIUM|LOW>
     likelihood: <HIGH|MEDIUM|LOW>
     owner: <who revisits — human:<name> | session | feature-owner>
     revisit: <trigger — a date, an event, or "at goalforge-verify">
   ```

2. The open-question bullet marked `[risk-accepted: <id>]`, where `<id>`
   resolves to a `## Risks` entry **in the same file**.

`goalforge-open-questions-gate.sh` counts a `[risk-accepted: <id>]` bullet as
resolved **iff** the id resolves; a dangling id counts as unresolved (the
marker is the link, the Risks row is the record). `[deferred]` stays for
genuinely-later questions that carry no risk decision; `[assumption]` stays
for assumed answers. Do not use `[risk-accepted]` without the id payload.

**`answered_by: agent` (C7).** An unattended harden may resolve an open
question via an agent respondent instead of a human: the bullet carries
`[answered: <resolution>] (answered_by: agent)`. A question the agent cannot
resolve with confidence is **parked**, not guessed — it stays `open` and
surfaces at the next human touchpoint. Goal facets (`outcome`,
`verification`, and any question that would change either) are **never**
agent-answered — only a human may resolve those.

---

## No task files (C1)

A schema-6 WP carries no `task-NN-*.md` files and no `brief-*.md` files. Work
items live as checklist lines in the WP overview's `## Checklist` section:

```
- [ ] T1 <imperative outcome> {files: a, b} [b1,b2]
```

`{files: ...}` names the item's file boundary (a subset of the WP's
`owned_files:`); `[b1,b2]` names the `goal.verification.behaviors[]` ids the
item satisfies. There is no per-task `status:`, `complexity:`, `checkpoint:`,
`commit:`, or `commit_exempt:` field — a WP ships as **one conventional commit**
(C5), and `implemented`/`verified` are WP-level `status:` values, not
per-checklist-item state.

---

## Relationship edge vocabulary (shared with memory-overhaul)

| Edge | Meaning |
|---|---|
| `depends_on` | This WP/task cannot start until the target is `ready`+ — a WP dep at `archived` also satisfies (it is off the linear `ready`+ chain; see the WP status note above) |
| `blocks` | Inverse of `depends_on` |
| `related_to` | Non-blocking association |
| `supersedes` | This WP replaces the target |
| `superseded_by` | Inverse of supersedes — this plan was replaced by the target |
| `optional_depends_on` | Non-gating soft link to a target that must exist — validator WARNs (never ERRORs) on a missing target; NEVER gates frontier/harden/execute regardless of the target's status |

Edge targets use `[[wikilink]]` form (the target's `name:` slug) so the Kuzu
graph and any Obsidian-style viewer resolve them. `optional_depends_on` may
also be written as a top-level `optional_depends_on: [slug, ...]` shorthand
field (see `evals/schema-v5/fixtures/e-v5-complete-goal-present-dep/` for a live example).

<!-- DEFERRED (not implemented here): a verified optional_depends_on target
     could surface a propose-only PROPOSAL-row suggesting downstream respec
     to the depending WP/task. The future consuming surface is plan-index /
     frontier (see spec.md Interface Contract §7 and §9a's data-contract
     event log) — not this schema, not this validator. Promotable later as
     its own idea; no owning WP exists for it yet. -->

---

## Integrity invariants (enforced by `goalforge-validate.sh`)

- `implemented`/`verified` ⇒ exactly one WP commit is linked (C5: one
  conventional commit per WP; no per-task commits).
- `verified` ⇒ gates A, B, C each have a recorded `gate.result` PASS
  (`trace-events.jsonl`) and `findings.md` exists.
- `depends_on: [x]` ⇒ `x` exists and is `ready`+ (or `verified`/`abandoned`/`archived`).
- `owned_files:` non-empty on a schema-6 WP; the verify-gate-A diff must be a
  subset of it.
- Validator suggests fixes; it **never auto-rewrites** frontmatter.

---

## Template marker

Every template's first body line after frontmatter is:

```
<!-- Template: <name> v4 (frontmatter-first, flat layout) -->
```

so a stale template (missing the marker or wrong version) is detectable by
`goalforge-validate.sh`. The marker check is **additive**: v4 is current, but v3 is
still accepted, so legacy plans never go stale on a marker bump alone.

---

## Transition ledger — `<feature>/.sdd-transitions.jsonl`

Append-only, git-tracked, one JSON row per WP status transition. **Single
writer:** `goalforge-transition.sh` (never hand-edit). Each row:

```jsonc
{ "ts": "<ISO-8601 Z>", "wp": "<wp-slug>", "from": "<status>", "to": "<status>",
  "reason": "<short why — the decision rationale>", "override": <bool>,
  "commit": "<short sha>",
  // ── attribution stamp (auto-filled by goalforge-attribution.sh; degrade → "unknown") ──
  "mode": "human" | "auto",          // human-gated edge vs autonomous engine
  "actor": "human:<git user.name>" | "<skill|auto>",
  "session": "<CLAUDE_CODE_SESSION_ID>",
  "model": "<opus|sonnet|deepseek-v4-pro|…>",
  "provider": "<anthropic|deepseek|ollama|…>",
  "agent": "<dispatched-subagent id | ''>",   // optional; '' in single-context runs
  "decision_ref": "<ADR-NNNN | findings.md#anchor | ''>" }  // pointer, not a copy
```

The stamp answers *who/what* resolved a transition or answered question — the
autonomous-run counterpart to a human approver. Alternatives/why are
**referenced** (`decision_ref` → ADR `Considered Options` / `findings.md`),
never duplicated into the row. Readers/validators **tolerate older rows** that
predate the stamp (additive fields; missing = un-stamped, not invalid).

---

## Goal object (schema v4 — the goal layer)

A **goal** is a frontmatter block carrying Codex's 6-part anatomy. It lives at
two altitudes: the **feature spec** (parent goal) and each **WP** (sub-goal).
The block is **optional** — a plan without it validates and falls back to the
legacy `## Goal` + task `verify:` representation (treated as
`strategy: deterministic`). When present, `goalforge-validate.sh` integrity-checks it.

### The block (both altitudes)

```yaml
task_type: code | docs | research | ops
goal:
  outcome: "<what is true when done — one measurable sentence>"
  verification:                 # the Verification Surface (router input)
    strategy: deterministic | judge | human
    command: "<the exact reproducible command — command-only, no prose>"
    check: "<schema-5 alias of command — WARN-only baseline compat>"
    behaviors:                  # optional; the b1..bN oracle rows checklist
      - id: b1                  #   items reference in their `[b1,b2]` tags
        given: "<precondition>"
        when: "<action>"
        then: "<expected result>"
        oracle: "<the deterministic check that proves it>"
  constraints: ["<what must not regress>", ...]
  boundaries: ["<allowed files/tools/resources>", ...]
  iteration_policy: "<how to choose the next action after each attempt>"
  blocked_stop: "<when to halt and report paths exhausted>"
```

The **WP** block additionally carries:

```yaml
inherits_from: <feature-slug | null>    # cascade source; WP-only (a feature spec has no parent)
```

### Per-strategy `verification.command` shapes

| `strategy` | `command` shape | How completion is decided |
|---|---|---|
| `deterministic` | string command, e.g. `"pytest tests/auth -q"` — command-only, no prose | exit 0 = met |
| `judge` | string command that runs a judge pass, e.g. `"bash evals/judge.sh <wp>"` | judge verdict; met iff no finding at/above a `block_on` severity named in the command's own rubric |
| `human` | string gate prompt | NON-BLOCKING in an autonomous loop (pause → write findings → exit → resume next run) |

Schema-6 WPs require `verification.command` (ERROR under `goalforge-validate.sh
--strict`); schema-5 WPs are read-only compatible via the legacy `check:` alias
(WARN only, never promoted to ERROR).

### One source of truth

The `goal:` frontmatter is authoritative. `goal.outcome` **supersedes** the body
`## Goal` section and `goal.verification` **supersedes** `## Verification`; those
sections become a rendered prose mirror (or are dropped). There is no third
representation.

### Checklist-item level (no per-item strategy)

A `## Checklist` item does **not** carry a strategy. Its `{files: ...}` +
`[b1,b2]` tags declare a file boundary and the `goal.verification.behaviors[]`
ids it satisfies — evidence that the item is done, not an independent
completion gate. The strategy router (`deterministic | judge | human`)
operates **only at the WP-goal altitude**: the WP `goal.verification` is the
**authoritative completion unit** — the single gate (verify gate A) that
decides whether the WP is done.

> **Facet-coverage self-check.** Every facet of `goal.outcome` MUST be covered
> by `goal.verification` (directly, or via its `behaviors[]`). A checklist item
> may prove only a slice; the WP gate must not leave any outcome facet
> unverified.

### Cascade rule (standalone-but-feature-aware), per-field semantics

Applies only when a WP sets `inherits_from: <feature-slug>` and that spec exists.

| Field | Cascade semantics |
|---|---|
| `outcome` | **Never inherited** — every goal declares its own (empty WP `outcome` is invalid). |
| `verification` | **Never inherited** — every goal declares its own. |
| `iteration_policy` (scalar) | WP value **overrides** spec; if unset on the WP, inherit the spec's. |
| `blocked_stop` (scalar) | WP value **overrides** spec; if unset on the WP, inherit the spec's. |
| `constraints` (list) | **Union with dedupe** (WP ∪ spec) — a WP never silently drops an inherited constraint. |
| `boundaries` (list) | **Union with dedupe** (WP ∪ spec). |

A WP with a complete goal block (no `inherits_from`, or all fields set) runs
solo. `task_type` and `strategy` are **orthogonal**: any `task_type` may use any
`strategy`; the code path is "the deterministic strategy."

### Goal-block integrity invariants (enforced by `goalforge-validate.sh`)

When a `goal:` block is present:

- `goal.outcome` is present and non-empty (WP and feature).
- `goal.verification.strategy` ∈ `{deterministic, judge, human}`.
- `verification.command` is a non-empty, command-shaped string (no prose) —
  **ERROR** under `--strict` on a schema-6 WP; **WARN** on a schema-5 WP whose
  legacy `check:` alias is present instead.
- `task_type`, when present, ∈ the `task_type` enum.
- `inherits_from`, when set on a WP, resolves to an existing feature spec slug.

A malformed goal block is a **fatal** schema violation — the validator exits
non-zero regardless of `--strict` (distinct from advisory status-drift errors).

### Goal-mandatory-at-ready (schema v5/v6, `schema_version:` marker)

When a WP's frontmatter carries `schema_version: 5` (or higher) **and** its
`status` is `ready`, `executing`, `implemented`, or `verified`, the `goal:`
block is no longer optional — a missing `goal:` is a **fatal** schema
violation (same severity as a malformed block; non-zero exit regardless of
`--strict`). Absent the marker, behavior is unchanged from v4 (goal block
optional, legacy fallback applies). `schema_version: 6` additionally requires
`verification.command` (see above) and the C1 8-section overview shape. This
check is gated strictly on the marker's presence — it never fires on a plan
that does not carry `schema_version:`.

### goal_approved_version

`goal_approved_version` is the **sha256 hash (first 12 hex chars)** of
`goal.outcome` + `goal.verification` **only** — trailing-whitespace-stripped,
LF-normalized. It deliberately excludes `constraints`, `boundaries`,
`iteration_policy`, and `blocked_stop`: an edit to those facets (or to any
other prose in the WP, e.g. `## Decisions`) does not change the hash and does
not require re-approval. It is **null/absent** until the first harden gate;
set by `goalforge-harden` at the `hardened → ready` approval.

### Goal Changelog (evolved-goal audit trail)

The `## Goal Changelog` section in each WP `overview.md` is **append-only**.
Row schema:

```
- v<N> <date> facet=<facet> <old>→<new>; reason: <text>
```

`facet` ∈ `outcome | verification | constraints | boundaries | iteration_policy | blocked_stop`.

**Hash-mismatch rule:** after a WP reaches `status: ready`, the evolved-goal gate
recomputes the goal-block hash and compares it against `goal_approved_version`. If
they differ, the WP is flagged — the goal changed post-approval and must go through
the harden gate again before execution resumes. The check is a **hash-mismatch
comparison** (recomputed hash ≠ `goal_approved_version`), not a date comparison.

---

## Contract-slice hash (per-WP)

Each WP's `contract_slice:` frontmatter list (e.g. `[C1, C3]`) names the
spec.md `## Interface Contract` subsections (`### C1`, `### C2`, ...) the WP
depends on. `goalforge/scripts/goalforge-feature-hash.sh <wp-dir>` hashes
exactly those named subsection bodies plus the sorted slice-id list itself
(sha256[:12], single source of the hash; never hand-computed). A WP's contract
dependency changes iff this hash changes — a sibling WP's unrelated goal edit,
or a spec edit outside the WP's named slices, never trips it.

---

## Prototype retention

The prototype layer materializes scratch/spike work under a single top-level
`prototype/` tree, with per-prototype git treatment driven by a **retention
tier**. `goalforge/scripts/goalforge-prototype-retain.sh <feature-slug>
<prototype-slug> <discard|keep|share>` owns folder creation and the
`prototype/.gitignore` line management (single source of the contract); it emits
JSON `{"path":"prototype/<feature>/<slug>/","tier":"...","gitignore_updated":true|false}`
and is idempotent + zero-breakage.

**Root path.** Each prototype lives at `prototype/<feature-slug>/<prototype-slug>/`,
relative to the invoking repo's worktree root.

**`prototype/.gitignore` behavior.** The file defaults to two lines — `*`
(ignore everything under `prototype/`) and `!.gitignore` (keep the ignore file
itself tracked). The `share` tier additionally **appends** the un-ignore lines
`!<feature>/`, `!<feature>/<slug>/`, `!<feature>/<slug>/**`. Lines are appended
only when absent (never rewritten), so an existing tree is never corrupted. The
parent-first order matters: git cannot re-include a child until its parent
directory is re-included, and `*` (no slash) matches at every depth — so all
three lines are required.

**Tiers (git semantics).**

| Tier | Git treatment | Intent |
|---|---|---|
| `discard` | folder stays ignored (default `*`) | scratch; never committed |
| `keep` | git-identical to `discard` — ignored in place | retained locally; the tier string is the only difference from `discard` |
| `share` | folder un-ignored via the three `!` lines → committable | promoted; the prototype ships in the repo |

**Share is sticky — tier transitions are monotonic w.r.t. `share`.** The
un-ignore lines are append-only: once `share` has written `!<feature>/`,
`!<feature>/<slug>/`, and `!<feature>/<slug>/**`, a subsequent `discard` or
`keep` run does **not** remove them, so the JSON `tier` string can diverge from
the actual git behavior (the folder stays committable). Walking a prototype back
from `share` requires manually deleting the `!<feature>/<slug>/`* lines from
`prototype/.gitignore`.

**Tolerable-error exit emits no stdout.** On a tolerable error (missing or
invalid argument, or a slug that fails validation) the script writes a note to
stderr and exits 0 **without emitting any stdout JSON**. Callers must treat
empty stdout as "no-op — see the stderr note", not as success.

**Findings-doc frontmatter additions.** A prototype's findings doc
(`plans/<feature>/<wp>/{LOGIC|UI|PERF}.md`) gains two frontmatter fields:

- `prototype_path: prototype/<feature-slug>/<prototype-slug>/` — the retained
  folder (mirrors the retain script's JSON `path`).
- `retention: discard | keep | share` — the tier applied (mirrors JSON `tier`).

**`## Run Log` body convention.** The findings doc body carries a `## Run Log`
section: an append-only table with **one row per run**, recording the date, what
changed that run, and what was learned.

```
## Run Log

| Date | Changed | Learned |
|---|---|---|
| 2026-07-24 | initial logic-branch spike | un-ignore order must be parent-first |
```

---

## Re-harden evidence

An evidence-gated re-harden re-opens a `ready` WP back to `hardened` so its goals
can be re-developed (see `state-machine.md` §Policy — Evidence-gated revert
exception). The trigger is a **typed evidence file** committed under a
`reharden/` subfolder of the WP.

**Layout.** The flat WP folder (`plans/<feature>/<wp-id>/`) gains one subfolder:

```
plans/<feature>/<wp-id>/reharden/<YYYY-MM-DD>-<slug>.md
```

One file per re-harden proposal; the date-prefixed slug keeps successive
proposals ordered and non-colliding. The subfolder is committed with the WP —
it is the durable audit trail for why goals were revised, indexed by
validators/authors alongside the WP's own artifacts.

**Evidence-file shape.** Frontmatter (template:
`references/templates/reharden-evidence.md`):

| Field | Type | Required | Semantics |
|---|---|---|---|
| `kind` | enum | yes | `prototype-findings` \| `execution-learning` \| `issue` — what class of evidence triggered the re-harden. |
| `locator` | string (path-or-url) | yes | Where the evidence lives (findings doc, PR, issue, trace row). Pointer, not a copy. |
| `summary` | string | yes | One-line statement of what the evidence shows. |

**Consumed by the transition mechanism.** The revert is written with the
evidence gate — `goalforge-transition.sh <wp> hardened --mode evidence
--evidence <path>` — which validates the file exists and carries the frontmatter
above; a bare-`--reason` revert on the `ready→hardened` edge is refused. The
transition emits `reharden.proposed` / `reharden.accepted` trace events whose
payloads mirror `kind`/`locator`/`summary` plus the evidence path (see
`references/trace-events.md`). The reverse `hardened→ready` re-promotion keeps
its human gate unchanged.

---

## dispatch.yaml (per-stage dispatch config)

`references/dispatch.yaml` is the configured source for model, effort,
provider, endpoint, and egress class per dispatch stage. Every consumer
(`goalforge-pick-agent.py`, `goalforge-rollup.sh`, `goalforge-workflow-compile.py`,
`goalforge-second-opinion.sh`, `goalforge-harden-stop.sh`) reads it through a
`--dispatch <path>` flag defaulting to this package file. No provider name
appears in any `SKILL.md`; provider names are data in this file only.

### Top level

| Key | Type | Required | Semantics |
|---|---|---|---|
| `schema_version` | integer | yes | This file's shape. Currently `1`. |
| `providers` | list | yes | Preference order, first entry = default. No budget accounting: preference order alone decides fall-through. |
| `stages` | map | yes | One row per dispatch stage; keys equal the `ROLE_TIER` keys in `scripts/goalforge-pick-agent.py` — `implement`, `discovery`, `feature-audit`, `harden-review`, `wp-verify`, `simplify`, `judge`, `panel`, `integration-review`, `second_opinion`. |
| `rollup.token_warn` | integer | yes | Per-dispatch soft token threshold; `goalforge-rollup.sh` writes a WARN line above it and does not change its exit code. Shipped value `250000`. |
| `harden.token_ceiling` | integer \| null | yes | `null` ⇒ tokens are a **soft sensor**: above the threshold `goalforge-harden-stop.sh` writes a `harden.warn` row and exits 0, the round cap staying the only default hard park (C4). An integer ⇒ a **hard ceiling**: park above it, the same meaning `SDD_HARDEN_TOKEN_CEILING` carries when set. Shipped value `null`. |
| `second_opinion.max_payload_bytes` | integer | no | Cap on the payload `goalforge-second-opinion.sh` hands the leaf as a `--prompt` **argv value**. Optional: absent means the loader default `102400`, which is also the shipped value and the reviewed **maximum** — a larger configured value is CLAMPED to it with a WARN, and a non-integer or non-positive value falls back to the default with a WARN (never silently). The ceiling exists because the payload is ONE argv string: `MAX_ARG_STRLEN` is `PAGESIZE * 32` = 131072 on a 4 KiB-page host (measured: 131000 bytes exec'd, 131100 exited 126), and the leaf re-passes the same value through `_core/intent_gate.sh` and `claude -p`. `--prompt` is used rather than `--prompt-file` because of what the CONFIGURED provider's leaf does with that flag (verified 2026-09-13 by reading the leaves): the ollama, zai and deepseek leaves route it through `_core/prompt_file.py`, a *structured handoff-brief* parser (base-dir allowlist, frontmatter contract, exit 2/3) that kills a raw payload file with leaf-exit-3, while the codex leaf reads it raw and would accept one — so this is a property of the configured row, not of leaf-interface v1. Above the cap the DIFF section is truncated head-first, marked in the payload, and named in the reason (`; diff-truncated N/M`); a payload still over the cap with the diff gone calls no leaf at all and emits `second_opinion.skipped` with reason `payload-oversize <actual>/<cap>`, exit 0. |

### `providers[]`

| Key | Type | Required | Semantics |
|---|---|---|---|
| `name` | string | yes | Provider id referenced by a stage row's `provider`. |
| `kind` | enum | yes | `native` \| `foreign` \| `local`. `native` runs in-session (Agent/Workflow tool); the others run through an agent-dispatch leaf. DERIVED, not trusted: `native` carrying a `leaf` — or reached through a stage row whose `endpoint` is not `session` or `egress` not `none` — is refused at exit 2, as is a duplicate `name`. |
| `leaf` | path \| null | yes | The `headless_dispatch` leaf (leaf-interface.md v1), written relative to `${CLAUDE_CONFIG_DIR:-$HOME/.claude}` — never an absolute home path. `null` for `kind: native`. An admission row binds this path AND its sha256, so repointing it under an admitted provider name inherits no admission. |
| `max_budget_usd` | float | no | Passed to the leaf as `--max-budget-usd`. Leaf default `0.10`. Omitted for `native`. |
| `propose_only` | bool | no | Informative echo of the **default verdict** when no admission row admits this provider for the WP's task class: the admission table decides the resolver verdict for role `implement` (`references/admission.md`, `references/admitted-providers.yaml`, shipped empty). A resolution left at that default produces a proposal row in the ledger and in `findings.md`, never a gate decision; compile-level dispatch of a non-native `implement` row stays refused until `wp-08-admitted-execution`. This key is an echo, never the gate: a row setting it `false` is still refused unless a table row binds its task class, model and leaf. |

### `stages.<stage>`

| Key | Type | Required | Semantics |
|---|---|---|---|
| `model` | enum \| string | yes | On a row whose provider `kind` is `native`: `sonnet` \| `opus` \| `fable` \| `haiku` \| `by_register` — `by_register` only legal on `implement`, resolved from the WP's `register`/`severity` by the pick-agent register logic. On a row whose provider `kind` is NOT `native`, it is that provider's own model id (e.g. `glm-5.3:cloud` on the ollama leaf); a Claude tier there makes the leaf exit 2 and the leg is silently skipped. |
| `effort` | enum | yes | `low` \| `medium` \| `high` \| `xhigh` \| `max` \| `by_register`. |
| `provider` | string | yes | First-choice `providers[].name`; fall-through continues down `providers` **from that entry onward**. |
| `endpoint` | enum | yes | `session` \| `leaf`. The dispatch sense formerly spelled `route` (ticket-62). `kind: native` ⇒ `session`; a leaf provider ⇒ `leaf`. |
| `egress` | enum | yes | `none` \| `diff-only` \| `overview` \| `full` — what may leave to that endpoint. |

Model/effort mirror the `semi-autonomous` `ROLE_TIER` projection
(`references/tier-map.md`) except `judge` and `wp-verify`, re-banded to
`opus`/`high` on every profile by ticket-48 (a grader must differ from the
implementer in persona AND in model or effort). `goalforge-pick-agent.py
--test-tiers` enforces that projection on every other row, comparing `model`
and `effort` on native rows and `effort` alone on a non-native row (whose
`model` is a provider id); the `by_register` sentinel is exempt.

### Egress classes (ticket-45)

Ordered, narrowest first: `none` < `diff-only` < `overview` < `full`.

| Class | Payload |
|---|---|
| `none` | Nothing leaves; the call is skipped with reason `egress-none`. |
| `diff-only` | The diff. |
| `overview` | The diff + the WP `overview.md`. **Shipped default on every row whose provider `kind != native`.** |
| `full` | The diff + `overview.md` + `spec.md` + `findings.md`. In the enum, used by no shipped row; enabled only by a reviewed config edit. |

`none` is legal on any row. **No content is redacted in any class** (operator's
explicit choice). A feature `spec.md` frontmatter `egress:` may only **narrow**
the stage row: a value at or below the row's class is applied; a **wider** value
is ignored with a WARN row and the stage row's class stands.

### Provider fall-through (leaf exit codes, leaf-interface.md §5/§6)

Resolved at dispatch time against the leaf's exit code:

| Leaf exit | Reason | Effect |
|---|---|---|
| `1` | backend unreachable | fall through to the next configured provider |
| `2` | model not found | fall through to the next configured provider |
| `4` | `plan_quota_exhausted` \| `metered_rate_limited` | no inner envelope, the turn was refused → fall through |
| `4` | `budget_exceeded` \| `budget_check_failed` | **not** a fall-through: the turn completed, the result is **kept**, and a WARN row names the overspend |
| `0` | — | result kept |

When the ordered list is exhausted with no result, `EscalationRequired` is
raised (exit 1, `ESCALATION REQUIRED: …` on stderr) — never a silent fallback.
