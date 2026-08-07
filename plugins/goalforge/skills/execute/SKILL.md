---
name: goalforge-execute
description: "Execute all tasks in a WP at status `ready`, running the per-task clean → deterministic-eval → commit sub-cycle (each task reaches the interim status `implemented`). The expensive semantic review + simplify are amortized to the WP boundary (goalforge-verify), not run per task. TRIGGER: /goalforge-execute <wp-path> or when goalforge-run reaches the execute step in the chain."
metadata:
  skill-kind: preference
  version: 2.0.0
---

# SDD Execute

## Plans root

`<wp-path>` points to a WP folder in `<PLANS_ROOT>/<feature>/`. Resolve
`<PLANS_ROOT>` per `${CLAUDE_PLUGIN_ROOT}/references/schema.md` §PLANS_ROOT
resolution (env `SDD_PLANS_DIR` → project git-root `plans/` → global
`~/.claude/plans/`).

## Contract

Reads a WP at `status: ready` and drives `ready → executing`; `goalforge-verify` writes
`executing → verified` after the WP-level semantic gate. **Tasks reach the
interim status `implemented`** here (deterministic eval passed + committed) —
*not* `verified`. `verified` is quality-signed-off and is
**written only at the WP gate** by `goalforge-verify`, which flips each `implemented`
task to `verified` as it finalizes. State-machine invariants (schema.md §state machine): `executing` ⇒ ≥1
task has a `checkpoint` block; a task reaches `implemented` after its
deterministic eval (Step 6) passes and it is committed (Step 8); `verified` ⇒ all
child tasks `verified` + `findings.md` exists.

## Unattended mode

Under `SDD_AUTONOMY=unattended` (the `autopilot` driver), every point that would
escalate via `AskUserQuestion` instead PARKs — append the blocker to `findings.md`
and stop cleanly; status is never advanced past a blocker. Detail:
`references/autonomy.md`.

## Goal layer (the simulated `/goal` loop)

Steps 1–10 run inside an **outer goal-completion loop** that simulates native
`/goal` (design §4). Split of labour:

- **The script (`goalforge-goal-eval`) is pure.** It decides `deterministic`/`numeric`
  goals itself (binary exit) and, for `judge`/`human`, **returns a directive**
  instead of acting. `resolve_effective_goal` (same module) is the single owner of
  goal cascade + legacy fallback.
- **This agent performs any dispatch** — a script cannot invoke `judge` or run
  `AskUserQuestion`.

Two bounded caps, **independent of** each other:

- **Inner** retry cap per task (Step 6).
- **Outer** `outer_max_iter`, **conditioned** on the goal strategy:
  `deterministic` → run the body once then gate (`outer_max_iter = 1`; the WP gate
  is a settled binary once every task is `implemented`); `numeric` / `judge` →
  full closed loop (default 3, Principle 6 — **Do not collapse** `numeric`);
  `human` → a non-blocking gate that parks, does not iterate.

**Single status-advance path:** the outer gate never writes `status: verified` —
it only decides whether to invoke `goalforge-verify` (Step 10), the sole authority for
`executing → verified`.

## Files read / written

| File | Access |
|------|--------|
| `<wp>/overview.md` | read + WP `status:`/`stage_updated:` via `goalforge-transition.sh`; `## Tasks` status cell written with the task's frontmatter (Step 8) |
| `<wp>/task-*.md` | read + write (`status:`, `checkpoint:`, `commit:`) |
| `<wp>/findings.md` | read (must exist — created by goalforge-harden); append on blocker |
| `<feature>/todo.md` | write via `goalforge-rollup.sh` (per task — Step 8.5 — and at the WP boundary — Step 10) |

---

## Sub-cycle procedure

### Step 0 — Entry

0. **Prototype-register WP?** If frontmatter carries `register: prototype`
   (schema.md §WP frontmatter), the WP is a declared spike — fidelity rung 3,
   `${CLAUDE_PLUGIN_ROOT}/references/fidelity.md` — whose task loop
   collapses to its single task (goalforge-decompose stamps prototype WPs with
   exactly one task for this reason): after the status advance below, run the
   `prototype` skill (one design question + success criteria from the goal
   block; spike code in a worktree, never committed) and commit the findings
   doc (LOGIC.md / UI.md / PERF.md content, filed per the task spec) as that
   task's commit — the task reaches `implemented` through Steps 6–8 like any
   other, so Step 10's preconditions (all tasks `implemented`, `commit:`
   backfill) hold, and goalforge-verify's cumulative-diff review covers a docs-only
   diff. Also write the WP-level `findings.md` (goalforge-verify requires it). Goal
   verdict via the WP's declared `judge`/`human` strategy over the findings —
   never deterministic-on-spike-code.
