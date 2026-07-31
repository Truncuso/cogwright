# Graduation Brief — Exit-Transfer Wiring

Concrete mechanics of graduate **step 5** (Exit-transfer). SKILL.md `## graduate
flow` owns the full gated sequence and forward-points here; this doc owns how the
`goalforge-capture` invocation is composed. Read alongside spec §Graduation.

## Gated sequence (recap — see SKILL.md for the authoritative flow)

```
converged: true (frontier script)          # precondition — zero open tickets
  → blind-spot re-check (dispatched)        # accepted candidate ⇒ ABORT (map working)
  → quiz-back gate (HITL)                   # surfaced gap ⇒ new ticket ABORT, or accepted-risk
  → user confirms transfer                  # human at the chain boundary
  → [adr-write gate] → exit-transfer        # this doc owns these two
  → wayfind/ stays in place                 # provenance, never deleted
```

Any gate can ABORT; on abort the map is simply `working` again — no status unwind.

## 1. adr-write gate (BEFORE goalforge-capture)

For **each** resolved decision, invoke the `adr-write` skill. It enforces its own
three-condition gate and writes only when ALL three hold:

- **hard-to-reverse** — undoing the decision is expensive.
- **surprising-without-context** — a newcomer would not guess it.
- **real-trade-off** — a genuine alternative was rejected.

adr-write **refuses** decisions that miss any condition (easy-to-reverse,
self-evident, or no real alternative). That refusal is **expected and fine** —
do not force it; skip and move on. ADRs land in `docs/adr/` + `.memory/` and are
referenced (not copied) from the graduated feature.

## 2. goalforge-capture invocation brief (the free-text intent)

Compose ONE free-text block from the converged map and pass it as
`goalforge-capture`'s intent argument. Template:

```
<destination line — verbatim from map.md `destination:`>

Resolved decisions:
- <decision A summary> — see <resolved ticket pointer, e.g. ticket-02-auth-model.md>
- <decision B summary> — see <ticket-05-storage.md>
- <one bullet per resolved ticket, each with its resolution pointer>

Scope (carried task tickets — concrete work, consumed later by goalforge-decompose):
- <leftover `ticket_type: task` title> — see ticket-07-wire-cli.md
- <one scope bullet per task ticket whose resolution is a DECISION about future work>

Completed work (already executed during the map — NOT scope, do not re-plan):
- <task ticket whose resolution IS the executed work> — see ticket-04-spike-parser.md

Accepted risks (from findings/quiz-back.md):
- <recorded accepted-risk, if any>

References: <count> provenance entries carried into sources[] (see §3).
```

Rules:
- **Destination line** is copied verbatim from map frontmatter — it is the pinned
  scope and becomes the feature's one-line intent.
- **Resolved decisions**: one bullet per resolved ticket, each carrying a pointer
  to its resolution (the ticket file / its `findings/` summary), never the full
  body — pointers, not copies.
- **Scope bullets** are surviving `ticket_type: task` tickets, passed as prose
  scope, NOT as pre-decomposed WPs.
- **Completed work vs scope (the discriminator).** Convergence resolves every
  task ticket, so "resolved" alone does not make a ticket a scope bullet. A
  resolved `task` ticket becomes a **scope bullet** ONLY when its resolution is a
  **decision about future work** — the work it names is still ahead. A resolved
  `task` ticket whose resolution **IS the executed work** (the spike was run, the
  CLI was wired) is reported under **Completed work**, never as scope. Reporting
  executed work as scope makes `goalforge-decompose` cut a WP for work already
  done. When a resolved task ticket carries both — work executed AND a decision
  about further work — split it: the executed half to Completed work, the
  forward-looking half to Scope.

## 3. Provenance bridge (references[] → sources[])

Map `references[]` entries land in the graduated feature's `overview.md`
`sources[]`, PLUS a `wayfind-<effort-slug>` self-link entry — the mirror of the
idea-promotion provenance path (idea `references[]` → promoted feature
`sources[]`). The entry shape and its `type` vocabulary are CANONICAL and cited,
never redefined here: `~/.claude/skills/idea/references/provenance-mapping.md`.
Shape written by goalforge-capture:

```yaml
sources:
  # ── carried verbatim from map.md references[] ──
  - id: <ref-id-from-map>
    type: url | file | spec | paper | repo | session | conversation | image | video
    locator: <path-or-url>
    note: <why it matters>
    retrieved: YYYY-MM-DD
  # ── wayfind self-link (added on graduation — the provenance mirror) ──
  - id: wayfind-<effort-slug>
    type: file
    locator: plans/<effort-slug>/          # the wayfind/ map that stays in place
    note: "graduated from wayfind decision-map (converged YYYY-MM-DD)"
    retrieved: YYYY-MM-DD
```

The `<effort-slug>` is the same slug as the map directory and the new feature —
graduation is in-place, so the self-link points back at the surviving `wayfind/`.

## 4. Boundary statement (where wayfind STOPS)

- Graduation **ENDS** at goalforge-capture's `overview.md` (`status: draft`).
- wayfind **never** writes spec, decompose, or WP artifacts — those proceed
  through the normal SDD chain (`goalforge-spec` → `goalforge-decompose` → …).
- Carried **task tickets** are consumed **later** by `goalforge-decompose` from the
  spec — wayfind hands them across as scope prose and never invokes decompose
  itself.
- `wayfind/` is **not** deleted or moved; it stays as provenance, reachable via
  the `wayfind-<effort-slug>` self-link in `sources[]`.
