# Examples

Real, working artifacts from cogwright's own use of the `goalforge`
Spec-Driven Development (SDD) chain and its `wayfind` pre-spec on-ramp,
lightly scrubbed (absolute personal paths only — no content rewrites) so
they're safe to publish. `plans/` and `docs/handoffs/` themselves stay
gitignored and private; these curated copies are the only public window into
what that private planning substrate actually produces.

Nothing here is a synthetic sample written to look good — each file is a
copy of a real artifact this repo's own agents produced and consumed while
building the goalforge chain and its wayfind child.

| File | What it is | Where in the chain |
|---|---|---|
| [`goal-object-anatomy-wp.md`](./goal-object-anatomy-wp.md) | A hardened, verified work package (WP) — the goal-object anatomy: `outcome`, `verification.check`, `constraints`, `boundaries`, an append-only decision log, and a versioned goal changelog that survives redecomposition | `/plan` output, ready for `/implement` |
| [`session-handoff.md`](./session-handoff.md) | A session handoff closing out a completed feature and carrying forward a short residue agenda — state snapshot, DO/DON'T constraints, gotchas, and durable learnings | Emitted at a session boundary, consumed via `/handoff-pickup` |

## Why these two

- The WP shows what a **verifiable goal** looks like in practice — not "make
  it work," but a falsifiable outcome with an exact, runnable verification
  check and a changelog that records when the goal itself turned out to be
  wrong and was corrected on the record.
- The handoff shows **cross-session continuity** — how an agent hands off
  mid-work (or, here, at feature close) so a fresh session — possibly a
  different model — can resume without re-deriving state from the repo and
  scrollback.
