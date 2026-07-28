---
name: goalforge-archive
description: "Archive a completed goalforge feature to its terminal `archived` status, optionally recording that it supersedes a prior feature. Fail-closed: REFUSES unless the feature is `status: completed` (cannot archive draft/ready/active). On `--supersedes <old>` writes the `supersedes`/`superseded_by` relationship edges on both features and archives the old one too, verifying both slugs exist first. A `--relocate` mode reconciles a STRANDED archived feature — one already `status: archived` but still physically at the active plans root (status set out-of-band, never moved) — by moving it into `_archived/` (move-only, no frontmatter edit; requires status: archived). Runs the strict validator gate and an ensure-committed check. TRIGGER: 'archive feature', 'archive completed feature', 'feature B supersedes A', 'migration archive', 'relocate stranded archived feature', 'reconcile archived plan at active root'. Human-gated / on-demand — NOT part of the sdd chain."
metadata:
  skill-kind: preference
  version: 1.4.0
---

# goalforge-archive

Drives a feature to its terminal `archived` status — the historical-record end
state. Two modes: a **plain archive** of one completed feature, and a
**supersession archive** that also records `supersedes`/`superseded_by` edges
between a replacing feature and the one it replaced.

`completed → archived` is **explicit user action only** — it is never automatic.
`goalforge-verify` advances a feature to `completed` (last-WP rule) and then *offers*
archival; this skill performs it on request.

Schema reference: `~/.claude/skills/goalforge/references/schema.md`.

## Plans root

`<feature>` (and `--supersedes <old>`) name folders inside `<PLANS_ROOT>/`.
Resolve `<PLANS_ROOT>` per `~/.claude/skills/goalforge/references/schema.md`
§PLANS_ROOT resolution: env `SDD_PLANS_DIR` → project git-root `plans/` →
global `~/.claude/plans/`.

## Inputs

- `<feature>` — the feature slug to archive (required).
- `--supersedes <old>` — optional; the prior feature slug that `<feature>`
  replaces.
- `--relocate` — optional; reconcile a **stranded** archived feature (move-only).
  Mutually exclusive with `--supersedes`. See *Relocate mode* below.
- `--strict-refs` — optional; escalate the reference-gate (Step 4b) from WARN to
  REFUSE (exit 6) when inbound **path** references to the feature would dangle after
  the move. Recommended for interactive archival. Composes with all modes.

## Relocate mode (stranded archived → `_archived/`)

A feature can end up `status: archived` but still physically at the active plans
root — its status was set out-of-band (a reconciliation pass, a hand edit) and the
folder was never moved into `_archived/`. The default gate **cannot** fix this: it
fail-closes on `status: completed`, and a stranded feature is already `archived`,
so it REFUSES. `--relocate` is the dedicated handler:

```bash
bash ~/.claude/skills/goalforge/scripts/goalforge-archive.sh <feature> --relocate \
     [--plans-root <PLANS_ROOT>]
```

- **Inverse gate:** requires `status: archived` (REFUSE with exit 3 if the feature
  is `completed`/`active`/`ready`/`draft` — use the plain mode for `completed`).
- **Move-only:** writes **no** frontmatter (the feature is already archived); it
  validates the feature scoped (`--feature --strict`) then moves `<feature>/` into
  `_archived/<feature>/`. Destination collision → exit 4 (HALT, no overwrite).
- `--supersedes` is rejected here (exit 2) — supersession is a completing-archival
  concern, not a relocation.

The orchestrator commits the rename (git tracks edit-free moves as a clean rename),
then runs the Step-5 ensure-clean on the new `_archived/<feature>/` path.

## Step 1 — Fail-closed precondition (REFUSE unless `completed`)

Read `<PLANS_ROOT>/<feature>/overview.md`. Inspect the `status:` frontmatter
field. **The skill proceeds ONLY when `status: completed`.**

If `status:` is anything else (`draft`, `ready`, `active`, or already
`archived`), the skill MUST:
- Print the offending status.
- Refuse to archive and halt — make no edits.

A feature must reach `completed` (all sibling WPs `verified`, via `goalforge-verify`'s
last-WP rule) before it can be archived. There is no path that archives a
`draft`, `ready`, or `active` feature.

When `--supersedes <old>` is given, additionally verify **both** slugs resolve
to an existing `<PLANS_ROOT>/<slug>/overview.md` before writing anything. If
either is missing, refuse and report the missing slug. (The `<old>` feature is
not required to be `completed` — a superseded feature is being retired.)

## Step 1.5 — Terminal integration confirmation before archive (soft gate)

The **primary** cross-WP integration review runs at the last-WP→`completed`
transition in `goalforge-verify` (role `integration-review`). This step is the
**terminal confirmation** of that review — the last point before the work becomes
a permanent historical record — not the sole integration tier and not a re-run
from scratch.

