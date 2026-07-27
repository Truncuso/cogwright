---
name: goalforge-spec
description: "Run a design pass on a captured feature and produce the spec document. Reads plans/<feature>/overview.md, optionally invokes personas or architect for a multi-lens review, writes plans/<feature>/spec.md from the feature-spec template, and advances the feature status draft → ready. HUMAN-GATED: must receive explicit user approval before advancing status. Trigger: the user asks to spec, design, or elaborate on a feature that already has an overview.md (status: draft)."
metadata:
  version: 1.1.0
hooks:
  Stop:
    - hooks:
        - type: command
          command: "$HOME/.claude/scripts/skill-measure.sh goalforge-spec"
        - type: command
          command: "$HOME/.claude/hooks/skill-trace.sh goalforge-spec:stop"
---

# goalforge-spec

Reads a captured feature overview, conducts a design pass, writes `spec.md`,
and advances the feature status from `draft` to `ready`. The `draft → ready`
transition is **human-gated**: the skill halts and asks for explicit approval
before changing any `status:` field.

**Full route only.** A `route: fast` feature (overview frontmatter, stamped by
`goalforge-capture`) has no `spec.md` by design — its single WP carries the complete
goal block. Invoking goalforge-spec on a fast feature is the deliberate promotion
path (the feature outgrew the fast route — e.g. 3+ WPs or a cross-WP
contract): author the spec retroactively and flip `route: full` with a note.

Schema reference: `~/.claude/skills/goalforge/references/schema.md`.
Templates: `~/.claude/skills/goalforge/references/templates/`.

## Unattended mode (`SDD_AUTONOMY=unattended`)

When `SDD_AUTONOMY=unattended` is set (the `autopilot` driver sets it), the
`draft → ready` sign-off has no human to grant it. **Do not call `AskUserQuestion`
to wait — PARK:** write the spec and the verbatim approval prompt to a handoff and
stop (the run resumes when a human approves, or on the next `/autopilot`). The
status is **not** advanced autonomously — accepting a spec is a human commitment.
Spec *content* quality checks (personas/architect/judge) are evidence-decidable and
still run. See `~/.claude/skills/autopilot/references/autonomy-policy.md`. Unset
(`interactive`) behaviour is unchanged.

## Inputs

- `<PLANS_ROOT>/<feature>/overview.md` — must exist; `status: draft`.

## Outputs (contracted files only)

| File | Template | Status after |
|---|---|---|
| `<PLANS_ROOT>/<feature>/spec.md` | `feature-spec.md` | `spec` (own frontmatter) |
| `<PLANS_ROOT>/<feature>/overview.md` | — (update in place) | `ready` |

No other files are created or modified.

## Procedure

### Step 1 — Load overview

Read `<PLANS_ROOT>/<feature>/overview.md`. Extract:

- Problem statement.
- Goal (success criterion).
- Scope (In/Out).
- Any existing open questions or notes.

If `status:` is not `draft`, warn and ask the user to confirm before proceeding.

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
in `## Open Questions` for `goalforge-harden` — this is guidance inside the
design pass, not a step.

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

### Step 3 — HUMAN GATE: present and seek approval

Before writing any files or advancing status, present the draft spec to the
user:

```
Draft spec for <feature>:

## Goal  (task_type: <task_type>)
outcome:       <one measurable sentence>
verification:  strategy=<strategy>  check=<check>
constraints:   <list>
boundaries:    <list>
iteration:     <iteration_policy>
blocked_stop:  <blocked_stop>

## Design
<approach summary>

## Interface Contract
<contracts summary>

## Non-Goals
<exclusions>

## Open Questions
<unresolved items>

Approve this spec and advance status (draft → ready)? [yes/no/revise]
```

Present the goal block first — it is the contract the rest of the spec serves.
If any goal facet is vague or unset (and not a deliberate open question), refine
it in Step 2b before re-presenting rather than asking the user to approve an
under-specified goal.

**Do not proceed until the user replies with an affirmative.** If the user
requests revisions, iterate the design pass (Step 2) and re-present. If the
user declines, exit without writing any files or changing any status.

