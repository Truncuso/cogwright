---
name: goalforge-decompose
description: "goalforge-internal — use entry commands; do not auto-trigger Decompose an approved feature spec into work packages. Reads plans/<feature>/spec.md and emits one wp-NN-<slug>/ folder per work package, each containing overview.md ONLY (status: spec) in the C1 eight-section shape with C2 frontmatter, a checklist of `- [ ] Tn <outcome> {files: a, b} [b1,b2]` lines, and a per-WP contract_slice. No per-item files, no todo.md. Also owns --add-wp: append ONE new WP to an existing feature without a re-decomposition. Trigger: the user asks to decompose, break down, or plan the work packages for a feature with an approved spec.md, or to add a single WP mid-flight."
metadata:
  skill-kind: preference
  version: 2.0.0
---

# goalforge-decompose

Emits the WP folder tree for an approved spec. Writes only
`<feature>/<wp-id>/overview.md` (born `status: spec`, never another status) and
the feature `<feature>/overview.md`; `spec.md` is read-only here. Schema (and
§PLANS_ROOT resolution): `${CLAUDE_PLUGIN_ROOT}/references/schema.md`. Template:
`${CLAUDE_PLUGIN_ROOT}/references/templates/wp-overview.md`.

## Step 1 — Read the spec

Preconditions: `<PLANS_ROOT>/<feature>/spec.md` exists with an
`## Interface Contract`, the feature `overview.md` is `status: ready`, and the
feature is next-to-execute — decomposing ahead buffers WPs that drift; confirm.

Extract the WP table (title, scope, dependencies, parallelism), Design,
`## Interface Contract`, Non-Goals, and the feature `goal:` block with its
`verification.behaviors[]`. Absent a WP table, derive WPs from Design by
vertical slice — one complete testable increment each, never a horizontal
layer. Never author work that implements a non-goal.

Size each WP by goal, not item count: split when the title needs an "and" (two
distinct outcomes) or when the WP is not one measurable `goal.outcome`
sentence; more than 8 owned files is a batching signal (C5), not a split
signal. Confirm the list when a WP is large or the decomposition is non-obvious.

## Step 2 — Derive the WP frontmatter (C2) and goal block

Per WP: `name: wp-NN-<slug>`, `severity`, `task_type`, `register` from the spec,
`depends_on` (backward-pointing slugs only), `parallel`,
`owned_files` (the file boundary), `contract_slice` (the `### C…` ids of the
Interface Contract this WP depends on — schema.md §Contract-slice hash),
`human_required: null` or a reason string (C7), `schema_version: 6`,
`plan: <feature>`, `goal_approved_version: null`.

`goal.outcome`/`goal.verification` are always WP-authored, never inherited: one
measurable outcome sentence, one `strategy`, one command-only
`verification.command`, and the `behaviors[]` rows this WP's checklist cites.
`constraints`/`boundaries` union with the feature's; `iteration_policy`/
`blocked_stop` inherit via `inherits_from:`.

## Step 3 — Author the checklist

```
- [ ] T1 <imperative outcome> {files: a, b} [b1,b2]
```

One line per work item, in execution order; `[b1,b2]` names the behavior ids it
satisfies. An item carries no status, complexity, verify, depends_on, or commit
field — the WP ships as one commit (C5).

## Step 4 — Stamp `overview.md`

Idempotency is folder-level: an existing WP folder is skipped without
modification. Otherwise stamp from the template — frontmatter from Step 2, body
in the C1 order `## Goal`, `## Verification`, `## Owned Files`, `## Depends On`,
`## Checklist`, `## Open Questions`, `## Decisions`, `## Goal Changelog`, and no
other H2. Double-quote free-text frontmatter that may carry a colon (`title:`,
`goal.outcome:`) — an unquoted colon-space breaks the block. `status: spec` is a
birth state, not a transition: never call `goalforge-transition.sh` here.

## Step 5 — Self-check (four rules, fixed in place)

1. **Deterministic gate.** Every `verification.command` is command-only and runs
   offline — no live run, network call, or manual step.
2. **Facet coverage.** Every facet of `goal.outcome` is covered by
   `goal.verification` or a `behaviors[]` row, and every item cites a behavior id.
3. **One owner, backward deps.** `owned_files` sets are pairwise disjoint
   across WPs, every `{files: …}` is a subset of its own WP's `owned_files`,
   and no `depends_on` points at a later WP.
4. **Hermetic oracle.** Every `behaviors[]` entry names the input its check runs
   against, and that input ships as a fixture under the WP's `owned_files` —
   never a live corpus root (`$HOME`, `$CLAUDE_CONFIG_DIR`); lint V6 WARNs.

A rule that needs a spec change surfaces to the user; never encode a guess.

## Step 6 — Lint, then update the feature overview

```bash
bash ${CLAUDE_PLUGIN_ROOT}/scripts/goalforge-section-lint.sh <wp-path>/overview.md
bash ${CLAUDE_PLUGIN_ROOT}/scripts/goalforge-validate.sh --feature <feature> --show <PLANS_ROOT>
```

Section lint exit 2 = a disallowed H2. Fix every `invalid YAML frontmatter`
ERROR here — malformed frontmatter reads as an empty `status:` downstream.
Then set `work_packages:` to the WP slug list, fill the Work Packages table
(`WP | Title | Status`, every row `spec`), set the feature `updated:` and each WP
`stage_updated:` to today, then report one line per WP — `wp-NN-<slug> (<M>
checklist items, contract_slice: [C1, C3])` — and `Next: goalforge-harden <wp>`.

## Add-WP mode (`--add-wp <slug> --goal "<outcome>"`)

Append ONE WP: Steps 2-6 for that WP alone, numbered with the next free `NN`,
touching no existing WP. Optional overrides for `depends_on`, `severity` and
`task_type`, plus `--derived-from <ref>` (stamped verbatim as a top-level
`derived_from:` scalar and a `relationships:` mirror row) and repeatable
`--source <record>` (appended verbatim to the feature `sources[]`) — both
schema-blind: stamped, never parsed. A learning that changes or drops an
existing WP is a restructure: use `goalforge-redecompose`.

## Gotchas

- Folder-level idempotency means editing `spec.md` and re-running does NOT
  update an already-stamped WP — delete the folder to force a re-stamp.
- A live or manual step inside a `strategy: deterministic` command is the most
  common decompose defect: harden's V5 lint blocks on it.
- The section lint checks H2 names, not line shape: a checklist item citing no
  behavior id passes it, and only self-check rule 2 catches it.