- **Confirm the goalforge-verify integration review ran and its findings are resolved**
  (read the feature `findings.md`). If it did run and is clean, this is a quick
  confirmation. If it is missing or has open findings, dispatch the `review` skill
  / `code-reviewer` over the feature's full diff (`git diff` across all WP commits)
  and resolve findings first — archive must not be the *only* place integration is
  checked, but it is the backstop when the upstream review was skipped.
- **Human-judgment, not a mechanical gate** (interactive). This step adds no
  script check and never auto-blocks; the human decides whether findings are
  resolved. (L2 user-decision — `[[review-agent-before-archive]]`.)
- **Autopilot (`SDD_AUTONOMY=unattended`): PARK, do not silently no-op.** With no
  human to judge, if the confirmation cannot be made cleanly (review missing or
  findings open), write the blocker to the feature `findings.md` and stop for human
  pickup — never skip the integration check and proceed to archive.

## Steps 2–4 — Mechanical core (delegated to `goalforge-archive.sh`)

The frontmatter edit, physical move, and validator gate are performed
**deterministically by a script** — `~/.claude/skills/goalforge/scripts/goalforge-archive.sh`
— so the same logic is drivable unattended (the `goalforge-archive-batch.sh` loop). The
script is the single source of truth for these mechanics; this skill is the
human front door (the Step-1 gate presentation, the refusal templates below, and
the Step-6 report).

```bash
bash ~/.claude/skills/goalforge/scripts/goalforge-archive.sh <feature> \
     [--supersedes <old>] [--plans-root <PLANS_ROOT>]
```

What the script does (and its contract):

- **Re-enforces the Step-1 gate** (refuses unless `status: completed`; under
  `--supersedes`, verifies both slugs exist). Exit **3** = refused.
- **Edits frontmatter** (targeted, minimal-diff): `<feature>` → `status: archived`
  + `updated: <today>`. Under `--supersedes`, also writes the inverse edges —
  `supersedes: [[<old>]]` on `<feature>` and `superseded_by: [[<feature>]]` on
  `<old>` (merged into any existing `relationships:` list, never clobbered) — and
  flips `<old>` to `status: archived` too.
- **Validates** each edited feature scoped — `--feature <slug> --strict` —
  BEFORE the move. The validator still WALKS the whole tree (so cross-feature
  `supersedes`/`superseded_by`/`depends_on` edges resolve), but only the archived
  feature's own errors gate, so a tree that legitimately carries deferred drift in
  unrelated features never blocks the archive. Exit **5** if it fails.
- **Moves** `<feature>/` (and `<old>/` under `--supersedes`) into `_archived/`
  AFTER the edit+validate, so git records the edit + rename in one commit. Exit
  **4** if the destination already exists (HALT, no overwrite).

The script does **not** commit and does **not** run ensure-committed — Step 5
does that after the orchestrator commits. On a non-zero exit, present the matching
refusal template and HALT.

## Step 4b — Reference-gate (warn; REFUSE under `--strict-refs`)

Between the validator gate and the physical move, the script scans for **inbound
path references** to the feature — refs that use the active `<slug>/` path (a
cross-cited `findings.md`/playbook, a fixture, a frontmatter `locator:`) and will
**dangle** after the folder moves to `_archived/<slug>/`. This is the gate that
was missing when a blind archive of a cross-cited WP `findings.md` broke ~12 links
and had to be reverted.

- **What is flagged:** only path references (`<slug>/…`) from OUTSIDE the feature's
  own folder and outside `_archived/`, across `<PLANS_ROOT>` and the sibling
  `docs/`. The search is `grep -F` (literal) so a slug with regex chars is safe.
- **What is NOT flagged:** relationship wikilinks `[[<slug>]]` — those are graph
  edges the validator resolves even for archived targets, so archiving never breaks
  them.
- **Behavior:** WARN by default (prints the offending refs + the relocate-then-move
  remedy, exit 0 — non-blocking so the unattended `goalforge-archive-batch.sh` loop is
  unchanged). Under `--strict-refs` it **REFUSES with exit 6**. The remedy in both
  cases: relocate the cross-cited artifact to a stable home and repoint every
  reference (or re-point them to `_archived/<slug>/`) BEFORE archiving.

## Step 5 — Ensure-clean (after the orchestrator commits)

This skill does **not** commit. After the orchestrator commits the archival
edits (including the physical move), confirm the feature path(s) carry no
uncommitted artifacts — using the **new** `_archived/` paths (the originals no
longer exist):
```bash
bash ~/.claude/skills/goalforge/scripts/goalforge-ensure-committed.sh <PLANS_ROOT>/_archived/<feature>
# and, under --supersedes:
bash ~/.claude/skills/goalforge/scripts/goalforge-ensure-committed.sh <PLANS_ROOT>/_archived/<old>
```
On non-zero, report the dirty paths and HALT (do not declare done). The check is
path-scoped (unrelated dirt elsewhere never false-blocks) and branch-agnostic:
in the **dotfiles repo** the working branch is `master`, so the commit lands on
`master` directly — no feature branch, no push. Elsewhere, normal branch rules
apply.