1. Read `<wp>/overview.md`.
2. **Resume check first:** if `status:` is already `executing`, do **not**
   transition again — skip to **Step 9 — Resume**. (The transition mechanism
   rejects `executing → executing` as illegal, so this check must precede the
   advance.)
3. Otherwise assert `status: ready` (abort if neither `ready` nor `executing`),
   then advance `ready → executing` through `goalforge-transition.sh` — the single
   writer of WP `status:` (writes `status:` + `stage_updated:`, appends the
   provenance ledger row, refreshes status cells + feature `todo.md`). Pass
   `--from ready` as an optimistic-lock re-check; never hand-edit `status:` or a
   status cell:
   ```bash
   bash ${CLAUDE_PLUGIN_ROOT}/scripts/goalforge-transition.sh <wp> executing \
     --from ready --reason "goalforge-execute entry" --actor goalforge-execute
   ```

### Step 0b — Resolve the effective goal

Resolve the WP's effective goal **once at entry** — the single source of truth for
the outer loop. Call the WP-02 resolver; `resolve_effective_goal` is the sole
owner of cascade + legacy fallback, so do NOT re-derive them here:

```python
# resolve_effective_goal is the sole back-compat owner (WP-02).
from goalforge_goal_eval import resolve_effective_goal   # loaded via importlib
effective_goal = resolve_effective_goal(wp_fm, spec_fm=<inherited spec or None>)
# → {outcome, verification:{strategy,check}, constraints, boundaries,
#    iteration_policy, blocked_stop, task_type}
```

- If the WP sets `inherits_from: <feature-slug>` and that feature's `spec.md`
  exists, pass its frontmatter as `spec_fm` (per-field cascade: outcome/
  verification never inherited; scalars override; lists union-with-dedupe).
- A WP with no goal block falls back to `strategy: deterministic` (legacy
  `## Goal` + task `verify:`), handled inside the resolver — do not special-case it.

Carry `effective_goal` and an empty `reason_feedback` into the outer loop.

**Assumption recheck (preflight — non-gating).** Re-run the WP's recorded
`## Assumptions` checks (set at harden) before building on them:

```bash
bash ${CLAUDE_PLUGIN_ROOT}/scripts/goalforge-assumption-recheck.sh <wp>/overview.md
```

On a mismatch it writes a keyed, idempotent row to `<wp>/findings.md`
(`## [DATE] Assumption mismatch: <key>`). **Do NOT hard-fail** — it detects and
logs; the decision to proceed or stop is operator judgment. Surface any logged
mismatch and continue unless the operator stops.

> Trust boundary: the assumption `check` commands are author-written to run here —
> NOT the untrusted task `verify:` string (verb-linted, never run).

### Outer goal-completion loop (wraps Steps 2–9)

```
reason_feedback = ""
goal_met = False
# Strategy-conditioned cap: deterministic settles in one pass; numeric/judge iterate.
outer_max_iter = 1 if effective_goal.verification.strategy == "deterministic" else 3
for outer_iter in 1..outer_max_iter:
    run Steps 2–9 (the sub-cycle, incl. the inner retry cap)
        # a not-met re-entry re-enters Step 2 and RESPECTS resume idempotency
        # (Step 9) — it NEVER re-runs an implemented/verified task unless Step 9.5
        # re-opened it to pending. reason_feedback (if set) guides implement.
    verdict = evaluate(effective_goal)        # PURE in-process call → {met, reason, strategy, directive?}
    verdict = act_on_directive(verdict)       # Step 9b — agent dispatches judge/human;
                                              # post: paused always bool; met concrete for non-human
    if verdict.paused: exit                   # human gate written to findings.md → resume next invocation
    if verdict.met is True: goal_met = True; break
    reason_feedback = verdict.reason          # carry forward as next-iter guidance
    reopen_task_from_reason(verdict.reason)   # Step 9.5 — map reason→task, reset to pending (bounded),
                                              # or PARK / goalforge-redecompose if none maps

if not goal_met:                              # loop exhausted without meeting the goal
    # never silent-pass: exhausting outer_max_iter IS the blocked_stop condition
    append blocker to findings.md (effective_goal.blocked_stop + last reason_feedback)
    escalate via AskUserQuestion; exit        # do NOT advance status
# Step 10 runs only when goal_met is True (and every task is implemented).
```

