---
name: spec
description: "Run a design pass on a captured feature and propose the spec document, or propose a revision of an approved spec when a learning falsifies it (the respec edge). Reads plans/<feature>/overview.md, optionally invokes personas or architect for a multi-lens review, writes plans/<feature>/spec.md from the feature-spec template as the proposal (draft → spec), and ratifies it on spec → ready. HUMAN-GATED: spec → ready needs explicit user approval. Trigger: the user asks to spec, design, or elaborate on a feature that already has an overview.md (status: draft), or a feature sits at status: spec with a proposal awaiting ratification."
metadata:
  skill-kind: preference
  version: 1.2.0
hooks:
  Stop:
    - hooks:
        - type: command
          command: "$HOME/.claude/hooks/skill-trace.sh goalforge-spec:stop"
---

# goalforge-spec

Reads a captured feature overview, conducts a design pass, PROPOSES the spec,
and ratifies it with the human. spec → ready is the single human-gated spec-approval transition
for a first spec and a revision alike: the stage proposes, the human ratifies,
and the skill halts and asks for explicit approval before taking that edge.

- **First spec** (feature at `draft`): the design pass writes `spec.md` as the
  proposal and takes `draft -> spec` (ungated). The Step 3 `yes` takes
  `spec -> ready --mode human`.
- **Revision** (feature at `spec`, entered through a respec edge
  `ready|active|executing|completed -> spec` with `--reason "<learning>"`):
  the stage writes only the proposal dir `respec/<YYYY-MM-DD>-<slug>/`
  (`proposed-spec.md` + `diff.json`) and never touches `spec.md`. The Step 3
  `yes` writes `RATIFIED`, runs `goalforge-respec-apply.sh`, then takes
  `spec -> ready --mode human`. Contract: `references/respec.md`.

**Full route only.** A `route: fast` feature (overview frontmatter, stamped by
`goalforge-capture`) has no `spec.md` by design — its single WP carries the complete
goal block. Invoking goalforge-spec on a fast feature is the deliberate promotion
path (the feature outgrew the fast route — e.g. 3+ WPs or a cross-WP
contract): author the spec retroactively and flip `route: standard` with a note.

Schema reference: `~/.claude/skills/goalforge/references/schema.md`.
Templates: `~/.claude/skills/goalforge/references/templates/`.

## Unattended mode (`SDD_AUTONOMY=unattended`)

When `SDD_AUTONOMY=unattended` is set (the `autopilot` driver sets it), the
`spec → ready` ratification has no human to grant it. **Do not call
`AskUserQuestion` to wait — PARK:** the stage writes the proposal and parks; it never writes RATIFIED,
never runs `goalforge-respec-apply.sh`, and never takes `spec -> ready`. Write the
verbatim approval prompt to a handoff and stop (the run resumes at feature
`spec` when a human approves, or on the next `/autopilot`); the parked prompt
is the gate block with the `grill` token stripped. A first spec may still take
the ungated `draft -> spec` proposal edge. Accepting a spec is a human commitment.
Spec *content* quality checks (personas/architect/judge) are evidence-decidable and
still run. See `~/.claude/skills/autopilot/references/autonomy-policy.md`. Unset
(`interactive`) behaviour is unchanged.

## Inputs

- `<PLANS_ROOT>/<feature>/overview.md` — must exist; `status: draft` (first
  spec) or `status: spec` (a proposal awaits ratification, or a respec edge
  just re-opened an approved spec).
- For a revision: the learning that falsifies a requirement (the respec edge's
  `--reason`).

## Outputs (contracted files only)

