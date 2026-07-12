---
name: goalforge-run
description: "Orchestrator for the SDD planning chain, route-aware: full = capture → spec → decompose → harden → execute → verify; fast = capture → add-wp → deterministic gates → execute → verify (route: read from the feature overview frontmatter, stamped by goalforge-capture). Routes the entry commands /spec /plan /implement /verify to the correct chain step, resumes mid-chain by reading the current WP status:, and supports --dry-run. Invoke goalforge-run when a user runs any of the four entry commands or when the chain must resume from a known WP stage. SKIP for single-step work: invoke the child skill directly (goalforge-capture, goalforge-spec, goalforge-decompose, goalforge-harden, goalforge-execute, goalforge-verify)."
metadata:
  version: 1.1.0
hooks:
  Stop:
    - hooks:
        - type: command
          command: "$HOME/.claude/scripts/skill-measure.sh goalforge-run"
        - type: command
          command: "$HOME/.claude/hooks/skill-trace.sh goalforge-run:stop"
---

# goalforge-run — SDD Orchestrator

## Location

`goalforge-run` lives at `skills/run/` within the goalforge plugin
(`$COGWRIGHT_ROOT/plugins/goalforge/skills/run/`); the directory is `run/` (not
bare `run`, which collides with the existing `run` skill) while the skill
registers under the name `goalforge-run`. Its six child skills
(`goalforge-capture`, `goalforge-spec`, `goalforge-decompose`, `goalforge-harden`, `goalforge-execute`,
`goalforge-verify`) are sibling plugin skills under `skills/`. The orchestrator
is invoked by name (`goalforge-run` / `skill-router goalforge-run`), so its
directory location does not affect how the slash commands or the router resolve it.

## Chain

`chain.yaml` (sibling file) declares the sequence. `goalforge-run` does not
autonomously reorder or extend the chain; any modification goes through
`/skill-improve`.

## Route awareness (fast vs full)

The chain adapts to the goal's size: `goalforge-run` reads the feature overview's
`route:` frontmatter (stamped by `goalforge-capture` via `goalforge-route.sh` —
capture is the routing home; absent ⇒ `full`) and skips the steps marked
`when_route: full` in `chain.yaml` for a `route: fast` feature:

- **`full`** — the six-step chain, unchanged.
- **`fast`** — capture → `goalforge-decompose --add-wp` (ONE WP, complete
  self-contained goal block, no `spec.md`) → deterministic gates
  (`goalforge-validate` + `goalforge-open-questions-gate.sh --check` +
  `goalforge-wp-complexity.sh` verdict `simple`, severity ≤ MEDIUM, non-migration)
  → `goalforge-transition.sh <wp> ready --mode auto` → execute → verify.
- **Escalation:** ANY fast-gate trip leaves the WP at `spec` and re-enters the
  chain at the harden step (full treatment). The gates, not the classifier,
  are the safety net.
- **Never skipped:** `goalforge-verify` — every route ends at the single semantic
  gate; the outcome→verification contract is route-independent.

Full fast-path runbook: `goalforge-capture` §Fast path.

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

Full schema: `~/.claude/skills/sdd/references/schema.md`.

WP stage vocabulary used as preconditions in `chain.yaml`:

```
draft → spec → hardened → ready → executing → verified → archived
```

`draft → ready` (feature, via goalforge-spec) and `hardened → ready` (WP, via goalforge-harden) are human-gated
(the latter with the signal-scoped auto-advance exception — state-machine.md §Policy).
`archived` is terminal; never entered automatically. A `route: fast` WP takes the
legal `spec → ready` edge via the deterministic gates instead of harden.

## Shared references

- Schema + frontmatter: `~/.claude/skills/sdd/references/schema.md`
- Templates: `~/.claude/skills/sdd/references/templates/`
- Specialist routing: `~/.claude/skills/sdd/references/specialist-map.yaml`
- PLANS_ROOT resolution: `~/.claude/skills/sdd/references/schema.md`
  §PLANS_ROOT resolution (env `SDD_PLANS_DIR` → project git-root `plans/` →
  global `~/.claude/plans/`)

## Gotchas

- Resume routing keys entirely off the target's on-disk `status:` — a value matching no `chain.yaml` precondition (a hand-edited label, schema drift, or a terminal `verified`/`archived`) leaves goalforge-run with no step to enter, so it halts rather than guessing. Don't hand-edit `status:` to force re-entry; set it to the exact precondition the intended step expects.
- `--dry-run` must have zero side effects: no files written, no subagents dispatched, no status fields mutated. A dry-run that modifies state makes testing the chain impossible and breaks CI verification.
- Resume reads the CURRENT on-disk `status:` at invocation — if a parallel session or an external committer advanced the WP between your last step and this resume, goalforge-run enters at the NEW status and can skip the step you expected. Re-check `status:` before resuming a long-suspended chain.
- `chain.yaml` steps resolve their `skill:` against installed skills only at RUNTIME — a step naming a renamed, uninstalled, or typo'd skill fails when the chain REACHES it, not at load. Run `scripts/goalforge-router.sh --dry-run <feature>` after any chain.yaml edit to surface an UNRESOLVED step up front.
- The entry commands (`/spec`, `/plan`, `/implement`, `/verify`) call their child skills **directly** (e.g. `commands/spec.md` → `goalforge-capture`/`goalforge-spec`) — they do NOT route through `goalforge-run`, so its resume + gate logic is bypassed when you use the slash commands. Invoke `goalforge-run` (or `skill-router goalforge-run`) explicitly when you need the orchestrator.