> A hard blocker raised *inside* Steps 2–9 (dependency deadlock at Step 2, inner
> retry cap at Step 6) already escalates via `AskUserQuestion` and exits within
> the sub-cycle. The post-loop block above is the
> *goal-not-met-after-`outer_max_iter`* case. `outer_max_iter` is **independent
> of** the inner retry cap; the outer loop only adds re-entry — nothing inside
> Steps 2–9 changes.

### Step 1 — Ensure clean working tree

- Run `git status --porcelain`; if non-empty, abort and prompt the user to commit
  or stash pending changes before re-running.
- Exception: parallel tasks use dedicated worktrees (Step 3); the main tree must
  still be clean at wave-launch.

### Step 2 — Pick next task

1. Filter `task-*.md` with frontmatter `status: pending`.
2. Keep only those where every slug in `depends_on` is `implemented` or
   `verified` (or `depends_on` is empty) — an `implemented` predecessor (code
   committed, deterministic eval passed) satisfies an intra-WP dependency; it need
   not wait for the WP-gate promotion.
3. Separate `parallel: true` candidates into a **wave** (Step 3); run a single
   `parallel: false` task sequentially.
4. If no candidate remains but some `pending` tasks have unsatisfied `depends_on`,
   append a blocker to `findings.md` and escalate via `AskUserQuestion`
   (dependency deadlock).
5. If all tasks are `implemented`/`verified`, go to **Step 10 — WP exit**.

### Step 2b — Gated brief authoring (pre-dispatch)

Applies only to a task whose frontmatter `complexity` is in {medium,high}
(read from the **task** frontmatter, NOT `goalforge-wp-complexity.sh`); a
low-complexity task skips briefing entirely and proceeds to Step 3/4/5 unchanged.

For a gated task at `status: pending`:

1. Invoke the PRIVATE brief child skill `goalforge-brief` (wp-06 task-01,
   `${CLAUDE_PLUGIN_ROOT}/skills/brief/`) once to author `<wp>/brief-task-NN.md` —
   a delta-only artifact (References/Context/Skeleton + a pointer to `task-NN.md`;
   frontmatter is exactly `{task, created, brief_tier}`). The brief is
   **immutable** after authoring.
2. Advance the task `pending → briefed` via the **sanctioned Bash-path status
   writer** — a python-via-Bash atomic frontmatter status write following the
   `goalforge-transition.sh` write pattern (mktemp → `os.replace`), which the
   wp-08 single-writer hook permits while it BLOCKS an Edit-tool status write.
   **NEVER** use the Edit tool to write task status. Update the task's
   `overview.md` `## Tasks` Status cell to `briefed` in the same sanctioned write.

An already-`briefed` task (crash-recovery re-entry) is not re-briefed — the
immutable brief already exists; proceed to Step 2c.

### Step 2c — Brief staleness re-validation (pre-consumption)

Before a cheap tier consumes a `briefed` task's brief, re-validate the brief
against current repo state (the brief may have been authored against a since-changed
file or goal):

```bash
bash ${CLAUDE_PLUGIN_ROOT}/skills/execute/brief-staleness.sh <wp-dir> <task-slug>
```

The script compares each `## References` anchor — a file anchor's recorded git blob
SHA against `git hash-object <file>`, and the `goal:` anchor's recorded WP goal-hash
against `goalforge-goal-hash.sh <wp-dir>`:

- **Exit 0 (FRESH)** — every anchor matches; proceed to Step 3/4/5 and consume the
  brief unchanged. The immutable brief is left untouched — **no `staleness_checked`
  flag is written back** (A-FOLD).
- **Exit 3 (STALE)** — at least one anchor drifted; the script has already recorded
  a **re-brief request** in the task's `## Checkpoint (goalforge-execute state)`
  block (`rebrief_requested: true`). **Do NOT consume the stale brief.** There is
  **no automated re-brief loop this WP** — surface the re-brief request (append to
  `findings.md`; under `SDD_AUTONOMY=unattended` PARK per the Unattended-mode rule)
  and leave the task for a re-brief pass. The brief is never mutated by this step.