| File | Template | Written | Feature status after |
|---|---|---|---|
| `<PLANS_ROOT>/<feature>/spec.md` (first spec) | `feature-spec.md` | at `draft -> spec`, as the proposal | `spec` |
| `<PLANS_ROOT>/<feature>/respec/<YYYY-MM-DD>-<slug>/proposed-spec.md` + `diff.json` (revision) | — | at feature `spec`, as the proposal | `spec` |
| `<PLANS_ROOT>/<feature>/respec/<YYYY-MM-DD>-<slug>/RATIFIED` (revision) | — | Step 3 `yes`, attended only | `spec` |
| `<PLANS_ROOT>/<feature>/overview.md` | — (status via `goalforge-transition.sh`) | Step 3 `yes` | `ready` |

A revision's `spec.md` and WP effects are written by `goalforge-respec-apply.sh`,
never by hand. No other files are created or modified.

## Procedure

### Step 1 — Load overview

Read `<PLANS_ROOT>/<feature>/overview.md`. Extract:

- Problem statement.
- Goal (success criterion).
- Scope (In/Out).
- Any existing open questions or notes.

If `status:` is `spec`, this is a ratification or a revision: read the
existing proposal (`spec.md` for a first spec, the newest `respec/` dir for a
revision) and the respec `--reason`. For any other status, warn and ask the
user to confirm before proceeding.

### Step 2 — Design pass

Conduct a design pass to produce the content of `spec.md`. This involves:

1. **Approach**: the chosen technical approach, key architectural decisions, and
   rationale.
2. **Interface Contract**: public APIs, file contracts, data shapes that other
   components depend on. **Pin every cross-WP artifact here.** Whenever one work
   package will produce an artifact another consumes — a file (give the exact path
   convention), a JSON/record (give the field schema), an env var, a CLI flag —
   write the path *and* the schema in this section now. A contract left "TBD"
   forces `goalforge-decompose` to invent a shape or leave the consumer WP
   unspecifiable; pinning it here is the cheapest place to do it.
3. **Non-Goals**: what the design explicitly excludes.
4. **Open Questions**: unresolved questions that must be answered before
   decomposition or execution.

If a section is blocked by a question that meets the **spike-candidate trigger**
— a how-should-it-look / behave / perform question that more talking will not
settle (criterion: `~/.claude/skills/goalforge/references/fidelity.md`) — spike it to
unblock the section instead of writing the section around the gap; the findings
feed the spec text and any ADR candidates. Most blockers do not qualify and stay
in `## Open Questions` for `goalforge-harden` — this is guidance, not a step.

### Step 2b — Author the feature goal block

Author the **feature-level goal block** in the `spec.md` frontmatter. This is
the parent goal each WP may inherit unset fields from (via `inherits_from`).
Schema: `~/.claude/skills/goalforge/references/schema.md` §Goal object. Set:

- **`task_type`** — `code | research | ops | writing | optimization | analysis`.
  The dominant nature of the work; defaults to `code`. Picked here so dispatch
  and the default-strategy map have a feature-level anchor.
- **`goal.outcome`** — one measurable sentence stating what is true when the
  feature is done. Not a task list — the end state. An outcome facet that is
  itself a spike-candidate question belongs in `## Open Questions`, flagged as
  such (criterion: `~/.claude/skills/goalforge/references/fidelity.md`).
- **`goal.verification.strategy`** — `deterministic | numeric | judge | human`,
  and **`goal.verification.check`** in that strategy's shape (see the
  per-strategy `check` table in the schema). This is the Verification Surface
  the runtime router consumes.
- **`goal.constraints`** — what must not regress (list; may be empty).
- **`goal.boundaries`** — allowed files / tools / resources (list; may be empty).
- **`goal.iteration_policy`** — how to choose the next action after each attempt.
- **`goal.blocked_stop`** — when to halt and report paths exhausted.

Write these into the `feature-spec.md` frontmatter (the template already carries
the block skeleton). `goal.outcome` is authoritative — it supersedes the body
`## Goal` prose; keep them consistent. Leave a facet only partially specified
**only** if it is a genuine open question — record it in `## Open Questions` so
`goalforge-harden` drives it to zero (it must be complete before `hardened → ready`).