This gate enforces the `draft → ready` human-gated transition for the feature
(§2 Status state machine; goalforge-spec advances overview.md, not spec.md).

### Step 4 — Stamp `spec.md`

After user approval, create `<PLANS_ROOT>/<feature>/spec.md` from the
`feature-spec.md` template:

```yaml
name: <feature>-spec
title: <human title> — spec
status: spec
created: <today YYYY-MM-DD>
updated: <today YYYY-MM-DD>
feature: <feature>
```

Populate all body sections from the approved design pass output.

### Step 5 — Advance `overview.md` status

Update `<PLANS_ROOT>/<feature>/overview.md` in place:

- Set `status: ready`.
- Set `updated: <today YYYY-MM-DD>`.
- Add the spec link to the Links section if not already present.

Do not modify any other frontmatter fields.

### Step 6 — Report

```
Updated: <PLANS_ROOT>/<feature>/overview.md  (status: draft → ready)
Created: <PLANS_ROOT>/<feature>/spec.md      (status: spec)
Next: run goalforge-decompose to break the spec into work packages.
```

## Drafting discipline

Four rules govern how the spec is drafted (additive discipline — they do not
change the human gate or any status transition):

1. **Research-first** — before fixing an approach, check what already exists
   (prior art, libraries, the repo's own patterns). Do not invent where a known
   solution fits.
2. **Hard-bets-first** — surface the hard-to-reverse decisions early and make
   them explicit in the spec; when two or more such approaches compete, that is
   the `goalforge-arbiter` trigger at harden.
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

- **Never** advance status without explicit human approval (Step 3 gate).
- **Never** create WP folders or task files — those belong to `goalforge-decompose`.
- **Never** modify `todo.md` or any WP files.
- Write only the two contracted files above.
- If `spec.md` already exists, ask the user whether to overwrite or merge.

## Human-gate rationale

`draft → spec` is one of two human-gated transitions in the SDD state machine
(§2 of spec.md). Automatic advancement would bypass design review and allow
under-specified work to reach execution. The gate is a presentation + explicit
approval, not just a confirmation dialog — the user must see the full draft
before approving.

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

- The human-gated transition protected here is `overview.md` advancing OUT of `draft` (to `ready`, per this skill's Step 3 gate + Outputs table) — it NEVER happens without explicit approval: not on re-run, not if `spec.md` already exists, not via any flag. (`spec.md` carries its own `status: spec`; don't conflate the two.) Bypassing the gate violates the SDD state-machine contract.
- The goal block (`task_type`, `goal.outcome`, `goal.verification`, etc.) is authored in `spec.md` frontmatter, NOT in `overview.md` — writing goal block fields to `overview.md` is incorrect and those values will be ignored by `goalforge-harden` and `goalforge-execute`.
- If `spec.md` already exists, the skill must ask the user whether to overwrite or merge — silently overwriting a previously approved spec discards prior design decisions; silently skipping leaves the overview in a potentially inconsistent state.
- Goal facets left partially specified must have a corresponding entry in `## Open Questions`; an empty facet with no open question entry will not be detected here but will be surfaced (and grilled) by `goalforge-harden` — this is expected behavior, but it delays the chain unnecessarily if the spec author forgot to record the question.
- Both files (`spec.md` and the updated `overview.md`) are written only after user approval; a partial write that creates `spec.md` but does not update `overview.md` status leaves the chain in an inconsistent state that `goalforge-decompose` will reject (it reads `overview.md` for the feature `status: ready` precondition).
- **Spin-off candidates during spec:** if speccing reveals an adjacent improvement worth capturing, invoke the `idea` package (mode=capture) — see `rules/common/idea-capture.md`. Don't silently absorb it into scope.
- **An unpinned cross-WP contract is a spec defect, not a decompose one.** If WP-B will read what WP-A writes, the path + schema belong in the Interface Contract *here* — leaving it for decompose forces a guess and surfaces as a pre-harden BLOCK. The spec is the single home for shared shapes.
- **A live/manual step inside a deterministic feature check** will propagate into the WP verification surfaces at decompose and BLOCK at pre-harden review. Keep the deterministic gate offline-reproducible; state live checks as a separate manual note.