### Step 3 — Wave dispatch (parallel tasks)

**Dispatch granularity (cohesion gate).** Before dispatching, decide the grain —
fewer subagents when the work is cohesive and low-risk, one-per-task when it is
not:

- **Task group → one subagent** when the candidate tasks share files/module,
  every task's `complexity ≤ medium`, and none triggers a blast-radius hit
  (`blast_radius` in `goalforge-pick-agent.py`). The group's tasks go to a single
  subagent that implements them in sequence.
- **Whole-WP → one subagent** for a small WP (≤ 3 tasks) meeting the same
  conditions (shared cohesion, complexity ≤ medium, no blast radius).
- **Per-task dispatch** otherwise — retained for high-risk tasks (blast-radius
  hit or `complexity: high`) and for a heterogeneous set whose tasks resolve to
  different specialists.

A grouped dispatch still **commits per task where feasible** (the
one-conventional-commit-per-task discipline below is unchanged) and the semantic
review stays **amortized at the WP boundary** (`goalforge-verify`) — grouping changes
dispatch fan-out, not the commit or review granularity.

Group-edge rules (deterministic):
- **Mixed tiers in a group** → the group dispatches at the **max tier of its
  members** (never dispatch a member below its own resolved tier).
- **Blast radius for a group:** the *sensitive-path signals*
  (auth/schema/migration/…) are evaluated on the **union** of touched files
  (a sensitive path is absolute); the *3+-file count threshold* is evaluated
  **per member task** — on the union it would trip for nearly every group and
  gut the grouping savings. The WP-boundary review covers the cumulative diff
  regardless.

For a candidate set with `parallel: true` tasks (per-task or per the grouping
above):

1. For each, call `EnterWorktree` to create an isolated git worktree; record its
   path in the task's `checkpoint.worktree` before dispatch.
2. Dispatch **all wave tasks in a single batched message** via multiple Agent
   calls (`superpowers:dispatching-parallel-agents`). Each subagent receives: the
   task spec (goal, steps, verify command), its worktree path
   (`superpowers:using-git-worktrees`), and the resolved
   `(specialist, model, effort, route)` from Step 4 (model + effort stated
   explicitly, never left to agent `.md` defaults). **Surface choice:** the Agent
   tool inherits session effort — when the wave's resolved efforts differ from
   the session (or mix, e.g. `opus@low` implementers alongside an `opus@high`
   gate), dispatch via the **Workflow tool** instead (`opts.model` +
   `opts.effort` per agent); see `references/dispatch-resolution.md` §Dispatch
   surface.
3. Wait for all subagents to return.
4. Merge each worktree back to the main branch — fast-forward on a clean merge; on
   a conflict **resolve** it (**do not discard** either side, per CLAUDE.md
   risky-action policy) and **Record the resolution in** `findings.md`. Call
   `ExitWorktree` per worktree after merge.
5. Continue to Step 5 (eval pass) for each task in the wave.

Sequential tasks (`parallel: false`) run in the main tree; omit
EnterWorktree/ExitWorktree.

### Step 4 — Dispatch resolution (pick-agent)

Call `pick_agent(task_frontmatter, touched_files, specialist_map, discover=…,
ollama_health=…)` from `${CLAUDE_PLUGIN_ROOT}/scripts/goalforge-pick-agent.py` →
`{specialist, model, route, discovered_by}` (optionally `proposed_map_entry`).

**Injected callables:** `discover` (a `general-purpose` Sonnet subagent that names
the fitting specialist + estimates complexity low|medium|high) and `ollama_health`
(the `ollama-dispatch` reachability check).

**Resolution order** (module-enforced): `by_tag` → `by_task_type` (incl. the
`writing` → `by_writing_kind` sub-map) → `by_extension` → `discover` →
`EscalationRequired` via `AskUserQuestion`. **No silent** hard default. The
evaluator *strategy* is resolved separately by the WP-02 router — `pick_agent`
selects the *specialist*, never the strategy.

