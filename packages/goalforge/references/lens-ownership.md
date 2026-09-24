# Lens Ownership

Every review concern class the goalforge chain checks has exactly one named
owner per review mode: harden G3's 3x panel, harden G3's single-pass
relaxation (`severity` below `HIGH` or `register` other than `production`),
and the verify cluster's Gate B / Gate C split. This table is the single home
for that mapping — `harden/SKILL.md` and `verify/SKILL.md` point here rather
than restate it.

## Concern-class ownership table

| Concern class | 3x-panel owner | Single-pass owner | Verify-cluster owner |
| --- | --- | --- | --- |
| `correctness` | code | harden G3 | Gate B |
| `error-handling` | code | harden G3 | Gate B |
| `complexity-delta` | code | harden G3 | Gate B |
| `root-cause-ai-slop` | code | harden G3 | Gate B |
| `goal-measurability` | eval | harden G3 | Gate C |
| `verification-coverage` | eval | harden G3 | Gate C |
| `owned-files-scope` | docs | harden G3 | Gate B |
| `contract-slice` | docs | harden G3 | Gate C |
| `depends-on-direction` | docs | harden G3 | Gate C |

3x-panel owners (`code`, `eval`, `docs`) are key names from
`references/expertise-map.yaml`'s `by_task_type`/`by_tag` maps — the closed
set a panel reviewer's expertise bundle is drawn from. They name which bundle
carries the concern when three `agents/reviewer.md` instances with distinct
bundles are convened; they are not a dispatch target of their own, and do not
assert that today's panel dispatch can route by concern class (it cannot —
harden's three reviewers get "distinct expertise bundles", not lens roles;
see `harden/SKILL.md:81-83`). Verify-cluster owners are the literal gate
headings `Gate B` and `Gate C` from `verify/SKILL.md`.

## Re-attribution rule

`harden/SKILL.md` G3 convenes the 3x panel only when `severity: HIGH` **and**
`register: production`; every other WP gets a single pass. That relaxation
skips every panel lens's dedicated bundle, so the single-pass column above
names `harden G3` — never a per-bundle owner — for every concern class: the
one reviewer that runs in the relaxed mode inherits every class the panel
would otherwise have split across three lenses. A skipped lens's concerns are
never recorded as skipped, deferred, or an accepted risk; they fold into
`harden G3`, the surviving pass, full stop.