**Optional multi-lens review** (recommended for medium/high complexity features):

- Invoke the `personas` skill or the `architect` agent for a second-opinion pass.
- Document any significant concerns or alternative approaches surfaced.
- Skip for trivial features or when the user wants speed over thoroughness.

### Step 2c — Write the proposal

The proposal is written BEFORE the gate; ratification, not the write, is the
approval.

- **First spec** (feature at `draft`): create `<PLANS_ROOT>/<feature>/spec.md`
  from the `feature-spec.md` template, populate every body section from the
  design pass, then take the ungated proposal edge
  `goalforge-transition.sh <feature> spec --from draft --reason "spec proposal"`.

  ```yaml
  name: <feature>-spec
  title: <human title> — spec
  status: spec
  created: <today YYYY-MM-DD>
  updated: <today YYYY-MM-DD>
  feature: <feature>
  ```

- **Revision** (feature at `spec` after a respec edge): leave `spec.md`
  untouched. Write `<PLANS_ROOT>/<feature>/respec/<YYYY-MM-DD>-<slug>/`
  holding `proposed-spec.md` (a complete candidate spec.md; log each changed
  goal facet in its `## Goal Changelog` via
  `goalforge-goal-changelog.sh append <proposal>/proposed-spec.md <facet> ...`)
  and `diff.json`
  (`bash ${CLAUDE_PLUGIN_ROOT}/scripts/goalforge-respec-diff.sh spec.md proposed-spec.md`).
  Carry every `ambiguous` pair (a renumber) into the gate as an open question.

### Step 3 — HUMAN GATE: present and seek ratification

Before ratifying, present the proposal to the user — through the ONE human
template (C7), never a second hand-rolled format:

```bash
bash ${CLAUDE_PLUGIN_ROOT}/scripts/goalforge-stage-report.sh spec <feature> \
  --json <report.json> --feature-dir <PLANS_ROOT>/<feature>
```

The report's `changed[]` carries the goal block first — it is the contract the
rest of the spec serves — then Design, Interface Contract and Non-Goals (for a
revision: the `diff.json` buckets, `changed` and `dropped` keys first); its
`issues[]` carry the Open Questions, one per bullet, each with its `ref`; and
its `next_gate.ask` is verbatim:

```text
Ratify this spec proposal and advance status (spec → ready)? [yes/no/revise/grill]  (grill omitted when SDD_AUTONOMY=unattended or the interview skill is unresolvable)
```

If any goal facet is vague or unset (and not a deliberate open question), refine
it in Step 2b before re-presenting rather than asking the user to ratify an
under-specified goal.