**Model + effort:** from the **canonical role→tier map** (`goalforge-pick-agent.py`,
`resolve_role_tier`), then instantiated to an explicit `{model, effort}` via
`tier_to_dispatch`/`resolve_dispatch` — values live in
`references/dispatch-resolution.md` §Model tier + effort, do not restate them
here. The `implement` role is **complexity-driven**, so the
discovery callable supplies the `complexity` estimate when frontmatter omits it;
**blast radius** (auth/schema/migration/exported-API/3+ files) deterministically
forces the high tier (→ opus@high). Every brief states model **and** effort
explicitly — never left to the agent's `.md` frontmatter defaults. **No silent
fallback** — missing complexity/role/profile raises `EscalationRequired`.

**Route:** `api` (default) or `ollama` (needs a passing health check; failure
escalates — no silent API fallback). Cache the resolved `{specialist, model,
effort, route, discovered_by}` in the task `checkpoint` before dispatch; append any
`proposed_map_entry` to `findings.md` for human review (do not auto-merge).

Full resolution order, `writing_kind`/non-code routes, and autonomy-profile
tiers: `references/dispatch-resolution.md`.

### Step 5 — Dispatch subagent

Delegate code-writing to the `implement` skill. **Do NOT reimplement**
`implement`'s logic here — invoke it by name and let it run. Pass:

- Task spec (goal, steps, `verify:` command).
- Working directory (main tree or worktree path).
- Resolved specialist hint + model + effort from Step 4.
- **`use_testing` hint (goal-predicated).** Evaluate
  `should_invoke_testing(effective_goal)` (the Step 0b effective goal) via
  `from goalforge_goal_eval import should_invoke_testing` — the predicate has ONE home
  in `goalforge-goal-eval.py`, not here. It returns `True` when the WP is
  `task_type == 'code'` **AND** `verification.strategy == 'deterministic'`; then
  pass `use_testing: true` so `implement` routes test authoring through
  `testing:write`/`update`. When `False`, pass **no** hint — the dispatch is
  byte-identical to today. The guard is additive and goal-predicated; `implement`
  stays goal-agnostic and never re-derives `effective_goal`.

**doc-check (pre-coding convention).** Before writing code against anything
external — a third-party API, a versioned package, a provider with quotas/limits —
do a quick docs/web-search pass to confirm current signatures, the pinned
version's behavior, and provider limits. Cheap up front; prevents coding against a
stale or imagined interface. Pass this to `implement` for any task touching
external surfaces.

**premise-check (blocked-return convention).** The brief MUST instruct the
worker: when the task's premise fails against real repo state — a referenced
symbol/signature/file the task assumes does not exist, an assumed invariant does
not hold, or a prerequisite edit was never made — RETURN BLOCKED naming the
exact `file:line` site and the unmet premise, rather than improvising a
workaround, widening scope, or shipping a false-green edit. A blocked return is
a first-class success outcome, not a failure to route around. On such a return,
append the named site + unmet premise to `findings.md` as a blocker (same trail
as the outer-loop `blocked_stop` case) and leave task status unadvanced — never
mark a premise-blocked task implemented. Pass this to `implement` for every
dispatched task.

After `implement` returns, write the checkpoint immediately (Step 6b).

### Step 6 — Evaluation pass (deterministic only)

Run the task's **deterministic** verification suite — the cheap
early-error-detection + recovery tier, NOT semantic review (review/simplify/
second-opinion are amortized to the WP boundary, Step 7 / `goalforge-verify`):

1. Execute the task's `verify:` command exactly as written in frontmatter.
2. Run **lint** diff-scoped to the files this task touched (`eslint <files>`,
   `ruff <files>`, `cargo clippy` on the touched crate, etc.) — not the whole
   repo; the touched set is what this task can have broken.
3. Run **type-check** whole-repo via the compiler's incremental cache
   (`tsc --noEmit`, `mypy`, `cargo check`) — NOT diff-scoped (a signature change
   in this task's file breaks dependents elsewhere; the incremental cache keeps it
   cheap). **After each parallel wave merges back** (Step 3.4), run one whole-repo
   type-check to catch cross-file/merge defects.

**On failure:** loop back to Step 5 (re-dispatch via `implement`) with the full
failure output as context. The retry cap is **`SDD_MAX_RETRIES`** (default 3;
resolved per `goalforge/references/schema.md` §Retry budget resolution). On hitting the
cap, append a blocker to `<wp>/findings.md` (the task name, all failure output
from the final attempt, the retry count as `attempt N / SDD_MAX_RETRIES`) and
escalate via `AskUserQuestion` — **never silent-pass** a failing eval.

