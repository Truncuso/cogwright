# Fog Precision — Rationale and Worked Examples

Rationale and examples for the four fog rules SKILL.md states inline. SKILL.md
owns the normative one-liners (chart step 3, work flow); this doc owns the
*why* and the worked cases. Nothing here is a rule the flows do not already
state.

Provenance: Matt Pocock's wayfinder skill + video — the source of the
fog-precision framing, no-pre-slicing, and one-ticket-per-session.

## 1. Fog precision — *statable now but not answerable now*

A ticket is a decision someone can **ask** today and cannot **answer** today.
Both halves are load-bearing:

| Candidate | Verdict | Why |
|---|---|---|
| "Postgres or SQLite for the local cache?" | ticket (`grilling`) | statable; answering needs the read/write profile |
| "Make the sync layer good" | not a ticket — fog | not statable as one decision; park under map `## Not yet specified` |
| "Rename `Cache` to `Store`" | not a ticket — just do it | answerable now; a ticket adds a loop iteration and nothing else |
| "What does the vendor's rate limit actually do under burst?" | ticket (`research`) | statable; answer is AFK-retrievable |

Two failure modes this rule blocks:

- **Under-precision** — an unstatable wish is ticketed, the picking session
  spends itself rediscovering what the question was, and the resolution is a
  restatement rather than a decision. Unstatable candidates belong in map
  `## Not yet specified`, which the blind-spot pass re-sweeps.
- **Over-precision** — an already-answerable item is ticketed, so the loop pays
  claim → dispatch → resolve → findings → map-pointer for a change that was one
  edit. Do it, and mention it in the ticket that surfaced it.

The eval harness can only assert this rule's TEXT is present in the chart step 3
slice. Whether a given candidate satisfies it is a judgment the flow makes at
triage time; no deterministic check can stand in for it.

## 2. The two out-of-scope homes

They are not interchangeable, and the difference is observable by the frontier
script:

| Home | Holds | Frontier effect |
|---|---|---|
| map `## Out of scope` (body section) | a **never-ticketed** candidate, dropped at blind-spot triage | none — inert; the frontier reads tickets, never the map body |
| `status: out-of-scope` (ticket frontmatter) | an **existing** ticket, deliberately dropped | closed (not open, so it does not block `converged`) AND **dependency-satisfying** |

Consequence: if `ticket-07` has `depends_on: [ticket-04]` and you drop
`ticket-04` by deleting it and writing a line under `## Out of scope`,
`ticket-07` blocks forever on a dangling reference (the frontier fail-closes
exit 2). Drop it by setting `status: out-of-scope` instead and `ticket-07`
unblocks. Use the section only for candidates that never became tickets.

## 3. No pre-slicing

Do not decompose a ticket into sub-tickets before it is picked. The sub-shape of
a decision is itself unknown until someone works it — pre-slicing guesses that
shape, and the guess is wrong often enough that the sub-tickets have to be
rewritten or deleted, after they have already been wired into `depends_on`
edges and counted against convergence.

Slicing is a legal **mid-loop fog move**: the session that picks a ticket and
finds two independent decisions inside it resolves what it can, surfaces the
remainder as new tickets, and records why in `## Resolution notes`. That
slicing is evidence-based; pre-slicing is not.

## 4. One ticket per session (default + exceptions)

The default exists because a wayfind session's product is a *decision*, and
decisions made under context pressure from a second unrelated decision are the
ones that get revisited. One ticket also keeps the end-of-session commit a
single consistent state (map pointer + ticket + findings), which is what the
next session resumes from.

Named exceptions — the only two:

- **`ticket_type: research` tickets.** They are AFK and non-conflicting: the
  dispatch runs outside the main session's context and writes only its own
  `findings/ticket-NN.md`. This is a property of the TYPE, not a loophole any
  ticket may claim by asserting it is easy.
- **Trivially-coupled tickets** — two tickets whose resolutions are the same
  decision viewed twice (e.g. "which serializer" and "which wire format"), where
  resolving one already determines the other.

There is **no machine check** for this rule. Once Resolve releases the claim, a
correctly-resolved ticket is byte-identical whether it was worked alone or
alongside three others — the contract cannot observe the difference. It is a
documented default, enforced by review and by the reasons above.
