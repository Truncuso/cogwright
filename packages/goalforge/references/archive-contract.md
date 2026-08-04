# Archive contract — what `_archived/` guarantees to its consumers

Single source of truth for how every goalforge consumer must treat an **archived**
plan or idea. `goalforge-archive` produces archived state; this file is the
contract everything that *reads* plans must satisfy. Four normative clauses.

Producers: `goalforge-archive` (features), `idea-archive` (ideas).
Consumers: `goalforge-validate.sh`, `goalforge-plan-index.py`, `goalforge-status.sh`,
`goalforge-frontier.sh`, `goalforge-capture`, and any sweep/report that walks
`<PLANS_ROOT>`.

## C1 — Archived is a terminal *resolution target*, not a deletion

An archived plan keeps its slug and stays reachable. A slug that resolves into
`_archived/` is **resolved**, not missing: an inbound edge whose target is archived
is **satisfied**, and the target's effective status is terminal
(`completed`/`archived` — dep-satisfying, exactly as `verified` is for a WP).

A consumer MUST NOT report an archived target as "not found", "dangling", or
"unresolved". A consumer MAY exclude archived nodes from *rendering* (a render-only
flag such as `--include-archived`), but exclusion from rendering MUST NOT remove
the slug from the **resolution** index.

## C2 — Detection predicate is DIRECTORY (or file) existence

An archived feature is detected by `<PLANS_ROOT>/_archived/<slug>/` **existing as a
directory**. An archived idea is detected by `<PLANS_ROOT>/ideas/_archived/<slug>.md`
**existing as a file**.

Detection MUST NOT depend on any file *inside* the directory — in particular not on
`overview.md`. Archived plans are frozen historical records that predate the current
layout; several carry no `overview.md`, and an `overview.md`-gated predicate reports
them as absent, producing false danglings and slug collisions.

Archive directory names: `_archived` (canonical) and `_archive` (legacy). Both are
recognized; new archives are written to `_archived/`.

## C3 — Archived plans are read for resolution only

An archived plan participates in the graph **only** as an inbound-edge target.
Specifically, a consumer MUST NOT:

- follow an archived plan's **outgoing** edges (they point at whatever the portfolio
  looked like when it was archived);
- include archived nodes in **topological ordering** or build-order tiers;
- report an archived node as an **orphan** (it has no live edges by construction);
- require **reciprocity** — an archived plan is not obliged to carry the inverse of
  an edge that points at it, and a missing inverse on the archived side is not an
  error.

Archived plans are likewise **not schema-validated** on a full-tree walk (they
predate the current schema; validating them yields noise that blocks unrelated
commits). Validating one explicitly by passing its directory AS the walked root is
supported.

**Pinned:** archiving a completed plan that has inbound typed relation edges
pointing at it is **allowed and expected**. Those edges are supposed to survive the
archive and resolve terminal per C1. No gate may be widened to refuse an archive
because inbound typed edges exist.

## C4 — Writers probe `_archived/` before instantiating a slug

Any operation that *creates* a plan or idea at a slug MUST probe the archived
locations (C2 predicate) before treating the slug as free, and MUST HALT on a hit
rather than stamping fresh live state over an already-archived identity.

On a hit the writer presents the choice — **restore** the archived slug or **use a
new slug** — and writes nothing until the choice is made. There is no automated
restore: restoring is a manual `git mv` out of `_archived/` plus a `status:` edit.
`goalforge-archive --relocate` is the inverse-adjacent operation (it moves a
stranded archived feature *into* `_archived/`, move-only); it does not restore.

## Known conformance status

| Consumer | C1 | C2 | C3 | C4 |
|---|---|---|---|---|
| `goalforge-validate.sh` | yes (archived-slug resolution index) | yes (dir/file entries under the archive roots) | yes (`SKIP_DIRS` excludes archived from the validating walk) | n/a |
| everything else | conform per this contract — **not** independently verified |

A consumer that does not conform is a defect in that consumer, never a reason for
`goalforge-archive` to refuse.
