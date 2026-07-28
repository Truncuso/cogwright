---
name: goalforge-decompose
description: "Decompose an approved feature spec into work packages and tasks. Reads plans/<feature>/spec.md, emits wp-NN-<slug>/ folders each containing overview.md (status: spec), todo.md, and task-NN-*.md files stamped from WP templates. Fills depends_on and parallel from the spec's WP table. Also owns the single-WP Add-WP mode (--add-wp): author ONE new WP into an existing feature — the fast-path (route: fast) WP author and the lightweight grow-on-the-go path for a mid-flight WP add, without a full re-decomposition (goalforge-redecompose stays the restructure tool). Trigger: the user asks to decompose, break down, or plan the work packages for a feature that has an approved spec.md — or to add a single WP to an existing feature mid-flight."
metadata:
  skill-kind: preference
  version: 1.3.0
hooks:
  Stop:
    - hooks:
        - type: command
          command: "$HOME/.claude/scripts/skill-measure.sh goalforge-decompose"
        - type: command
          command: "$HOME/.claude/hooks/skill-trace.sh goalforge-decompose:stop"
---

# goalforge-decompose

Reads an approved feature spec and emits the WP folder tree: one `wp-NN-<slug>/`
folder per work package, each containing `overview.md`, `todo.md`, and one or
more `task-NN-*.md` files. Fills `depends_on` and `parallel` from the spec's WP
table.

Schema reference: `~/.claude/skills/goalforge/references/schema.md`.
Templates: `~/.claude/skills/goalforge/references/templates/`.

## When NOT to decompose — JIT rule (soft, forward-only; 2026-07-16)

Do not decompose a feature until it is **next-to-execute** (spec approved AND at
the execution frontier). Decompose-ahead builds a speculative WP buffer whose
todo.md rollups, `depends_on` edges, and mirrored sequence entries drift before
the work ever runs — measured 2026-07-16: 106 WPs at `spec` against 3 executing,
and 57% of a month's commits spent on coordination surfaces. When asked to
decompose a feature that is not next-to-execute, say so and confirm before
proceeding. Forward-only: existing decomposed WPs stay (their depends_on edges
are load-bearing); this rule governs NEW decompositions.

## Inputs

- `<PLANS_ROOT>/<feature>/spec.md` — must exist. **Exception:** Add-WP mode
  (below) tolerates an absent `spec.md` — a `route: fast` feature has none by
  design; a full-path feature's spec is read when present.
- `<PLANS_ROOT>/<feature>/overview.md` — read to extract the feature title
  and confirm `status: ready` (Add-WP mode: any non-`archived` status).

## Outputs (contracted files only)

For each work package `wp-NN-<slug>`:

| File | Template | Initial status |
|---|---|---|
| `<PLANS_ROOT>/<feature>/wp-NN-<slug>/overview.md` | `wp-overview.md` | `spec` |
| `<PLANS_ROOT>/<feature>/wp-NN-<slug>/todo.md` | `wp-todo.md` | — |
| `<PLANS_ROOT>/<feature>/wp-NN-<slug>/task-NN-<slug>.md` | `task.md` | `pending` |

Also generates/updates:

| File | Change |
|---|---|
| `<PLANS_ROOT>/<feature>/overview.md` | Fills the Work Packages table with WP slugs, titles, and statuses |
| `<PLANS_ROOT>/<feature>/todo.md` | Auto-generated rollup (via `goalforge-rollup.sh`); derived from WP statuses and open items |

No other files are created or modified.

## Procedure

### Step 1 — Load spec

Read `<PLANS_ROOT>/<feature>/spec.md`. Extract:

1. **WP table** (if present): each row gives a WP title, rough scope,
   dependencies, and whether it can run in parallel with siblings.
2. **Design** + **Interface Contract**: infer task breakdown when the WP table is
   absent or sparse.
