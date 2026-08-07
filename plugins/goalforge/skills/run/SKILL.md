---
name: goalforge-run
description: "Orchestrator for the SDD planning chain, route-aware over the canonical route enum one-go|fast|standard|wave: standard = capture → spec → decompose → harden → execute → verify; fast = capture → add-wp → deterministic gates → execute → verify (route: read from the feature overview frontmatter, stamped by goalforge-capture). Routes the entry commands /spec /plan /implement /verify to the correct chain step, resumes mid-chain by reading the current WP status:, and supports --dry-run. Invoke goalforge-run when a user runs any of the four entry commands or when the chain must resume from a known WP stage. SKIP for single-step work: invoke the child skill directly (goalforge-capture, goalforge-spec, goalforge-decompose, goalforge-harden, goalforge-execute, goalforge-verify)."
metadata:
  skill-kind: preference
  version: 1.1.0
---

# goalforge-run — SDD Orchestrator

## Location

`goalforge-run` lives at `~/.claude/skills/goalforge/run/` — the PRIVATE `run/`
orchestrator child of the local goalforge v2 package (source of truth per
wp-13-local-rename). Its child skills (`goalforge-capture`, `goalforge-spec`,
`goalforge-decompose`, `goalforge-harden`, `goalforge-execute`,
`goalforge-verify`) are nested siblings under `~/.claude/skills/goalforge/`,
alongside the `sdd` local redirect hub. The orchestrator is invoked by name
(`goalforge-run` / `skill-router goalforge-run`), so its directory location does
not affect how the slash commands or the router resolve it.

## Chain

`chain.yaml` (sibling file) declares the sequence. `goalforge-run` does not
autonomously reorder or extend the chain; any modification goes through
`/skill-improve`.

## Route awareness (canonical route enum)

Routes are the canonical enum `one-go | fast | standard | wave`. The chain
adapts to the goal's size: `goalforge-run` reads the feature overview's `route:`
frontmatter (stamped by `goalforge-capture` via `goalforge-route.sh` — capture is the
routing home; absent ⇒ `standard`) and skips the steps marked
`when_route: standard` in `chain.yaml` for a `route: fast` feature:

- **`standard`** — the six-step chain, unchanged.
- **`fast`** — capture → `goalforge-decompose --add-wp` (ONE WP, complete
  self-contained goal block, no `spec.md`) → deterministic gates
  (`goalforge-validate` + `hooks/goalforge-open-questions-gate.sh --check` +
  `goalforge-wp-complexity.sh` verdict `simple`, severity ≤ MEDIUM, non-migration)
  → `goalforge-transition.sh <wp> ready --mode auto` → execute → verify.
- **Escalation:** ANY fast-gate trip leaves the WP at `spec` and re-enters the
  chain at the harden step (full treatment). The gates, not the classifier,
  are the safety net.
- **Never skipped:** `goalforge-verify` — every route ends at the single semantic
  gate; the outcome→verification contract is route-independent.

Full fast-path runbook: `goalforge-capture` §Fast path.

## Wave route — planning-fan-out choreography (OWNER)

`run/SKILL.md` is the OWNER of the wave-orchestration section per spec pin #8.
`goalforge-capture` only *stamps* the `execution_plan` for a `route: wave`
feature; it does not own or duplicate the choreography described here.

The `wave` route orchestrates a **multi-feature planning run** — several
features specced in one fan-out — through an **active four-stage
choreography**, executed in this order:

1. **explore fan-out** — a fan-out of explorer subagents, one per candidate
   feature, each mapping its feature's problem space and returning findings as
   DATA (no spec authored yet).
2. **parallel spec authors** — one spec-author subagent per feature, dispatched
   concurrently, each writing only within its own feature directory under an
   **owned-set** declared in its dispatch brief.
3. **cross-spec judge** — a single judge over the *whole set* of authored specs,
   checking cross-feature consistency, overlap, and contradiction.
4. **fixer** — applies the cross-spec judge's findings, reconciling the specs
   the judge flagged.

### Cold dispatch for the cross-spec judge

The **cross-spec judge runs cold** — a fresh subagent with no shared
conversation state — per the dispatch trust boundary: it consumes the authored
specs as untrusted DATA and returns a verdict the orchestrator parses, never
executes. The deferred cold per-spec tier-1 audits (below) carry the **same
cold requirement** when later enabled.

### execution_plan wiring

For a `route: wave` feature, `goalforge-capture` stamps `execution_plan.steps`
to exactly this four-stage sequence, in order:

```
execution_plan:
  route: wave
  steps:
    - explore-fan-out
    - parallel-spec-authors
    - cross-spec-judge
    - fixer
```

### File-ownership discipline (planning-wave)