**Do not proceed until the user replies with an affirmative.** If the user
requests revisions (`revise`), iterate the design pass (Step 2), rewrite the
proposal (Step 2c; a revision's `diff.json` is regenerated) and re-present the
DIFF: pass the previous report as `--previous`, so a `revise` round renders
only what changed and never re-pastes the whole draft (C7).

```bash
bash ${CLAUDE_PLUGIN_ROOT}/scripts/goalforge-stage-report.sh spec <feature> \
  --json <report.json> --previous <prev-report.json> --feature-dir <PLANS_ROOT>/<feature>
```

If the user declines (`no`), stop: the proposal stays at feature `spec`, no
`RATIFIED` is written and no status changes.

`grill` is the fourth answer, additive: `yes`, `no`, and `revise` keep the
semantics above unchanged. It runs a pre-ratification grill over the proposal
**before anything is ratified**. Frame the session from the drafted goal block,
the Design, and the Open Questions exactly as rendered in the block above, then
delegate the Q&A loop to the `interview` plugin skill with the literal
`preset: spec-grill`. The `interview` plugin skill takes only a `preset:`
argument (no artifact argument), so that framing is the only channel to the
draft; question technique and stopping behavior stay with the engine. Fold the
returned signals into a Step 2 / Step 2b revision (goal-facet signals go to
Step 2b) and re-present this same gate — a grill never advances status and never
writes `RATIFIED`. An `ADR_CANDIDATE` is carried as an open question and routed
to `adr-write` at harden, not written here.

Under `SDD_AUTONOMY=unattended` the `grill` option is **not** offered: the gate
PARKs per §Unattended mode above, unchanged, and no `AskUserQuestion` is
introduced on that path. Otherwise probe first — *resolvable* := the `interview`
skill (plugin `interview@cogwright`) appears in the session skill listing —
checked **before** rendering the gate; unresolvable renders `[yes/no/revise]`
instead, the option degrades, it never blocks the gate. If resolution fails at
invocation time after `grill` was chosen, report the unresolved skill in one line
and re-present the gate as `[yes/no/revise]` — never stall, never advance.

This gate enforces the `spec → ready` human-gated transition for the feature
(`references/state-machine.md` §Feature policy; goalforge-spec advances
overview.md, not spec.md's own `status: spec`).

### Step 4 — Ratify (the `yes` branch, attended only)

- **First spec**: nothing more to write — `spec.md` is the ratified proposal.
- **Revision**: write `RATIFIED` in the proposal dir, one line
  (`ratified_by: human date=<proposal-dir date> sha256=<proposed-spec.md> diff_sha256=<diff.json> base_sha256=<spec.md> reply=<verbatim reply>`,
  `references/respec.md`), then run
  `bash ${CLAUDE_PLUGIN_ROOT}/scripts/goalforge-respec-apply.sh <feature-dir> <proposal-dir>`.
  It supersedes affected `verified` WPs in place, writes reharden evidence for
  affected `ready` WPs, and copies the proposal over `spec.md`. A non-zero exit
  is a refusal: report it and stop, never patch `spec.md` by hand.

### Step 5 — Advance `overview.md` status

Take the gate edge through the single status writer:

```bash
bash ${CLAUDE_PLUGIN_ROOT}/scripts/goalforge-transition.sh <PLANS_ROOT>/<feature> ready \
  --from spec --mode human --reason "spec ratified: <verbatim reply>"
```

It sets `status: ready`. Then add the spec link to the Links section of
`overview.md` if not already present. Do not modify any other frontmatter fields.

### Step 6 — Outputs written

```
Updated: <PLANS_ROOT>/<feature>/overview.md  (status: spec → ready)
Created: <PLANS_ROOT>/<feature>/spec.md      (status: spec; first spec)
Applied: respec/<YYYY-MM-DD>-<slug>/         (revision; apply report lists superseded and reharden WPs)
Next: run goalforge-decompose (first spec) or goalforge-harden on the reharden WPs (revision).
```

## Drafting discipline

Four rules govern how the spec is drafted (additive discipline — they do not
change the human gate or any status transition):

1. **Research-first** — before fixing an approach, check what already exists
   (prior art, libraries, the repo's own patterns). Do not invent where a known
   solution fits.
2. **Hard-bets-first** — surface the hard-to-reverse decisions early and make
   them explicit in the spec; when two or more such approaches compete, resolve
   the choice explicitly in the spec's `## Decisions` before handoff.
3. **Standalone** — the spec must read on its own: a reader with no session
   context can understand the outcome, constraints, and boundaries.
4. **Concrete-first** — prefer concrete outcomes and measurable verification over
   generic phrasing; no placeholder goals.
5. **Deterministic checks stay self-contained** — when `goal.verification.strategy`
   is `deterministic`, the `check` must be reproducible offline (fixtures /
   commands), with no live run, network call, or manual step. A real end-to-end or
   manual check is worth stating, but as a separate "manual integration" note, not
   inside the deterministic gate — the gate must run unattended in `goalforge-execute`.

## Constraints

- **Never** take `spec -> ready` or write `RATIFIED` without explicit human
  approval (Step 3 gate).
- **Never** create WP folders or task files — those belong to `goalforge-decompose`.
- **Never** modify `todo.md` or edit any WP file by hand — a revision's WP
  effects come only from `goalforge-respec-apply.sh`.
- Once ratified, spec.md changes only through goalforge-respec-apply.sh; the
  stage writes a `respec/` proposal, never the approved `spec.md`.
- Write only the contracted files above.
- If `spec.md` already exists for a feature at `draft`, ask the user whether to
  overwrite or merge.

## Human-gate rationale

`draft → ready` (the feature gate) is one of two human-gated transitions in the SDD state machine.

`spec → ready` is the feature's one spec-approval gate; with `hardened → ready`
(the WP gate) it is one of the two human-gated edges of the SDD state machine
(`references/state-machine.md`). There is no `draft`-exit gate and no second
gate on a revision: a first spec and a revision are both proposals ratified on
the same edge. Automatic advancement would bypass design review and allow
under-specified work to reach execution. The gate is a presentation + explicit
approval, not just a confirmation dialog — the user must see the full proposal
(or, for a revision, its diff) before ratifying.

## Plans root

Resolve `<PLANS_ROOT>` at runtime per the priority rules in
`~/.claude/skills/goalforge/references/schema.md` §PLANS_ROOT resolution:
env `SDD_PLANS_DIR` → project git-root `plans/` → global `~/.claude/plans/`.

## Template reference

Templates at `~/.claude/skills/goalforge/references/templates/`. Stamped files carry:

```
<!-- Template: feature-spec v4 (frontmatter-first, flat layout) -->
```

## Gotchas

- The human-gated transition protected here is `overview.md` advancing from `spec` to `ready` (the ratification, per this skill's Step 3 gate + Outputs table) — it NEVER happens without explicit approval: not on re-run, not if `spec.md` already exists, not via any flag. A second pass over an approved spec is legal only as a respec proposal the human ratifies and `goalforge-respec-apply.sh` reconciles; an unratified or unreconciled second pass (a hand edit of `spec.md`, a `RATIFIED` written without a `yes`, an apply skipped) is forbidden. (`spec.md` carries its own `status: spec`; don't conflate the two.) Bypassing the gate violates the SDD state-machine contract.
- The goal block (`task_type`, `goal.outcome`, `goal.verification`, etc.) is authored in `spec.md` frontmatter, NOT in `overview.md` — writing goal block fields to `overview.md` is incorrect and those values will be ignored by `goalforge-harden` and `goalforge-execute`.
- If `spec.md` already exists at `draft`, the skill must ask the user whether to overwrite or merge — silently overwriting discards prior design decisions. An approved spec is never overwritten: it is revised through a respec proposal, which supersedes affected verified WPs in place instead of deleting their evidence.
- Goal facets left partially specified must have a corresponding entry in `## Open Questions`; an empty facet with no open question entry will not be detected here but will be surfaced (and grilled) by `goalforge-harden` — this is expected behavior, but it delays the chain unnecessarily if the spec author forgot to record the question.
- A first spec's `spec.md` is written at `draft -> spec` as the proposal; `overview.md` reaches `ready` only on ratification. A feature parked at `spec` is not decomposable: `goalforge-decompose` rejects it (it reads `overview.md` for the feature `status: ready` precondition) until the proposal is ratified.
- **Spin-off candidates during spec:** if speccing reveals an adjacent improvement worth capturing, invoke the `idea` package (mode=capture) — see `rules/common/idea-capture.md`. Don't silently absorb it into scope.
- **An unpinned cross-WP contract is a spec defect, not a decompose one.** If WP-B will read what WP-A writes, the path + schema belong in the Interface Contract *here* — leaving it for decompose forces a guess and surfaces as a pre-harden BLOCK. The spec is the single home for shared shapes.
- **A live/manual step inside a deterministic feature check** will propagate into the WP verification surfaces at decompose and BLOCK at pre-harden review. Keep the deterministic gate offline-reproducible; state live checks as a separate manual note.
