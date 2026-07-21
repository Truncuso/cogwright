---
name: goalforge-arbiter
description: "Approach arbitration for SDD hardening. Invoked by goalforge-harden when the spec marks decision-required OR when two or more approaches involve a hard-to-reverse bet. Normalizes each candidate approach into comparable claims along seven axes (objective, assumptions, files touched, sequencing, validation, rollback, cost), cross-reviews them dimension-by-dimension, and emits a decision memo — chosen direction, rejected alternatives with reasons, verification gates for the chosen path. Advisory input to goalforge-harden; does NOT change the human-gated hardened→ready transition. Trigger: goalforge-harden delegates a multi-approach arbitration for a WP, or a user asks to arbitrate competing implementation approaches."
metadata:
  version: 1.1.0
---

# goalforge-arbiter

Advisory approach arbitration for SDD work packages during the hardening phase.
Invoked by `goalforge-harden` when architectural approaches diverge and a structured
comparison is needed before the human gate.

## Trigger

`goalforge-harden` invokes `goalforge-arbiter` when either condition holds:

1. The WP spec marks a section **decision-required** (explicit ambiguity flag).
2. Two or more candidate approaches involve a **hard-to-reverse bet** — an
   irreversible infrastructure choice, a public-API change, a schema migration,
   or a substantial rewrite that forecloses alternatives.

A single approach with no competing option does not warrant arbitration. When
in doubt, apply the irreversibility test: if the wrong choice cannot be undone
without significant pain, arbitrate.

## Stakes tiering (how much arbitration to spend)

The trigger already self-gates on irreversibility, so everything that reaches
arbitration is above the bar. Within that, scale the *depth* of normalization to
the stakes — but **fail safe to the full grid whenever reversibility is
uncertain**. This is a bounded cost-saver, never an axis-drop for brevity.

| Stakes | Path | Normalization |
|--------|------|---------------|
| **Hard-to-reverse bet** (irreversible infra, public-API, schema migration, substantial rewrite) | **Full grid** | All **seven axes** + the full six-dimension cross-review + decisive dimension. |
| **Borderline-reversible** (arbitration triggered, but the wrong choice is recoverable at moderate cost) | **Quick-compare** | Objective alignment + the **decisive axis** + the **rollback axis (always retained)**. If, while comparing, reversibility turns out worse than assumed → **escalate to the full grid**. |

The **rollback axis is never dropped** — it is the axis that decides whether the
quick path was even legitimate. Any uncertainty about reversibility resolves to
the full grid (fail-safe). The quick-compare path exists only to avoid a
seven-axis grid on a genuinely recoverable two-approach choice; it is not a
fast-path around rigor on a real bet.

### Optional: dispatch the mechanical normalization grid to a cheap tier

The N-approach × axis **normalization grid is mechanical** — it can be produced
by a cheaper-tier sub-agent and consumed as typed DATA. Resolve its model tier
from the canonical role→tier map — role **`arbiter-grid`** (`goalforge-pick-agent.py`);
do not restate the tier. Keep the **cross-review judgment, the decisive-dimension
call, and the memo in the main context** (they are the actual arbitration), and
stamp the memo with a decision-attribution stamp when any part was
subagent-produced (`goalforge-attribution.sh`). This is optional — inline normalization
is fine; only offload when the grid is large enough to be worth a round-trip.

## Approach Normalization

Before comparison, normalize each candidate approach into comparable claims
along these seven axes:

| Axis | What to capture |
|------|----------------|
| **objective** | The concrete outcome the approach delivers — how it satisfies the WP goal |
| **assumptions** | What must be true for the approach to work (env, data shape, team knowledge) |
| **files touched** | Estimated file/module scope — which components are modified or created |
| **sequencing** | Order of implementation steps; what is blocked behind what |
| **validation** | How success is verified — tests, metrics, acceptance criteria |
| **rollback** | How to undo if the approach is abandoned mid-execution |
| **cost** | Estimated complexity/time/risk compared to alternatives |

Record each axis as a one- or two-sentence claim. Avoid narrative: comparable
claims must be structurally parallel so the cross-review can diff them directly.

## Cross-Review

Compare the normalized approaches dimension-by-dimension:

1. **Objective alignment** — which approach most directly satisfies the WP
   outcome without scope creep?
2. **Assumption risk** — which assumptions are most uncertain or hard to verify?
   An approach with fragile assumptions scores lower even if its logic is sound.
3. **Blast radius** — larger `files touched` sets increase merge conflict risk
   and review burden; prefer the narrower scope when outcomes are equivalent.
4. **Sequencing flexibility** — prefer approaches that unlock validation early;
   flag approaches whose validation is deferred to the end (late-integration risk).
5. **Rollback cost** — prefer reversible over irreversible where outcomes are
   equivalent; a cheaper rollback lowers the irreversibility penalty.
6. **Overall cost delta** — compare relative complexity and implementation time.

Assign a brief verdict per dimension (≤ one sentence). Surface the **decisive
dimension** — the single axis where the approaches diverge most consequentially.

## Decision Memo

Emit a **decision memo** structured as follows:

```
## Decision Memo — <WP identifier>

**Chosen direction:** <approach name + one-line rationale>

**Rejected alternatives:**
- <approach name>: <reason rejected — the decisive dimension>
- ...

**Verification gates for the chosen path:**
- <gate 1: what must be true before proceeding>
- <gate 2: acceptance criterion that closes the decision>
- ...
```

The memo is written into the WP folder (e.g., `<wp>/arbiter-memo.md`) and
surfaced to `goalforge-harden` as advisory input. It does NOT alter the WP's
frontmatter status.

## Advisory Boundary

`goalforge-arbiter` is advisory input to `goalforge-harden`. It produces a decision memo
and surfaces the reasoning, but it does NOT change the human-gated
`hardened → ready` transition. The decision memo informs the human reviewer;
it cannot approve or advance the WP on its own. All status authority remains
exclusively with the human gate in `goalforge-harden`.

## Gotchas

- **Advisory, not a gate.** The decision memo is input to the human reviewer,
  not a verdict. If you find yourself blocking `goalforge-harden`'s status advance
  based on a memo finding, that is a bug in the wiring — record the memo and
  return control to `goalforge-harden`.
- **Normalization before comparison.** Never compare raw narrative approaches
  directly. Each approach must be reduced to axes first; skipping normalization
  produces a subjective narrative comparison, not an arbitration. (Applies to
  both paths — the quick-compare path still normalizes its retained axes; it does
  not narrative-compare.)
- **Seven axes, not six — on the full grid.** On the **full grid** (hard-to-reverse
  bets) the seven normalization axes — objective, assumptions, files touched,
  sequencing, validation, rollback, cost — are the full set; do not drop axes for
  brevity, a missing axis hides information the human gate needs. The
  **quick-compare path** (Stakes tiering) is the *only* sanctioned reduction, it
  is bounded to borderline-reversible bets, it **always retains the rollback
  axis**, and it **fails safe to the full grid** when reversibility is uncertain.
- **Single approach: skip.** When only one approach exists, do not force an
  arbitration. Return immediately with a note that no competing approach was
  identified and arbitration is not applicable.
- **Decisive dimension required.** The cross-review must identify the single
  axis where the approaches diverge most consequentially. A memo without a
  decisive dimension is not actionable.
- **Irreversibility is the primary trigger.** When it is unclear whether to
  invoke `goalforge-arbiter`, ask: "Is the wrong choice hard to undo?" If yes,
  arbitrate. If no, the decision can be revisited cheaply and arbitration adds
  overhead without value.
