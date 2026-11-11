# ADR 0001 — goalforge plugin: all 13 children stay discoverable

- Status: accepted
- Date: 2026-11-11

## Context

The goalforge package nests its stage skills as private children of one front
door. In the package tree, discovery is one level deep, so only `goalforge`,
`prototype` and `wayfind` are discoverable and every other child is read by
path. The generated plugin is different: `scripts/goalforge-generate.sh` emits
every child under `plugins/goalforge/skills/`, and a plugin loader discovers
each one as `goalforge:<child>`. The package Gotcha used to state that no nested
child resolves via the Skill tool, which was false for the plugin.

## Decision

The plugin keeps its current layout. Its discoverable child set is exactly these
13 names: `archive`, `capture`, `decompose`, `execute`, `harden`, `onboard`,
`plan-index`, `prototype`, `redecompose`, `run`, `spec`, `verify`, `wayfind`.
Each child description carries the do-not-auto-trigger marker that routes a
reader back to the entry commands.

The set is pinned by name, not by count. `lint_privacy_marker` in
`scripts/ci-lints.sh` compares the literal name list with the plugin child dirs
and with the package child dirs, so adding, removing or renaming a child needs a
deliberate edit in both places. The same lint requires the package Gotcha to
carry the phrase `plugin-discoverable as goalforge:<child>`, so the documented
behavior cannot drift from the shipped one.

## Alternatives considered

- **Relocate the children out of `skills/`** so the plugin exposes only the
  front door. Rejected for now: it touches the generator's path-rewrite rule,
  the commands, the hooks and several lints, and no mis-triggering has been
  observed that would justify that cost.
- **Keep a count-only pin.** Rejected: a same-count rename, or a child added to
  the package but not the plugin, passes a count check unnoticed.

## Consequences

- Plugin users can address any child as `goalforge:<child>`; the marker, not the
  layout, is what discourages auto-triggering.
- Changing the child set is a deliberate multi-place edit: the name list in
  `scripts/ci-lints.sh`, the child dir, the catalog count, the child count
  asserted in `packages/goalforge/evals/run.sh`, and the count quoted in the
  package Gotcha and in the generator comment.
- The phrase check reads the whole package `SKILL.md`, not only its Gotchas
  section.
- A later change may hide the children from model invocation or relocate them;
  that change supersedes this record.