## Step 6 — Report

```
Archived:   <PLANS_ROOT>/_archived/<feature>/overview.md  (status: archived, moved from <feature>/)
[Supersedes: <old> — <old> archived + moved to _archived/<old>/]
Validator:  PASS (goalforge-validate --strict)
Working tree: clean under _archived/<feature>/ [and _archived/<old>/]
```

## Not in the chain

`goalforge-archive` is **NOT** wired into `chain.yaml`. Archival is a terminal,
human-gated decision invoked on demand — never an automated chain step.

## Files read / written

| File | Access |
|------|--------|
| `<feature>/overview.md` | read (`status:` gate) + write (`status: archived`, `updated:`, optional `supersedes` edge) |
| `<feature>/` (directory) | moved to `_archived/<feature>/` after frontmatter edit |
| `<old>/overview.md` | (`--supersedes` only) read (existence) + write (`status: archived`, `updated:`, `superseded_by` edge) |
| `<old>/` (directory) | (`--supersedes` only) moved to `_archived/<old>/` after frontmatter edit |

## State transition

```
feature: completed → archived + moved to _archived/<feature>/        (explicit user action only — this skill)
feature: completed → archived + moved to _archived/<feature>/
         <old>     → archived + moved to _archived/<old>/            (--supersedes, both features)
```

`completed` is the only valid source state. `archived` is terminal. The physical
move to `_archived/` is part of the same atomic user-action: frontmatter edit
then folder move, committed together.

## Refusal template

When the precondition is not met, output:

```
goalforge-archive REFUSED — precondition not satisfied:

Feature: <feature>
status: <offending-status>   (required: completed)

A feature must be `completed` (all WPs verified via goalforge-verify) before it can be
archived. Cannot archive a draft/ready/active feature.
```

When a `--supersedes` slug is missing:

```
goalforge-archive REFUSED — supersedes target not found:

Missing: <PLANS_ROOT>/<old>/overview.md

Check the <old> slug spelling, or confirm the feature exists.
```

## Gotchas

- **Reference-gate flags PATH refs, not wikilinks.** Step 4b greps for `<slug>/`
  (literal, `grep -F`) from outside the feature + outside `_archived/`. A
  `[[<slug>]]` relationship edge is NOT a path ref and is correctly ignored — only
  refs that point INTO the feature's files (a cross-cited `findings.md`, a
  frontmatter `locator:`) dangle after the move. WARN by default keeps the
  unattended batch loop working; `--strict-refs` makes it a hard gate (exit 6).
  Do NOT "fix" a flagged ref by deleting it — relocate the artifact and repoint.
- The status gate is fail-closed on exactly `completed` — `active`, `ready`, `draft`, and an already-`archived` feature all REFUSE in the default mode. There is no "force archive"; advance the feature to `completed` via `goalforge-verify`'s last-WP rule first. The one exception is `--relocate`, whose gate is the *inverse* (`status: archived` required) and which only moves a stranded archived feature into `_archived/` — it never flips a non-archived status.
- Feature terminal status is `archived`; WP terminal status is `verified`. Never write `status: verified` to a feature overview or `status: completed`/`archived` to a WP — the enums do not overlap at the terminal end.
- `--supersedes` archives BOTH features: `<feature>` (the replacing one, already `completed`) AND `<old>` (the replaced one, retired regardless of its prior status). Forgetting that `<old>` also flips to `archived` leaves a half-written relationship with one live and one archived side.
- `supersedes` and `superseded_by` are inverse edges and BOTH must be written (one per feature) — writing only one side leaves the graph navigable from a single direction and the validator's cross-feature check sees only half the relationship.
- The validator gate runs over the WHOLE `<PLANS_ROOT>`, not `<PLANS_ROOT>/<feature>` — a single-feature walk cannot resolve a cross-feature `supersedes` target and would either skip the check or false-dangle. Always pass the plans root.
- Merge new edges into the existing `relationships:` list; never replace it. A feature may already carry `related_to`/`depends_on` edges that must survive.
- The ensure-committed check is path-scoped and branch-agnostic: it passes on `master` (the dotfiles exception) and never false-blocks on dirt outside the feature path. It is NOT a substitute for the commit itself — the orchestrator commits; this skill only verifies cleanliness afterward.
- The physical move happens AFTER the frontmatter edits so git tracks the rename correctly (edit + move in one commit). Moving first, then editing, creates a confusing two-step git history where the file appears at the old path in one commit and the new path in the next.
- After the physical move, `goalforge-ensure-committed.sh` must be called on `<PLANS_ROOT>/_archived/<feature>`, NOT on the original path (which no longer exists after the move).
- `goalforge-validate.sh --strict <PLANS_ROOT>` must walk `_archived/` to resolve cross-feature `supersedes/superseded_by` edges — pass `<PLANS_ROOT>` (not `<PLANS_ROOT>/<feature>`) so the validator sees both sides, including features that have already been moved into `_archived/`.
