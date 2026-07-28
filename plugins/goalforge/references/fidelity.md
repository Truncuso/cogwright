# Fidelity Ladder (discussion → interview → prototype)

A design question deserves the **cheapest fidelity that can settle it**, and no
more. This file is the single home of the ladder, the trigger criterion, and one
routing row per surface that consults them. Nothing here is a gate: a feature
that needs no prototype runs the chain exactly as before.

## Ladder

Three rungs, cheapest first. Start at rung 1; climb only when the rung below has
demonstrably failed to settle the question.

1. **Discussion** — reading the code, docs, or prior art and talking it through.
   Settles most questions. Climb when two passes leave the answer contested or
   the participants are reasoning from memory rather than evidence.
2. **Interview question** — structured Q&A driven by `interview-loop`, which
   converts the ambiguity into a named open question and drives it to resolved,
   assumption, or risk-accepted. Climb when the interview keeps circling: the
   answer depends on how the thing actually looks, behaves, performs, or scales,
   and no further questioning will produce it.
3. **Prototype** — a declared spike that answers ONE question by building the
   cheapest thing that produces evidence. Owned by the `prototype` skill;
   retention and what survives are governed by its Contract
   (`prototype/SKILL.md` §Contract §4-§5).

## Trigger

Canonical criterion — the only full statement outside the `prototype` skill's own
description (a discovery surface that must stay self-contained); stage decision
sites carry a one-line cue plus a link back here.

> A question is a **spike candidate** when both hold:
> 1. it is of kind **"how should it look / how should it behave / which approach
>    wins / how should it perform / does it scale"**, and
> 2. **more talking or reading will not settle it** — the answer depends on
>    observing the built thing.
>
> Either half alone is not enough. A look-and-feel question that a five-minute
> discussion resolves stays on rung 1; an intractable question that is not of
> that kind is an open question, a risk-accept, or a missing decision — not a
> spike.

## Per-stage routing

| stage / surface | hook |
|---|---|
| `capture` | Step 3 — a Goal sentence that turns on a question meeting the trigger carries a one-line downstream spike-candidate note; capture flags, it never spikes. |
| `spec` | A blocked spec section whose blocker meets the trigger is a spike to unblock it; findings feed the spec text and any ADR candidates. |
| `harden` | Step 1 applies the trigger to flag a spike candidate and routes it to the `prototype` skill (handoff mode `prototype`); `interview-loop` stays the sole resolver for everything else. Escalation refinement is owned by `goalforge-interview` (see `interview/`). |
| `decompose` | §Prototype WPs — a WP whose whole goal meets the trigger is a declared spike: `register: prototype`, one task, findings doc as deliverable. |
| `execute` | Step 0 — a WP carrying `register: prototype` runs the `prototype` skill and commits only the findings doc. |
| `goalforge-interview` escape hatch | When a question resists resolution, ask once: *"this is above discussion fidelity — spike it?"* rather than grinding further; see `interview/`. |

## issue-routing

Scope: **goalforge-side only**. The global triage skill is deliberately left
untouched; that integration is deferred to the idea `triage-fidelity-routing`,
gated on wp-04 verified.

A captured issue (`scripts/goalforge-issue`) or an unresolved open question that
meets the spike-candidate trigger (§Trigger) routes **up** the ladder to a
declared spike instead of staying prose. The kinds that most plausibly carry a design
question are `spec-gap` (a design facet the spec never settled) and
`dispatch-mismatch` (vocabulary-only until a `dispatch.*` producer lands, so
expect `spec-gap` in practice); the other kinds are operational and never route
here.

Routing happens at the stage that owns the surface, never at capture time:

- names a blocked spec section → the `spec` hook (spike to unblock it);
- reads as an open question → `harden` Step 1, flagged for `goalforge-interview` (which drives the global `interview-loop` engine) as
  a spike candidate;
- WP-sized on its own → `decompose` §Prototype WPs (`register: prototype`).