3. **Non-Goals**: tasks that would implement non-goals must not be created.
4. **Feature goal block** (frontmatter `task_type` + `goal:`): the parent goal;
   each WP's goal block derives from it (Step 5b) and may cascade unset fields via
   `inherits_from`.

If the spec has no WP table, derive work packages from the Design section, grouping
logically cohesive chunks. Apply the vertical-slice rule: each WP should deliver
one complete, testable increment, not a horizontal layer.

### Step 2 — WP sizing check

A WP is sized by its **goal**, not its task count. The WP is the authoritative
goal + verification + commit unit (schema.md §Goal object); tasks inside it are
ordered execution *steps* and may be coarse. Size the WP around one clean,
measurable goal — do not split a cohesive WP merely because it carries several
substantial steps. Evaluate each candidate WP:

- If a WP title requires "and" (two distinct outcomes), split it.
- If a WP cannot be described by a ≤3-bullet acceptance criterion, split it.
- If a WP exceeds ~10 tasks, that is a *signal* its goal may be doing two things —
  review it; split only if the goal is genuinely compound (not a soft cap).

Task lower bound is only useful per-task checkpoint/recovery granularity (one
crash should not lose a large uncommitted step). Present the proposed WP list for
confirmation if any WP is large or the decomposition is non-obvious; proceed
without it for clear small-to-medium decompositions.

**Wide mechanical refactors** (one change repeated across many call sites —
rename, signature change, API migration): slice WPs by the **expand–contract**
pattern from the `deprecation-and-migration` skill — expand the new form beside
the old, migrate call sites in batches sized by blast radius (one WP or task per
batch, CI green after each), then contract the old form away in a final WP.

**Prototype WPs.** A WP whose goal is answering ONE design question that only a
built thing can settle — how it looks, behaves, performs, or scales (criterion:
`~/.claude/skills/goalforge/references/fidelity.md`) —
rather than shipping production code is a **declared spike**: set
`register: prototype` in its frontmatter (schema.md §WP frontmatter), give the
goal block a `judge` or `human` strategy over the findings doc, name the
prototype branch (logic / UI / perf) in the outcome, and stamp **exactly one
task** ("answer the question; deliverable = the findings doc") — goalforge-execute
collapses the spike to that task's commit so the WP exit contract holds.
`goalforge-execute` routes such a WP to the `prototype` skill; only the findings
doc commits. A design
question smaller than a WP does not get its own prototype WP — it surfaces as
an open question and routes to `prototype` via `goalforge-harden` Step 1.

### Step 3 — Derive WP metadata

For each WP, determine:

- **Slug**: kebab-case short title (e.g. `scaffold-db-schema`).
- **Number** (`NN`): zero-padded two-digit sequence; **WP ID** = `wp-NN-<slug>`.
- **`depends_on`**: WP slugs this WP cannot start until they are `ready`+ (from
  the spec's WP table; default `[]`).
- **`parallel`**: `true` if it can run concurrently with siblings once
  `depends_on` are satisfied (from spec; default `false`).
- **`severity`**: `HIGH | MEDIUM | LOW`, inferred from spec risk/criticality
  (default `MEDIUM`).

### Step 4 — Idempotency check

For each WP folder `<PLANS_ROOT>/<feature>/<wp-id>/`:

- **Folder absent**: create it and stamp all files.
- **Folder present, files absent**: stamp the missing files.
- **Folder present, files present**: skip without modifying (do not clobber; log
  that the WP was already present).

### Step 5 — Stamp WP `overview.md`

Stamp `overview.md` from the `wp-overview.md` template. Frontmatter is the
template skeleton with: `name: <wp-id>`, `status: spec`, `severity`, `parallel`,
`depends_on` (empty list if none), `plan: <feature>`, and one `relationships`
`depends_on` entry per dependency. Full field list: schema.md §Goal object + the
template.

> **Genesis, not a transition.** This initial `status: spec` is the WP's birth
> state, stamped from the template — decompose does **not** route it through
> `goalforge-transition.sh` (which reads an existing `from` status). Every *subsequent*
> WP-`status:` change is written exclusively by `goalforge-transition.sh` in the
> downstream chain skills — never by hand-edit or `sed`.

Body sections: **Goal** (one measurable sentence), **Verification** (exact
command/check proving the WP done), **Tasks table** (from Step 6), **Open
Questions** (placeholder).

**Quote colon-bearing free-text frontmatter.** Any free-text frontmatter string
that may contain a colon — `title:`, and any authored `goal.outcome` — MUST be
double-quoted (the templates default to the quoted form; keep it). An unquoted
colon-space re-parses the line as a nested map and the whole frontmatter block
breaks, so `status`/`title` read empty downstream.
INCORRECT: `title: research: capture idea` → parses as a nested map, frontmatter
breaks, status reads empty.
CORRECT: `title: "research: capture idea"`.

### Step 5b — Derive the WP goal block + set `inherits_from`

For each WP, derive its **goal block** in `overview.md` frontmatter from the
feature goal (Step 1). The `wp-overview.md` template carries the skeleton; field
shapes and strategies are owned by schema.md §Goal object. Populate:

- **`task_type`** — the WP's own dominant nature; defaults to the feature's.
- **`goal.outcome`** and **`goal.verification`** — **always WP-authored,
  never inherited.** One measurable outcome sentence (empty is invalid); a WP-declared
  verification `strategy` (`deterministic`/`numeric`/`judge`/`human`) + `check`
  in that strategy's shape. Every WP declares its own verification surface.
- **`goal.constraints`**, **`goal.boundaries`** (lists) — WP-specific entries,
  **unioned** with the feature's under `inherits_from` (dedup), so a WP never
  silently drops an inherited one.
- **`goal.iteration_policy`**, **`goal.blocked_stop`** (scalars) — set only if
  the WP differs; **leave unset to inherit** the feature's value.
- **`inherits_from: <feature-slug>`** — the feature slug, so unset scalars
  cascade and lists union; `null` only for a deliberately standalone WP.

**Cascade rule** (only when `inherits_from` resolves to an existing feature
spec): `outcome`/`verification` never inherit; scalars inherit when unset on the
WP; lists union WP ∪ feature with dedupe.

The goal block is optional for back-compat; derive it whenever the feature spec
carries one — a WP without it falls back to legacy `## Goal` + task `verify:`
(treated as `strategy: deterministic`).

### Step 6 — Stamp WP `todo.md`

Create `todo.md` from the `wp-todo.md` template (v5 scratchpad): fill `name`,
`title`, `plan`, `wp`, `updated`. Leave the Open Items and Blocked On sections as
template placeholders.

### Step 7 — Derive and stamp tasks

For each WP, derive the ordered **steps** (tasks) that together deliver the WP
goal. A task is a deterministic execution step — not an independently
strategy-verified atom (the authoritative gate is the WP `goal.verification`;
schema.md §Task level). Each task should be:

- A cohesive unit whose `verify:` **deterministically proves its own slice**
  (exit 0). Lighter means *smaller scope*, never *weaker evidence*.
- Small enough that its per-task commit is a sensible recovery checkpoint, yet
  free to be richer than a single-line change (the WP, not the task, carries the
  semantic-review and commit-cleanup ceremony).
- Named `task-NN-<slug>.md`, `NN` zero-padded within the WP.

Stamp each task from the `task.md` template. Deltas to fill: `name`, `title`,
`status: pending`, `complexity` (`low`/`medium`/`high` by scope — low = one-file
change, medium = multi-file/moderate reasoning, high = architectural/uncertain),
`parallel`, `depends_on` (task slugs in the same WP), and `verify:`. **`verify:`
is ALWAYS a block scalar (`|`)** — `'` and `\` are literal inside it (BRE like
`a\|b` / `a\.b` is safe); NEVER a double-quoted `verify:` (`\|` `\.` are invalid
YAML escapes that break frontmatter → status reads empty). The commented
`checkpoint:` map stays template-provided.

**Coverage rule.** Tasks carry no strategy — each `verify:` is a deterministic
evidence check (exit 0 = pass) over that task's slice. The WP-level
`goal.verification` is the **authoritative completion gate**; the WP goal is met
⇔ every task `verify:` passes **AND** the WP `goal.verification` passes
(complementary, not redundant — schema.md §Task level). Decompose such that
**every facet of the WP's `goal.outcome` is covered by the WP
`goal.verification`**. No outcome facet may be left unverified.

### Step 7b — Decomposition quality self-check

Before stamping the feature tables, run this self-check over every WP just
authored — the recurring defects that otherwise surface only at pre-harden
review (or mid-execute). Fix each in place now; it is far cheaper here.

1. **Verification checks are deterministic and self-contained.** A WP
   `goal.verification.check` declared `strategy: deterministic` (and every task
   `verify:`) must be fixture/command-only, reproducible offline — **no live run,
   network call, manual eyeballing, or interactive step.** A real
   end-to-end/manual check belongs in a separate "manual integration" note in the
   WP body, never inside the deterministic gate.
2. **No stale open questions.** Every `## Open Questions` entry must be a genuine
   *harden-time decision*. If a task you just authored decides it, mark it
   `RESOLVED: <decision>` (keep for provenance) or drop it — a decomposition that
   leaves answered questions open burns a harden cycle re-deciding them.
3. **Cross-WP contracts are pinned, not "TBD".** When WP-A produces an artifact
   (path + schema) that WP-B consumes, author the **identical** path convention
   and schema in *both* overviews, and flag it for lifting into the spec's
   Interface Contract (you cannot edit `spec.md` here — record the need or surface
   it). A consumer WP referencing an undefined producer artifact is unspecifiable.
4. **Missing-input handling is stated.** Any task whose script/hook reads an
   optional or external input (a sibling dir, env var, another tool's log) must
   state its zero-breakage behavior when that input is absent (tolerate → empty
   output, exit 0; or exit 2 to block). Silence becomes a runtime crash later.
5. **One owner per shared file; dependencies point backward only.** A file in ≥2
   WP boundaries must have a single owning WP. A `depends_on` must never point at
   a later WP. Reorder, merge, or reassign ownership so the dependency graph is
   acyclic and points earlier-or-equal.
6. **Facet coverage — the WP gate covers every outcome facet.** Enumerate the
   facets of each WP's `goal.outcome` (each measurable clause); every facet MUST
   be covered by the WP `goal.verification` (the authoritative gate). A task
   `verify:` proving a slice does not substitute. If a facet has no covering check,
   extend it (or declare the right `strategy`: `numeric`/`judge`/`human`). A WP
   whose gate leaves an outcome facet unverified is incomplete.

If a check needs a spec change you cannot make here, surface it to the user
rather than silently encoding a guess.

### Step 8 — Update feature `overview.md` WP table

List each created WP in the Work Packages table in
`<PLANS_ROOT>/<feature>/overview.md` (columns `WP | Title | Status`, each row
`` `wp-NN-<slug>` | <title> | `spec` ``). Set `work_packages:` in the frontmatter
to the list of WP slugs; set `updated:` to today.

### Step 9 — Bump timestamps

Set `stage_updated:` in every new WP `overview.md` to today. Set `updated:` in
every `todo.md` to today. Set `updated:` in the feature `overview.md` to today.

### Step 10 — Generate feature rollup

Generate the feature-level `todo.md` rollup:

```bash
bash ~/.claude/skills/goalforge/scripts/goalforge-rollup.sh <PLANS_ROOT>/<feature>
```

It reads each WP `overview.md` status + `todo.md` open items and writes
`<PLANS_ROOT>/<feature>/todo.md` with `generated: true` (idempotent — twice
produces byte-identical output).

### Step 10.5 — Lint the generated tree

Before reporting, parse-check every file just written:

```bash
bash ~/.claude/skills/goalforge/scripts/goalforge-validate.sh --feature <feature> --show <PLANS_ROOT>
```

Fix any `invalid YAML frontmatter` ERROR immediately — its most common causes are
a double-quoted `verify:` scalar containing `\|` / `\.` (Step 7: always use a
block scalar) OR an unquoted colon-bearing `title:` / `goal.outcome` (Step 5:
always double-quote free-text that may contain a colon) — fix by using the block
scalar or double-quoting the value. Malformed frontmatter silently makes a
`status`/`title` unreadable downstream, so catch it here, not three sessions later.

### Step 10.7 — Tier-1 feature audit (adversarial, hash-gated)

Run the **Tier-1 adversarial audit once per feature**, here at the
decompose→harden seam — the cheapest place to catch *feature-global* defects
before per-WP harden. Feature-global defects are audited once here; WP-local
defects are a cheap per-WP delta in `goalforge-harden` (Step 0a).

1. **Compute the feature audit hash** (deterministic, gates re-runs):

   ```bash
   bash ~/.claude/skills/goalforge/scripts/goalforge-feature-hash.sh <PLANS_ROOT>/<feature>
   ```

   The hash covers the feature's *structure + goals* (sorted WP slugs, each
   `depends_on`, each `goal:` block, spec Interface Contract — schema.md §Tier-1
   feature audit). Re-run **only when the hash differs** from the one stamped in
   `.tier1-audit.md`; an unchanged structure reuses the cached verdict.

2. **If stale (or no audit exists), dispatch the feature-audit agent.** Resolve
   its dispatch from the canonical role→tier map — role `feature-audit`
   (`scripts/goalforge-pick-agent.py`, instantiated to an explicit `{model, effort}`
   via `resolve_dispatch`; state both on the brief); do not restate the tier here. Its cold,
   author-blind whole-feature brief + the `.tier1-audit.md` stamp contract:
   `references/tier1-feature-audit.md`. `goalforge-harden` reads the stamp as typed DATA.

**Advisory at decompose time** — record findings, do not block; the human harden
gate enforces resolution.

### Step 11 — Report  <!-- was Step 10 -->

```
Decomposed <feature> into N work packages:
  wp-01-<slug>  (<M> tasks)
  wp-02-<slug>  (<M> tasks)
  ...
Updated: <PLANS_ROOT>/<feature>/overview.md  (work_packages list)
Generated: <PLANS_ROOT>/<feature>/todo.md  (rollup via goalforge-rollup.sh)
Tier-1 audit: <PLANS_ROOT>/<feature>/.tier1-audit.md  (<verdict>; hash <hash[:8]>)
Next: run goalforge-harden to grill each WP and resolve open questions.
```

## Add-WP mode (`--add-wp`) — author ONE WP into an existing feature

The lightweight sibling of a full decomposition — an **append, not a reconcile**:
it never touches existing WPs (no status changes, supersession, or renames). The
moment a learning implies an existing WP is wrong (`changed`/`dropped`/`ambiguous`
in reconcile vocabulary), stop and route through `goalforge-redecompose`. Two callers:

- **Fast path** (`route: fast`): capture delegates here to author the single WP
  that carries the whole goal (goalforge-capture §Fast path).
- **Grow-on-the-go**: mid-flight a learning surfaces one new WP without
  invalidating existing WPs. (When it *changes or drops* existing WPs, that is a
  restructure: use `goalforge-redecompose`'s 5-bucket reconcile, not this mode.)

Invocation: `goalforge-decompose --add-wp <slug> --goal "<outcome>"` (optionally
`--depends-on <wp-slug>,…`, `--severity`, `--task-type`).

Procedure — the scoped subset of the full run:

1. **Derive metadata** (Step 3): number = next free `NN`; `depends_on` from
   `--depends-on` (validated existing sibling slugs, backward-pointing only);
   `severity`/`task_type` from flags or defaults.
2. **Idempotency** (Step 4): an existing WP folder → skip without modifying
   (byte-identical no-op on re-run).
3. **Stamp the WP** (Steps 5, 5b, 6, 7): `overview.md` (born `status: spec`) with
   a **complete goal block** — `goal.outcome` from `--goal`, WP-authored
   `goal.verification`, `inherits_from` set to the feature when it has a goal
   block (fast-path features have none — author self-contained, `inherits_from:
   null`) — plus `todo.md` and task files.
4. **Self-check** (Step 7b) scoped to the new WP, plus: its `depends_on` targets
   exist and the dependency graph stays acyclic.
5. **Refresh feature artifacts** (Steps 8–10): WP table row, `work_packages:`,
   timestamps, `goalforge-rollup.sh`.
6. **Lint** (Step 10.5): `goalforge-validate.sh --feature <feature>` — feature level,
   never the WP subtree alone.
7. **Tier-1 hash note — do NOT re-audit here.** Adding a WP stales the feature
   hash (`goalforge-feature-hash.sh`), so the next `goalforge-harden` Step 0a.1 freshness gate
   detects the drift and takes its whole-feature-review fallback. Report one line:
   `tier-1 audit stale (WP added) — next harden re-audits`.

Report: `Added <wp-id> (<M> tasks) to <feature>; rollup + WP table refreshed;
tier-1 audit stale — next harden re-audits.`

The new WP then enters the normal frontier: full-path features harden it
(`goalforge-harden`); a fast-path WP takes the deterministic gates in goalforge-capture
§Fast path (validate + OQ check + complexity → record goal hash
(`goalforge-goal-hash.sh --record`) → `--mode auto`, escalating to harden on any
trip). The add-wp'd fast WP is born `goal_approved_version: null`, so capture
records the hash before the auto-advance — else wp-01's `→ready` gate refuses it.

## Constraints

- **Never** modify `spec.md` — it is read-only for this skill.
- **Never** advance `overview.md` status beyond `ready` (set by `goalforge-spec`).
- **Never** set a newly created WP status to anything but `spec`, or a task
  status to anything but `pending`.
- Write only the contracted files listed in the Outputs table above.
- Idempotent: re-running must not clobber existing WP or task files.

## Plans root

Resolve `<PLANS_ROOT>` at runtime per the priority rules in
`~/.claude/skills/goalforge/references/schema.md` §PLANS_ROOT resolution:
env `SDD_PLANS_DIR` → project git-root `plans/` → global `~/.claude/plans/`.

## Template reference

Templates at `~/.claude/skills/goalforge/references/templates/`. Stamped files carry
the appropriate marker:

```
<!-- Template: wp-overview v4 (frontmatter-first, flat layout) -->
<!-- Template: wp-todo v5 (frontmatter-first, flat layout) -->
<!-- Template: task v4 (frontmatter-first, flat layout) -->
```

## Gotchas

- Idempotency is folder-level: an existing `wp-01-scaffold/` is **skipped without modifying** any file — editing `spec.md` and re-running will NOT update an already-created WP. Delete the WP folder explicitly to force a re-stamp.
- **A live or manual step inside a `strategy: deterministic` check is the single most common decompose defect** (Step 7b.1): it cannot run in the unattended `goalforge-execute` eval loop. Keep the gate fixture/command-only; the pre-harden review BLOCKs on it, so catching it here saves the round-trip.
- **A fast-path feature growing past ~3 WPs or gaining its first cross-WP contract has outgrown the fast route** — prompt the user to author `spec.md` retroactively (`goalforge-spec`) so shared shapes get a single home (the Interface Contract). Judgment nudge, not a hard gate.
- Edge-case gotchas (empty-`goal.outcome` late-fail, cascade-scalar silent-resolve): `references/gotchas.md`.
