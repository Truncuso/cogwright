---
name: sdd-plan-index
description: "Generate plans/INDEX.md -- a DERIVED feature register + cross-feature dependency DAG + topological build-order tiers + cycle/orphan detection -- by harvesting each feature overview's `relationships:` frontmatter. The frontmatter is the single source of truth; the index is regenerated, never hand-synced. Use to (re)build or refresh a plans portfolio index after adding/changing features, to see the build order, or to find dependency cycles and orphaned features. TRIGGER: 'generate the plan index', 'rebuild plans/INDEX.md', 'show the feature dependency graph', 'what is the build order', 'find plan cycles/orphans'. Pairs with sdd-archive's reference-gate (idea: sdd-plan-index-and-portfolio-housekeeping)."
metadata:
  version: 1.0.0
hooks:
  Stop:
    - hooks:
        - type: command
          command: "$HOME/.claude/scripts/skill-measure.sh sdd-plan-index"
---

# sdd-plan-index

Derives `plans/INDEX.md` from feature-overview frontmatter so the portfolio index
and the per-feature `relationships:` edges never drift apart. The index is a build
artifact -- regenerate it; do not hand-edit it.

**Scope:** this is **feature-level portfolio navigation**, regenerated on demand —
it is **not** part of the per-WP execute → verify → commit loop and never gates a
transition. It answers "what features exist, in what build order, with which
cross-feature dependencies", orthogonal to a WP's goal/verify/commit cycle.

## Mechanical core

```bash
python3 ~/.claude/skills/sdd/scripts/sdd-plan-index.py \
    [--plans-root <root>] [--include-archived] [-o <file|->]
```

- **Plans root** resolves like the rest of the SDD chain: `--plans-root` -> env
  `SDD_PLANS_DIR` -> git-root `plans/` -> CWD `plans/` -> `~/.claude/plans/`.
- **Output**: default writes `<PLANS_ROOT>/INDEX.md`; `-o -` streams to stdout
  (preview without touching disk); `-o <file>` writes elsewhere.
- `--include-archived` folds `_archived/` features in as `status: archived` nodes.

## What it derives

- **Feature register** -- one row per `<feature>/overview.md`: feature, `status`,
  and the features it depends on (precede it).
- **Dependency DAG** -- each `relationships:` edge normalized to a forward edge
  (A -> B means A precedes B):
  - `B follows A` and `B depends_on A` => `A -> B`
  - `A enables B` => `A -> B`
  - `part_of` is a grouping note, not a build-order edge.
- **Build-order tiers** -- a Kahn topological layering (Tier 0 = no unmet deps).
- **Cycle detection** -- features that cannot be ordered are listed under a
  WARNING; the script exits **4**.
- **Orphans** -- features with no edges in or out (often a sign their
  `relationships:` frontmatter is unfilled, not that they are truly independent).

## Exit codes

`0` clean DAG written | `2` plans root missing | `3` no features found |
`4` cycle detected (index still written, with the cycle WARNING).

## Source of truth

The `relationships:` frontmatter (schema: `~/.claude/skills/sdd/references/schema.md`)
is canonical. If the generated index is wrong, fix the **frontmatter**, then
regenerate -- never patch INDEX.md by hand. An unexpected orphan means a feature's
edges are missing from its overview.

## Gotchas

- **The index is DERIVED -- never hand-edit.** A hand edit is overwritten on the
  next run and silently diverges from the frontmatter in the meantime. Fix the
  overview's `relationships:` and regenerate.
- **An orphan is usually a missing edge, not independence.** The framework's
  `viz-service-api`/`viz-desktop-app` showed as orphans because their `relationships:`
  frontmatter was thinner than the hand-written index -- the generator surfaces the
  gap rather than inventing the edge.
- **`enables` is inverted on purpose.** `A enables B` becomes `A -> B` (A precedes
  B), the same direction as `B depends_on A`. Do not also add the `depends_on` on B
  -- one direction per edge, or the DAG double-counts (harmless to tiers, noisy in
  the register).
- **A cycle still writes the index** (exit 4) so you can see the offending nodes;
  it does not silently refuse.
- **gitignored plans roots are fine** -- the generator reads the filesystem, never
  git, so an ignored `plans/` (e.g. the parent app repo) indexes normally.