### Step 6b — Checkpoint write

**After every subagent return** (whether the eval passed or failed), write the
`checkpoint:` block to the task's **body** as a `## Checkpoint (goalforge-execute
state)` section — NOT the frontmatter. `goalforge-validate` enforces the `executing`
evidence invariant by scanning for `^checkpoint:` in the body; a checkpoint placed
inside the frontmatter is invisible to that scan and the pre-commit hook will
BLOCK. Belt-and-suspenders: it must function even if the **WP-05** `SubagentStop`
hook is absent.

````markdown
## Checkpoint (goalforge-execute state)

checkpoint:
  last_step: <step number just completed>
  specialist: "<resolved specialist or empty>"
  model: "<model used>"
  route: api|ollama
  worktree: "<absolute path or empty for main tree>"
  discovered_by: manual|map|discovery-agent
  commit_sha: "<full sha of this task's commit (Step 8), or empty until committed>"
  resumable: true
````

Set `resumable: false` only when a blocker has been escalated and human
intervention is required before continuing. `commit_sha` is the
**deferred-backfill carrier** (schema.md §Frontmatter `task-NN-*.md`): the commit
hash is stashed here at commit time (Step 8) and batch-backfilled into each task's
frontmatter `commit:` at WP finalize by `goalforge-verify` — so execution does not churn
task frontmatter with a per-task `commit:` write.

### Step 7 — Semantic review (amortized to the WP boundary; opt-in per task)

**Per-task `verify-and-simplify` is removed from the default path.** The expensive
agent fan-out (code review + simplify + second-opinion) now runs **once** in
`goalforge-verify` on the cumulative WP diff — running it per-task ×N on isolated diffs
and then re-doing it at the WP was pure duplication. A task that passed the
deterministic eval (Step 6) is `implemented`, not yet quality-signed-off.

**Opt-in per-task review (high-risk tasks only).** For a task flagged high-risk —
a deterministic blast-radius hit (exported symbols / auth / schema / migration /
3+ files) or human-pair mode — you MAY still delegate to `verify-and-simplify` on
this task's diff (then re-run Step 6 to confirm the simplification did not break
the eval), resolving its tier from the canonical role→tier map (roles `simplify` /
`wp-verify`). This is the exception, not the default.

### Step 8 — Atomic commit (task → `implemented`)

**Per-task commits stay** — they are the inter-task clean-tree gate (Step 1), the
parallel-wave merge-back unit (Step 3), and the durable crash-recovery substrate
(Step 9). They are **not** removed or squashed (a `wip` type blocks the commit-msg
hook; a mid-history squash on the master trunk is forbidden). What changes is the
task *status* (`implemented`, not `verified`) and where the commit hash is
recorded.

1. Stage only the files touched by this task.
2. Create **one conventional commit per task**: `<type>(<scope>): <description>`
   where `<type>` is `feat`/`fix`/`refactor`/etc. and `<scope>` is the task slug
   (e.g. `task-01-ralph-loop-core`).
3. Set task `status: implemented` in frontmatter **only after** the Step 6 eval
   pass. **In the same edit**, update that task's row in the `overview.md`
   `## Tasks` Status cell to `implemented` — frontmatter and Tasks cell MUST
   advance together (the wp-01 drift-detector hard-fails on divergence).
   (`verified` is written later, by `goalforge-verify`, when the WP gate passes.)
4. After the commit succeeds, capture the hash and **stash it in the task's
   checkpoint block** (`checkpoint.commit_sha`) — do **not** write a frontmatter
   `commit:` field here:
   ```bash
   HASH=$(git rev-parse HEAD)   # write to checkpoint.commit_sha (Step 6b block)
   ```
   `goalforge-verify` batch-backfills every task's `commit:` from the stashed
   `commit_sha` at WP finalize. Resume (Step 9) keys on `status:`, not `commit:`,
   so deferring the `commit:` write is safe.
5. After the task reaches `implemented` and `commit_sha` is stashed, refresh the
   feature rollup (per-task cadence):
   ```bash
   bash ${CLAUDE_PLUGIN_ROOT}/scripts/goalforge-rollup.sh <PLANS_ROOT>/<feature>
   ```
   Step 10 refreshes the rollup again at the WP boundary; both are intentional.

