# Fidelity Ladder (discussion → interview → prototype)

A design question deserves the **cheapest fidelity that can settle it**, and no
more. This file is the single home of the ladder and the trigger criterion.
Nothing here is a gate: a feature that needs no prototype runs the chain
exactly as before.

## Ladder

Three rungs, cheapest first. Start at rung 1; climb only when the rung below has
demonstrably failed to settle the question.

1. **Discussion** — reading the code, docs, or prior art and talking it through.
   Settles most questions. Climb when two passes leave the answer contested or
   the participants are reasoning from memory rather than evidence.
2. **Interview question** — structured Q&A driven by the `interview` plugin engine, which
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