Concurrent spec authors never collide because their **owned-sets are
pairwise-disjoint** and each writes only within its own per-feature directory
(per-feature-dir writes are naturally disjoint). This is enforced at
**dispatch-brief-authoring time** — an overlapping owned-set between two agents
is a malformed wave and must be detectable (the pairwise-disjointness check
lives in the wave-route brief instance, task-02). Safety is **declaration-time
only** (`[risk-accepted]`): no runtime write guard and no worktrees for
planning-wave spec authors. The owned-set / off-limits fields, the ownership
rule, and the return-as-DATA contract are defined once in
`skills/goalforge/references/dispatch-template.md` and are **not duplicated
here** — the wave-route brief references that contract by path.

### Worked example — a 2-feature wave

Walking the synthetic 2-feature fixture (`feature-a`, `feature-b`) through the
four stages:

1. **explore fan-out** — two explorer subagents fire in parallel, one per
   feature. Each returns a problem-space map as DATA.
2. **parallel spec authors** — two spec-author subagents fire concurrently.
   Author A's brief declares `owned: [plans/feature-a/**]`; author B's declares
   `owned: [plans/feature-b/**]`. The two owned-sets are pairwise-disjoint (no
   path appears in both), so the wave is well-formed. Each author writes only
   its own `spec.md`. The ownership/return-as-DATA contract each brief obeys is
   the one in `skills/goalforge/references/dispatch-template.md` (referenced by
   path, no contract text copied).
3. **cross-spec judge** — one cold judge reads both authored specs and checks
   for cross-feature overlap or contradiction (e.g. both features claiming the
   same module), returning a findings verdict as DATA.
4. **fixer** — applies the judge's findings, editing only the specs the judge
   flagged, then the wave is complete.

### Optional extensions (deferred)

Two further stages are **documented but not wired** into the active
choreography or the fixtures, explicitly deferred until the first real
multi-feature wave run (A-TRIM):

- **cold per-spec tier-1 audits** — a per-feature cold tier-1 review of each
  authored spec (carries the same cold-dispatch requirement as the cross-spec
  judge when enabled).
- **parallel hygiene agent** — a concurrent agent enforcing cross-feature
  naming/structure hygiene over the wave set.

Do not add these to `execution_plan.steps` or assert them in fixtures until the
first real wave run motivates them.

### Planning-wave vs execute-wave (do not conflate)

This section describes the **planning-wave**: a *spec-author fan-out* coordinated
by pairwise-disjoint owned-sets, a **feature-level** primitive distinct from
wp-04 within-feature `execution_plan.parallel`. It is separate from the
**execute-wave** — the execute-stage worktree isolation owned by
`execute/SKILL.md` (§ parallel tasks use dedicated worktrees), which handles
execute-stage filesystem-collision safety for parallel *task* execution.
Owned-set discipline coordinates planning-wave; worktree isolation coordinates
execute-wave. The two must not be conflated.

## Unattended mode (`SDD_AUTONOMY=unattended`)

When `SDD_AUTONOMY=unattended` is set (the `autopilot` driver sets it), `goalforge-run`
and the child skills run with **no human to answer gates**. At every human-gated
boundary (`draft → ready` spec sign-off, `hardened → ready` harden sign-off) and at
any hard wall that would call `AskUserQuestion`, **do not block — PARK:** record the
verbatim gate/blocker and stop cleanly so the run resumes later. This never
*bypasses* a human gate (the gated status is not advanced autonomously); it stops
and hands off. Classification of which gates park vs. auto-resolve lives in
`~/.claude/skills/autopilot/references/autonomy-policy.md`. With the variable unset
(`interactive`, the default), gate behaviour is unchanged. Note: `goalforge-run` must
never invoke `autopilot` (the driver sits above the chain — forbidden back-edge).

## Task-type awareness

The chain is a general goal-driven workflow, not a code-only pipeline. A feature
or WP declares a `task_type` — `code | research | ops | writing | optimization |
analysis` — which the chain carries through to dispatch and evaluator-strategy
resolution:

- **Dispatch:** non-code task types route to a specialist via `by_task_type` in
  `specialist-map.yaml` (e.g. `research → research-analyst`, `ops →
  devops-engineer`); `writing` is kind-dependent and resolves via a second-level
  `by_writing_kind` map (scientific/research/docs), with an untagged writing WP
  escalating so the right producer is chosen. See `goalforge-execute` Step 4.
- **Strategy:** `task_type` supplies the *default* verification strategy
  (`default_strategy_for` in `goalforge-goal-eval.py`) when a WP omits one.

**Code is the primary, best-supported path** — the richest specialist coverage,
reviewers, and build/verify tooling target code. Non-code task types are
first-class but lean on the goal block's `verification` (judge/human/numeric)
rather than a compiler. An explicit WP `strategy:` always wins over the
task-type default.

## Entry command routing

The four entry commands (`/spec /plan /implement /verify`) are rewired to the
chain in WP-07. The intended mapping (documented here; command files are edited
in WP-07, not here):

