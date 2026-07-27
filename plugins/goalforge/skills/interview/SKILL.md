---
name: goalforge-interview
description: "PRIVATE child of goalforge. Fidelity-aware goal-hardening specialization: frames a WP's open questions for a grilling session, delegates the Q&A loop to the global interview-loop engine, and implements the discussion-fidelity escape hatch. Invoked only by goalforge-harden Step 1; not a user-facing front door."
metadata:
  version: 1.0.0
---

# goalforge-interview

## Visibility

PRIVATE child of the `goalforge` package. Discovery is one level deep, so this
nested SKILL is never a user-invocable front door. Its **only** call site is
`goalforge-harden` Step 1, which invokes it by name to drive a WP's open
questions to zero.

## What this adds over bare interview-loop

The global `interview-loop` engine is a domain-agnostic Q&A loop; it knows
nothing about WPs, goal facets, or fidelity. This specialization supplies the
goal-hardening framing the engine needs:

- **Goal-facet completeness target** — the session isn't done until every open
  question in the WP's scope is resolved, recorded as an explicit assumption,
  or risk-accepted (harden Step 1's own exit criteria).
- **Fidelity vocabulary** — a question can outgrow discussion fidelity mid-loop;
  see `references/fidelity.md` for the ladder and the trigger criterion this
  specialization applies.
- Nothing here reimplements the engine's question technique or output
  contract — those stay entirely in `interview-loop`.

## Procedure (frame -> delegate -> escape hatch -> return)

1. **Frame** the session from the target WP's goal block (`overview.md`) and
   its recorded open questions — this is the context handed to the engine, not
   a restatement of its mechanics.
2. **Delegate** the Q&A loop to the global `interview-loop` skill by name. All
   question technique, confidence signaling, and stopping behavior belong to
   the engine; this specialization does not reimplement or shadow it.
3. **Escape hatch** — when a question meets the spike-candidate trigger
   (`references/fidelity.md` §Trigger), ask once: *"this is above discussion fidelity — spike it?"*
   Surface this by consuming the engine's existing `HANDOFF_SUGGESTION: high-fidelity`
   token (no parallel signal invented) and route per `references/fidelity.md`
   §Per-stage routing — `harden` row — to the `prototype` skill.
4. **Return** the engine's structured outputs (resolved terms, ADR candidates,
   handoff suggestions) untouched to the caller; this specialization does not
   post-process or filter them.

## Consumed by

`goalforge-harden` Step 1 — the sole call site. Spec-stage goalfinding is not a
consumer of this specialization (it keeps its own wp-04 spike hook).

## Gotchas

- The engine (`interview-loop`) stays global and unmodified — do not fork its
  question loop or stopping logic into this file.
- Drift between this wrapper's framing and the engine's actual contract is
  guarded by evals, not by restating the engine's mechanics here.
- Package-private: no top-level installer symlink for this child skill.
