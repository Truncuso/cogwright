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
of optional.

`schema_version:` (an optional integer WP/feature frontmatter field, e.g.
`schema_version: 5`) is a **per-plan opt-in marker** — distinct from both of
the above:

- distinct from **this doc's version** (the "Schema version: 3" header above),
  which describes schema.md's own revision, not any single plan's behavior;
- distinct from the **template marker** (`<!-- Template: <name> v4 ... -->`,
  see `## Template marker` below), which flags a stale template file, not a
  plan's semantics.

A plan with no `schema_version:` field is **legacy (≤v4)** and stays fully
exempt from the v5 goal-mandatory check — absence is not an error, it is the
default. Only a plan that explicitly carries `schema_version: 5` (or higher)
opts into goal-mandatory-at-ready. `sdd-validate.sh` gates strictly on the
field's presence: no marker ⇒ the check does not run at all (see
`sdd-validate.sh`'s goal-mandatory-at-ready check, enforced under the
Goal-block integrity invariants).

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

The per-task evaluation retry cap (inner cap; see `sdd-execute` Step 6 and
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

Every work package moves through six stages, stored as `status:` in frontmatter:

| Stage | Meaning | Evidence required |
|---|---|---|
| `draft` | Rough capture — problem stated, target files guessed | WP exists; problem statement non-empty |
| `spec` | Goal + verification defined | Measurable goal written; verification rows drafted |
| `hardened` | Grilled, open questions resolved | `interview-loop` run; zero `open` items in OPEN_QUESTIONS |
| `ready` | Approved for exec | Human approval recorded; `depends_on` WPs are `ready`+ |
| `executing` | `sdd-execute` running | ≥1 task has a `checkpoint` block |
| `verified` | Passed verification | `sdd-verify` PASS with evidence; review + simplify clean |
| `archived` | Terminal — historical record | Explicit user action only; never automatic |

Transitions are forward by default. A regression (e.g. `hardened → spec`) is
allowed and must be logged in `findings.md`. `draft → ready` (feature gate, in
`sdd-spec`) and `hardened → ready` (WP gate, in `sdd-harden`) are the two
human-gated transitions — except that `hardened → ready` may **auto-advance
under the signal-scoped rule** (complexity verdict `simple`, severity ≤ MEDIUM,
`task_type ≠ migration`; ledger row records `mode: auto` + the signal evidence
— see `state-machine.md` §Policy). `archived` is terminal.

---

## Frontmatter — feature `overview.md`

```yaml
---
name: <feature>                   # kebab, matches folder name
title: <human title>
status: draft|ready|active|completed|archived
# draft→ready→active→completed→archived
# completed: written by sdd-verify (last-WP rule); archived: written by sdd-archive
# active: reserved-for-future (no skill writes it yet; sdd-lifecycle-redesign)
created: YYYY-MM-DD
feature: <feature>
route: standard                   # one-go|fast|standard|wave — chain route,
                                  # stamped by sdd-capture (sdd-goal-route.sh
                                  # verdict). Back-compat: fast|full still
                                  # accepted on read; full normalizes to
                                  # standard. Absent ⇒ standard (back-compat).
# confidence: clear|borderline|pinned  # classifier confidence for the route
                                  # verdict (optional; sdd-goal-route.sh output
                                  # field, not gating). pinned = human override.
# execution_plan:                 # optional; stamped by sdd-capture alongside
                                  # route. Shape (see spec.md Interface Contract
                                  # §2):
#   steps: [spec, decompose, harden, execute, verify]  # subset per route
#   dispatch: {spec: agent, decompose: agent, hygiene: agent}  # inline|agent per step
#   parallel: [[spec], [decompose, hygiene]]           # groups run concurrently
#   tiers: {explore: sonnet, spec_author: opus, judge: opus, boilerplate: haiku}
# Absent execution_plan: block ⇒ standard route, all-inline (legacy behavior).
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

## Route enum + execution_plan block

`route:` classifies how much of the chain a feature needs. Four values:

| Route | Meaning |
|---|---|
| `one-go` | Smallest unit — reuses fast-path 1-WP mechanics with a single dispatch (full goal-contract + deterministic gates preserved). |
| `fast` | capture → single WP → execute/verify, no `spec.md`. |
| `standard` | Full chain: spec → decompose → harden → execute → verify. Default. |
| `wave` | Multi-WP with parallel fan-out (explore, parallel spec authors, cross-spec judge, hygiene). |

Back-compat: `fast`/`full` are still accepted on read; `full` normalizes to
`standard`. Absent `route:` ⇒ `standard` (legacy behavior).

Classifier confidence (optional `confidence:` field, output of
`sdd-goal-route.sh`, never gating): `clear` (unambiguous signals), `borderline`
(mixed signals, verdict is a best guess), `pinned` (human override — the
verdict was set explicitly, not classified).

`execution_plan:` is an optional frontmatter block stamped by `sdd-capture`
alongside `route:` — persisted DATA, inspectable and human-overridable at the
spec gate, consumed (never re-classified) by the runner:

```yaml
route: standard            # one-go | fast | standard | wave
execution_plan:
  steps: [spec, decompose, harden, execute, verify]   # subset per route
  dispatch:                # inline | agent, per step
    spec: agent
    decompose: agent
    hygiene: agent
  parallel: [[spec], [decompose, hygiene]]            # groups run concurrently
  tiers: {explore: sonnet, spec_author: opus, judge: opus, boilerplate: haiku}
```

**Fallback rule:** an absent `execution_plan:` block means `standard` route,
all-inline (legacy behavior) — no step is dispatched to an agent unless the
block says so.

---

## Frontmatter — WP `overview.md`

```yaml
---
name: wp-01-<slug>                # kebab, matches WP folder name
title: <human title>
status: draft|spec|hardened|ready|executing|verified|archived
# archived is reserved-for-future (sdd-lifecycle-redesign)
# NB: there is NO `superseded` WP status — supersession is expressed by the
#     `superseded_by` relationship edge (feature-level); a superseded WP stays
#     `verified`/`archived`. Adding a WP status here would double-own the concept.
schema_version: 5                 # optional per-plan opt-in marker (see "Version
                                  # lineage" above) — DISTINCT from this doc's
                                  # version and the template marker. Absent
                                  # (legacy ≤v4) ⇒ goal: block stays optional.
                                  # Present + >=5 ⇒ goal: is MANDATORY at
                                  # ready/executing/verified (fatal if missing).
stage_updated: YYYY-MM-DD
severity: HIGH|MEDIUM|LOW
register: production|prototype    # optional; default production. prototype ⇒
                                  # declared spike (CLAUDE.md Principle 2, declared
                                  # in the WP — never post-hoc): the WP answers ONE
                                  # design question via the `prototype` skill; its
                                  # deliverable is the findings doc (LOGIC.md /
                                  # UI.md / PERF.md), which is what gets committed —
                                  # spike code lives in a worktree and never lands.
                                  # Goal strategy: judge|human (the findings answer
                                  # the question), never deterministic-on-spike-code.
                                  # NB: register is NOT covered by the goal hash —
                                  # flipping it after goal_approved_version is set
                                  # changes execution semantics silently; treat a
                                  # register change as a goal change: re-run sdd-harden.
                                  # Mechanically gated by sdd-validate.sh check_register
                                  # (ERROR under --strict): enum ∈ {production,prototype};
                                  # prototype ⇒ strategy judge|human (any status) and
                                  # exactly one task-*.md (ready+ only).
parallel: false                   # may a sibling WP run concurrently?
depends_on: [wp-00-x]            # slug list; validator resolves them
plan: <feature>                   # parent feature slug
tags: [tag1, tag2]
relationships:
  - depends_on: [[wp-00-x]]
  - blocks: [[wp-03-y]]
  - related_to: [[wp-02-z]]
sources: [SRC-01]
goal_approved_version: null           # sha256[:12] of the goal block; set at harden gate; null until first approval
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
     revisit: <trigger — a date, an event, or "at sdd-verify">
   ```

2. The open-question bullet marked `[risk-accepted: <id>]`, where `<id>`
   resolves to a `## Risks` entry **in the same file**.

`sdd-open-questions-gate.sh` counts a `[risk-accepted: <id>]` bullet as
resolved **iff** the id resolves; a dangling id counts as unresolved (the
marker is the link, the Risks row is the record). `[deferred]` stays for
genuinely-later questions that carry no risk decision; `[assumption]` stays
for assumed answers. Do not use `[risk-accepted]` without the id payload.

---

## Frontmatter — `task-NN-*.md`

```yaml
---
name: task-01-<slug>
title: <one-line goal>
status: pending|in-progress|implemented|verified
# implemented = deterministic eval passed + committed (interim, by sdd-execute);
#               NOT quality-signed-off. verified is written only at the WP gate by
#               sdd-verify (it promotes implemented → verified).
complexity: low|medium|high       # drives model tier; discovery agent estimates if absent
route: api|ollama                 # default: api
parallel: false                   # safe to run concurrently with sibling tasks?
depends_on: []                    # task slugs within the same WP
verify: "<exact cmd or check that proves the task done>"
# expects_absent: [<repo-relative path>, ...]   # optional; deletion tasks only.
#   Paths this task's verify: legitimately asserts ABSENT. sdd-validate.sh verify-lint
#   INVERTS the existence check for a listed token: it EXISTS → ERROR (deletion
#   regressed), it is MISSING → pass. Tokens not listed keep the default check.
#   Applies to the NON-negated verify form (e.g. `test -f <p>`); a negated form
#   (`! test -f <p>`) is already skipped by verify-lint, so expects_absent is moot there.
# commit: <sha>                   # optional; BACKFILLED by sdd-verify at WP finalize
#                                 # from checkpoint.commit_sha (not written per-task
#                                 # during execution). required for status: verified
#                                 # under --require-commit validation.
---
```

The `checkpoint:` block is written by `sdd-execute` into the task **body** (not
the frontmatter) as a `## Checkpoint (sdd-execute state)` section. The validator
enforces the `executing` evidence invariant by scanning for `^checkpoint:` in the
body, so a checkpoint placed inside the frontmatter is invisible to it. Shape:

```markdown
## Checkpoint (sdd-execute state)

checkpoint:
  last_step: 0
  specialist: ""
  model: ""
  route: api
  worktree: ""
  discovered_by: ""             # manual|map|discovery-agent
  commit_sha: ""                # full sha of this task's commit; stashed at Step 8,
                                # batch-backfilled into frontmatter commit: by sdd-verify
  resumable: true
```

`complexity` drives the model tier; the tier is instantiated to an explicit
`{model, effort}` by `TIER_DISPATCH`/`tier_to_dispatch` in
`sdd/scripts/sdd-pick-agent.py` — do not restate the values here (they drift).
`discovered_by` records how the specialist was resolved (see §5 of spec.md for
the dispatch algorithm).

---

## Relationship edge vocabulary (shared with memory-overhaul)

| Edge | Meaning |
|---|---|
| `depends_on` | This WP/task cannot start until the target is `ready`+ |
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

## Integrity invariants (enforced by `sdd-validate.sh`)

- `verified` ⇒ all child tasks `verified` + `findings.md` exists.
- `executing` ⇒ ≥1 task has a `checkpoint` block.
- `depends_on: [x]` ⇒ `x` exists and is `ready`+.
- Validator suggests fixes; it **never auto-rewrites** frontmatter.

### Severity-split invariants (WARN-plain / ERROR-flag-gated)

The two advisory checks below are WARN in a plain run (exit 0). Each is
promoted to an ERROR — causing non-zero exit — by a **different flag**, because
they are enforced at different lifecycle points:

| Check | Plain run | Under `--strict` | Under `--require-commit` | Who uses it |
|---|---|---|---|---|
| **Missing commit hash** | WARN (exit 0) | WARN (exit 0) | **ERROR (exit 1)** | `sdd-verify` gate — `--strict --require-commit` |
| **Stale feature rollup** | WARN (exit 0) | **ERROR (exit 1)** | WARN (exit 0) | pre-commit hook — `--strict` only |

Rationale for the split: `commit:` is recorded **after** the task commit, so
the pre-commit hook (`--strict`) must never gate on it — that would false-block
the very commit writing the hash. Commit-hash provenance is enforced at
verify-time only, via `--require-commit`. `sdd-verify` uses both flags
(`--strict --require-commit`) to enforce all advisory checks at once.

| Check | Condition | Fix |
|---|---|---|
| **Missing commit hash** | A `task-*.md` with `status: verified` has no `commit:` field (or it is empty) | Add `commit: <sha>` — recorded by `sdd-execute` after the task's commit |
| **Stale feature rollup** | `<feature>/todo.md` has `generated: true` and a Status Rollup cell that contradicts the current WP `status:` | Run `sdd-rollup.sh <feature>` to regenerate |

---

## Template marker

Every template's first body line after frontmatter is:

```
<!-- Template: <name> v4 (frontmatter-first, flat layout) -->
```

so a stale template (missing the marker or wrong version) is detectable by
`sdd-validate.sh`. The marker check is **additive**: v4 is current, but v3 is
still accepted, so legacy plans never go stale on a marker bump alone.

---

## Transition ledger — `<feature>/.sdd-transitions.jsonl`

Append-only, git-tracked, one JSON row per WP status transition. **Single
writer:** `sdd-transition.sh` (never hand-edit). Each row:

```jsonc
{ "ts": "<ISO-8601 Z>", "wp": "<wp-slug>", "from": "<status>", "to": "<status>",
  "reason": "<short why — the decision rationale>", "override": <bool>,
  "commit": "<short sha>",
  // ── attribution stamp (auto-filled by sdd-attribution.sh; degrade → "unknown") ──
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
`strategy: deterministic`). When present, `sdd-validate.sh` integrity-checks it.

### The block (both altitudes)

```yaml
task_type: code | research | ops | writing | optimization | analysis | migration
goal:
  outcome: "<what is true when done — one measurable sentence>"
  verification:                 # the Verification Surface (router input)
    strategy: deterministic | numeric | judge | human
    check: <command | metric spec | judge spec | gate prompt>
  constraints: ["<what must not regress>", ...]
  boundaries: ["<allowed files/tools/resources>", ...]
  iteration_policy: "<how to choose the next action after each attempt>"
  blocked_stop: "<when to halt and report paths exhausted>"
```

The **WP** block additionally carries:

```yaml
inherits_from: <feature-slug | null>    # cascade source; WP-only (a feature spec has no parent)
```

### Per-strategy `check` shapes

| `strategy` | `check` shape | How completion is decided |
|---|---|---|
| `deterministic` | string command, e.g. `"pytest tests/auth -q"` | exit 0 = met |
| `numeric` | `{bench: "<cmd emitting JSON {metric: value}>", metric: "p95_ms", op: "<", threshold: 120}` | run bench, parse metric, compare `metric op threshold` |
| `judge` | `{artifact: "<path>", rubric: "<criteria>", block_on: [CRITICAL, HIGH]}` | judge verdict; met iff no finding at/above a `block_on` severity |
| `human` | string gate prompt | NON-BLOCKING in an autonomous loop (pause → write findings → exit → resume next run) |

`op` ∈ `< | <= | > | >= | == | !=`. `block_on` is a non-empty list of severity
labels (`CRITICAL | HIGH | MEDIUM | LOW`).

### One source of truth

The `goal:` frontmatter is authoritative. `goal.outcome` **supersedes** the body
`## Goal` section and `goal.verification` **supersedes** `## Verification`; those
sections become a rendered prose mirror (or are dropped). There is no third
representation.

### Task level (no per-task strategy)

Tasks do **not** carry a strategy. A task keeps its `verify:` field = a
**deterministic** evidence check (exit 0 = pass) that proves *its own slice* of
the work. It is two things at once: a per-task progress/evidence signal during
execution **and** a conjunct of the WP-completion predicate. The strategy router
(`numeric | judge | human`) operates **only at the WP-goal altitude**: the WP
`goal.verification` is the **authoritative completion unit** — the single gate
that decides whether the WP is done. (A task is therefore a deterministic *step*
toward the WP goal, never an independently strategy-verified atom.)

> **Coverage rule.** The WP goal is met ⇔ every task `verify:` passes **AND** the
> WP-level `goal.verification` passes. The two are complementary, not redundant:
> task `verify:` proves each slice was built; `goal.verification` is the
> authoritative gate that proves the WP outcome holds as a whole. This states
> *what* must hold, not *when* each conjunct is evaluated — the execution engine
> chooses the timing.
>
> **Facet-coverage self-check.** Every facet of `goal.outcome` MUST be covered by
> `goal.verification`. A task `verify:` may prove only a slice; the WP gate must
> not leave any outcome facet unverified. When `goal.verification` cannot cover a
> facet on its own, the WP author extends it to cover that facet — a task
> `verify:` never stands in for the authoritative WP gate.

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

### Goal-block integrity invariants (enforced by `sdd-validate.sh`)

When a `goal:` block is present:

- `goal.outcome` is present and non-empty (WP and feature).
- `goal.verification.strategy` ∈ `{deterministic, numeric, judge, human}`.
- `numeric` ⇒ `check` is a mapping with `bench`, `metric`, `op` (∈ the op set),
  and a numeric `threshold`.
- `judge` ⇒ `check` is a mapping with non-empty `artifact`, `rubric`, and a
  non-empty `block_on` list.
- `deterministic`/`human` ⇒ `check` is a non-empty string.
- `task_type`, when present, ∈ the `task_type` enum.
- `inherits_from`, when set on a WP, resolves to an existing feature spec slug.

A malformed goal block is a **fatal** schema violation — the validator exits
non-zero regardless of `--strict` (distinct from advisory status-drift errors).

### Goal-mandatory-at-ready (schema v5, `schema_version:` marker)

When a WP's frontmatter carries `schema_version: 5` (or higher) **and** its
`status` is `ready`, `executing`, or `verified`, the `goal:` block is no longer
optional — a missing `goal:` is a **fatal** schema violation (same severity as
a malformed block; non-zero exit regardless of `--strict`). Absent the marker,
behavior is unchanged from v4 (goal block optional, legacy fallback applies).
This check is gated strictly on the marker's presence — it never fires on a
plan that does not carry `schema_version:`.

### goal_approved_version

`goal_approved_version` is the **sha256 hash (first 12 hex chars)** of the raw
`goal:` block text — the lines from `goal:` up to the next top-level frontmatter
key, with per-line trailing whitespace stripped and line endings normalized to LF.
It is **null/absent** until the first harden gate; set by `sdd-harden` at the
`hardened → ready` approval.

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

## Tier-1 feature audit (adversarial, hash-gated)

The adversarial-verification principle is applied in **two tiers**, scaled to the
defect's altitude (not the WP count): **Tier-1** audits *feature-global* defects
**once per feature**; **Tier-2** (`sdd-harden` Step 0a) is a cheap *WP-scoped
delta* that consumes Tier-1 findings as typed DATA. This concentrates the
expensive cross-cutting review up front (cheap to fix at the spec/structure
level) and keeps per-WP harden from re-litigating it.

**Artifact:** `<PLANS_ROOT>/<feature>/.tier1-audit.md` — git-tracked, one per
feature. Written by `sdd-decompose` (Step 10.7) and refreshed by `sdd-harden`
only when stale. Shape:

```yaml
---
feature: <feature-slug>
audit_hash: <sha256[:12] of the feature structure+goals — see below>
generated: YYYY-MM-DD
verdict: pass | findings
---
# Tier-1 feature audit

- scope: cross-wp-contract | shared-file-ownership | ordering | nondeterministic-check | claims-vs-source
  severity: CRITICAL | HIGH | MEDIUM | LOW
  wps: [wp-01-x, wp-02-y]
  finding: <one-line description>
  # (repeat per finding; empty list ⇒ verdict: pass)
```

**`audit_hash` input (canonical, deterministic).** The hash covers the feature's
*structure + goals* so it changes exactly when a re-audit is warranted:

1. the sorted list of WP slugs,
2. each WP's `depends_on` list (sorted),
3. each WP's raw `goal:` block text (same normalization as
   `goal_approved_version`: trailing-whitespace-stripped, LF-normalized),
4. the spec's `## Interface Contract` section text (cross-WP contracts).

Computed by `sdd/scripts/sdd-feature-hash.sh <feature-dir>` (single source of the
hash; never hand-computed — LLMs cannot hash reliably). **Freshness gate:** an
audit is fresh iff `.tier1-audit.md`'s `audit_hash` equals the recomputed hash;
a stale or absent audit triggers a re-run (a `feature-audit`-role dispatch).

**Tier-2 freshness fallback.** `sdd-harden` consumes Tier-1 as DATA for the WP it
is hardening. If a *sibling* WP changed since the Tier-1 snapshot (hash mismatch),
the cross-WP findings may be stale → `sdd-harden` falls back to a whole-feature
review rather than trusting a stale delta.