| Command      | Entry step    | Child skill    | Notes                         |
|--------------|---------------|----------------|-------------------------------|
| `/spec`      | `capture`     | `goalforge-capture`  | Starts chain; elicits raw input, writes `overview.md` |
| `/plan`      | `decompose`   | `goalforge-decompose`| Expects feature `status: ready`; breaks spec into WPs  |
| `/implement` | `execute`     | `goalforge-execute`  | Expects WP `status: ready`; runs execute sub-cycle    |
| `/verify`    | `verify`      | `goalforge-verify`   | Expects WP `status: executing`; runs verification     |

`goalforge-run` resolves which step to enter by checking the target WP's (or
feature's) `status:` frontmatter field before dispatching.

## Resume mid-chain

When invoked without an explicit entry command, `goalforge-run` reads the current
WP's `status:` frontmatter and resumes at the next actionable step:

| Current `status:` | Next step  | Child skill    | Gate           |
|-------------------|------------|----------------|----------------|
| `draft`           | `spec`     | `goalforge-spec`     | human-gated    |
| `ready` (feature) | `decompose`| `goalforge-decompose`| automatic      |
| `hardened`        | `harden`→`ready` | `goalforge-harden` | human-gated  |
| `ready` (WP)      | `execute`  | `goalforge-execute`  | automatic      |
| `executing`       | `verify`   | `goalforge-verify`   | automatic      |
| `verified`        | —          | —              | chain complete |
| `archived`        | —          | —              | terminal; halt |

Human-gated transitions (`draft → ready` at the spec step; `hardened →
ready` at the harden step) are never advanced without explicit user approval —
with one recorded exception: `hardened → ready` auto-advances under the
signal-scoped rule (`simple` + severity ≤ MEDIUM + non-migration, `--mode
auto`; goalforge-harden Step 2.3 / state-machine.md §Policy). Outside that class,
`goalforge-run` calls `AskUserQuestion` at each gated boundary. On the fast route
the WP advances `spec → ready` through the deterministic gates instead (a
non-human-gated edge; same signal-scoped conditions as policy guard).

## `--dry-run` semantics

`skill-router goalforge-run --dry-run` (or passing `--dry-run` when invoking
`goalforge-run` directly):

1. Reads `chain.yaml` and resolves every step's `skill` against
   `~/.claude/skills/**/<name>/SKILL.md`.
2. For each step, prints:
   - step name
   - skill name + resolved path
   - status precondition required to enter
   - whether the precondition is currently satisfied (if a target WP is provided)
3. Reports any unresolved skill as an error.
4. **No side effects**: no files written, no subagents dispatched, no status
   fields mutated.

## Status machine (reference)

Full schema: `~/.claude/skills/goalforge/references/schema.md`.

WP stage vocabulary used as preconditions in `chain.yaml`:

```
draft → spec → hardened → ready → executing → verified → archived
```

`draft → ready` (feature, via goalforge-spec) and `hardened → ready` (WP, via goalforge-harden) are human-gated
(the latter with the signal-scoped auto-advance exception — state-machine.md §Policy).
`archived` is terminal; never entered automatically. A `route: fast` WP takes the
legal `spec → ready` edge via the deterministic gates instead of harden.

## Shared references

- Schema + frontmatter: `~/.claude/skills/goalforge/references/schema.md`
- Templates: `~/.claude/skills/goalforge/references/templates/`
- Specialist routing: `~/.claude/skills/goalforge/references/specialist-map.yaml`
- PLANS_ROOT resolution: `~/.claude/skills/goalforge/references/schema.md`
  §PLANS_ROOT resolution (env `SDD_PLANS_DIR` → project git-root `plans/` →
  global `~/.claude/plans/`)

## Gotchas

- Resume routing keys entirely off the target's on-disk `status:` — a value matching no `chain.yaml` precondition (a hand-edited label, schema drift, or a terminal `verified`/`archived`) leaves goalforge-run with no step to enter, so it halts rather than guessing. Don't hand-edit `status:` to force re-entry; set it to the exact precondition the intended step expects.
- `--dry-run` must have zero side effects: no files written, no subagents dispatched, no status fields mutated. A dry-run that modifies state makes testing the chain impossible and breaks CI verification.
- Resume reads the CURRENT on-disk `status:` at invocation — if a parallel session or an external committer advanced the WP between your last step and this resume, goalforge-run enters at the NEW status and can skip the step you expected. Re-check `status:` before resuming a long-suspended chain.
- `chain.yaml` steps resolve their `skill:` against installed skills only at RUNTIME — a step naming a renamed, uninstalled, or typo'd skill fails when the chain REACHES it, not at load. Run `scripts/goalforge-router.sh --dry-run <feature>` after any chain.yaml edit to surface an UNRESOLVED step up front.
- The entry commands (`/spec`, `/plan`, `/implement`, `/verify`) call their child skills **directly** (e.g. `commands/spec.md` → `goalforge-capture`/`goalforge-spec`) — they do NOT route through `goalforge-run`, so its resume + gate logic is bypassed when you use the slash commands. Invoke `goalforge-run` (or `skill-router goalforge-run`) explicitly when you need the orchestrator.