### Step 8.5 — Recap (delegated to `goalforge-recap`)

The **authoritative** trace record is **one row per WP** written at WP finalize by
`goalforge-verify` (`recap.sh record-wp`); the recap carries no per-task commit column.
Per-task `append-task` here is **optional live-progress only** (useful in a
long-running / interactive run) — record-only, with no effect on outer-loop
control or status-advance authority:

```bash
RECAP=<PLANS_ROOT>/<feature>/recap.md
bash ${CLAUDE_PLUGIN_ROOT}/scripts/recap.sh init "$RECAP" <feature>
# OPTIONAL live progress (result = ok|… ; no commit column):
bash ${CLAUDE_PLUGIN_ROOT}/scripts/recap.sh append-task "$RECAP" <wp-slug> <task-slug> ok
```

On a Step 6 loop-back (re-dispatch after a failed eval) **and** on a Step 9.5
reason→task re-open, record the loop-back before the retry (the iteration trace,
accumulated into the WP's single record at finalize):

```bash
bash ${CLAUDE_PLUGIN_ROOT}/scripts/recap.sh append-loopback "$RECAP" <wp-slug> <iter> "<reason>" <task-slug>
```

### Step 9 — Resume (re-entry)

When `goalforge-execute` is called for a WP already at `status: executing`:

1. Read every `task-*.md` (frontmatter for `status:`; body for the `checkpoint:`
   section).
2. A task at `implemented`, `verified`, or `committed`: **skip** — no-op (its code
   is in git; `commit_sha` awaits WP-finalize backfill).
3. A task with a `checkpoint:` block and `resumable: true`: if
   `checkpoint.worktree` is non-empty and the dir exists, **re-enter** it
   (`EnterWorktree`); continue from `checkpoint.last_step`.
4. A task with no checkpoint: treat as `pending`, process from Step 2.
5. Resume is **idempotent** — re-running it on an already-`implemented`/`verified`
   task is a no-op, **except** a task explicitly re-opened to `pending` by
   Step 9.5, which is reprocessed (that is the point of the re-open).

### Step 9.5 — Reason → task re-open (`reopen_task_from_reason`)

On a **not-met** WP verdict (numeric/judge path), the outer loop maps the
verdict's `reason` to the task(s) that must change rather than blindly re-running
the whole sub-cycle:

1. **Map** `verdict.reason` to a task (by file path / symbol / facet named in the
   reason). If one maps: reset it `implemented → pending` (Tasks cell **and**
   frontmatter together — wp-01 drift-detector), **clear its checkpoint
   `commit_sha`** (the prior commit is superseded by the re-do; the old commit
   stays in history, the next pass produces a new one), and record a recap
   loop-back (Step 8.5). **Bound** re-opens per task (default 2); a task past the
   bound without meeting the goal escalates — do not loop a task forever.
2. **No task maps** (the gap is structural): **PARK** (append the reason to
   `findings.md`, exit for human pickup) or route to `goalforge-redecompose` when the
   reason indicates a decomposition gap (a missing/mis-scoped WP). Never silently
   re-run with no target.

### Step 9b — Act on the goal-eval directive

After the sub-cycle pass, call the **pure** evaluator and act on its result — the
script never dispatches; this agent does. Use the in-process form so the
cascade-resolved `effective_goal` from Step 0b is honored:

```
verdict = evaluate(effective_goal)   # {met, reason, strategy, directive?}
```

`act_on_directive(verdict)` must return a shape the outer loop can read on **every**
path — `paused` always a bool, `met` concrete for every non-human path. Full
post-condition table: `references/goal-directive.md`.

- **`deterministic | numeric`** — `verdict.met` is already decided by the script
  (binary); nothing to dispatch (`paused = False`).
- **`judge`** (`met` is `null`, directive `{dispatch: judge, artifact, rubric,
  block_on}`): invoke the `judge` skill on `artifact` with `rubric`. Map the
  verdict by severity order **`CRITICAL > HIGH > MEDIUM > LOW`**: the *bar* is the
  **lowest** severity in `block_on`; **met = no finding at or above that bar**
  (e.g. `block_on: [HIGH]` blocks HIGH **and** CRITICAL). Otherwise not-met, and
  the judge's blocking findings become the carried-forward `reason`.
  **Fail-closed:** if `block_on` is empty/missing or carries an unknown severity,
  do **not** crash — treat the goal as not-met and escalate via `AskUserQuestion`.
- **`human`** (`met` is `null`, directive `{gate: <prompt>}`): a **non-blocking**
  gate. PAUSE — emit the gate prompt, write the pending gate to `findings.md`, set
  `verdict.paused = True`, and return so the outer loop **exits** (do not
  block-wait, do not iterate). The next `goalforge-execute` invocation resumes once the
  human has answered (Step 9 idempotency).

**Reason-feedback.** When the goal is not met and the loop continues, carry
`verdict.reason` into the next outer iteration and pass it to `implement` as
guidance (mirrors native `/goal`'s per-turn reason).

### Step 10 — WP exit (single status-advance authority)

Reached only when **every task is `implemented` AND `verdict.met` is `True`**:

- Invoke `goalforge-verify` — the single WP semantic gate. It runs the one
  cumulative-diff `verify-and-simplify` pass, **promotes each `implemented` task →
  `verified`**, batch-backfills every task's `commit:` from its checkpoint
  `commit_sha`, runs `--require-commit`, and advances `executing → verified`. It
  checks: all tasks `implemented`/`verified` + `findings.md` exists, then the
  cumulative-diff semantic gate.
- After `goalforge-verify` returns, refresh the feature rollup:
  ```bash
  bash ${CLAUDE_PLUGIN_ROOT}/scripts/goalforge-rollup.sh <PLANS_ROOT>/<feature>
  ```
- The WP `recap.md` finalize + `recap.sh rollup` are delegated to `goalforge-recap`
  **inside `goalforge-verify`** — record-only, no status-advance effect.

The outer goal gate does **not** write `status: verified` itself — it only gates
whether this step runs. `goalforge-verify` is the **sole authority** for the
`executing → verified` transition (defense in depth; no dual status-advance path).

---

## Skills reused (do not reimplement)

| Skill / Superpower | Used for |
|---|---|
| `implement` | Code-writing subagent dispatch (Step 5) |
| `verify-and-simplify` | **Opt-in only** for a flagged high-risk task (Step 7); the one review + simplify + second-opinion pass runs at the WP boundary in `goalforge-verify` |
| `superpowers:dispatching-parallel-agents` | Wave batched dispatch (Step 3) |
| `superpowers:using-git-worktrees` | Worktree create/merge per parallel task (Step 3) |
| `goalforge-goal-eval` (`skills/goalforge/scripts/`) | Pure goal router + `resolve_effective_goal` (Steps 0b, 9b) |
| `judge` | Acting on a `judge` directive from the goal eval (Step 9b) |

---

## Gotchas

- **Commit-hash ordering.** The hash is stashed in `checkpoint.commit_sha` at
  Step 8, not written to frontmatter `commit:` during execution; `goalforge-verify`
  batch-backfills `commit:` at WP finalize **before** the `--require-commit` gate
  — backfilling after would false-block. The pre-commit hook uses `--strict` only
  (never `--require-commit`), so the absent mid-execution `commit:` never blocks a
  commit.
- **`verified` is never written here.** Writing `status: verified` from
  goalforge-execute is a contract violation — `goalforge-verify` is the sole authority (it
  promotes `implemented → verified` at the WP gate). This holds even when
  `verdict.met` is `True`; a dual status-advance path is forbidden.
- **Inner vs outer caps are independent** — exhausting the inner retry cap
  escalates inside the sub-cycle; `outer_max_iter` counts outer passes, not total
  implementation attempts.
- **Transition rides the first task commit.** The `ready → executing` transition
  (Step 0) cannot be committed before any task checkpoint exists — the
  `sdd-pre-commit` hook blocks a transition-only commit with no checkpoint
  evidence. A wave agent must run the transition **in its worktree** and fold the
  transition's file changes into its **FIRST** task commit (Step 8), so the status
  advance and the first checkpoint land atomically.
- **Final-task `--amend` leaves a dangling `commit_sha`.** When the final task's
  commit is amended, `checkpoint.commit_sha` still points at the pre-amend (now
  dangling) sha, so `goalforge-verify`'s backfill would stamp a dead hash into
  `commit:`. Backfill it from the agent's **REPORTED post-amend sha**, or amend the
  checkpoint **before** creating the commit it records — never trust a stashed sha
  across an amend.
