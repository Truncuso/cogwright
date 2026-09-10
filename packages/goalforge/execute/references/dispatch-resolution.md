# goalforge-execute — Dispatch resolution detail

Behind the `goalforge-pick-agent.py --task <wp>/overview.md --role implement`
call in `SKILL.md` §3. `references/dispatch.yaml` is the single configuration
file; `--dispatch <path>` overrides it (tests pass a fixture). No provider is ever named in a SKILL.md.

## Resolution order

1. **Stage row** — `dispatch.yaml` `stages:<role>` gives `model`, `effort`,
   `provider`, `endpoint`, `egress`. The stage keys are exactly the `ROLE_TIER`
   keys; an unknown role raises `EscalationRequired`, never a silent default.
2. **Agent + expertise** — the role maps to one roster agent under `agents/`;
   `references/expertise-map.yaml` resolves the reading list (`by_tag` →
   `by_task_type` → `by_extension`, order-preserving union) into the brief's
   `Expertise refs:` slot. The map never names a dispatch target.
3. **Provider preference** — `providers:` is an ordered list, first entry the
   default. Resolution starts at the stage row's `provider` and walks the list
   from there. No budget accounting.
4. **Leaf seam** — a non-native provider is reached through its
   `headless_dispatch` leaf (`leaf-interface.md` v1) named by `providers[].leaf`.
5. **Fall-through** — leaf exit `1` (unreachable), `2` (model not found), or `4`
   with reason `plan_quota_exhausted` / `metered_rate_limited` (no result
   envelope) advances to the next provider. Exit `4` with `budget_exceeded` /
   `budget_check_failed` is **not** a fall-through: the turn completed, its
   result is kept and a WARN row names the overspend. An exhausted list raises
   `EscalationRequired`.
6. **Propose-only ledger** — every resolution whose provider `kind` is not
   `native` is propose-only and appends one row at `GOALFORGE_DISPATCH_LEDGER`
   (default `${CLAUDE_CONFIG_DIR:-$HOME/.claude}/data/dispatch-decisions.jsonl`).
   Ledger I/O degrades, never blocks.
7. **Admission seam** — `admission.resolve(role, task_class, provider)` runs for
   role `implement` before propose-only marking; today it admits only the native provider, and `--admitted <path>` is parsed and reserved (wp-06 fills both).

The verification strategy comes from the WP's own `goal.verification.strategy`
and is never inferred here.

## Model + effort

Both come from the stage row verbatim; the human-readable projection of the
role bands is `references/tier-map.md` (generated — do not hand-edit). The
`implement` row is `by_register`: resolved from the WP's `register:` (and
`severity:` / blast radius), which is why a WP with no `register:` is a usage
error rather than a guess. Graders (`judge`, `wp-verify`) are pinned to
`opus`@`high` on every profile so a grader is never the executor's twin
(ticket-48). Every brief states model AND effort explicitly, never the agent default.

## Endpoint (ticket-62)

`endpoint:` is the dispatch sense of the retired `route:` field — WP frontmatter
`route:` is gone from the schema and ignored where legacy plans still carry it.

- `session` — runs in-session on the native provider. The **Agent tool** sets
  `model` per agent but inherits session effort; the **Workflow tool** is the
  only surface with a per-agent effort knob, so a batch mixing efforts uses it.
- `leaf` — the headless `headless_dispatch` CLI of a non-native provider, with
  `--max-budget-usd` from the provider row. Always propose-only.

## Egress classes

`egress:` on a stage row bounds what leaves the session for that dispatch:
`none` < `diff-only` < `overview` < `full`.

| class | payload |
|-------|---------|
| `none` | nothing — skip with reason `egress-none`, no leaf call |
| `diff-only` | the diff |
| `overview` | diff + `overview.md` (shipped default on every egressing row) |
| `full` | diff + `overview.md` + `spec.md` + `findings.md` |

A feature `spec.md` frontmatter `egress:` may only **narrow** a stage row; a
widening value is ignored with a WARN row. No content is redacted in any class.

## Workflow compile surface

When C5 batching applies, `scripts/goalforge-workflow-compile.py <wp>/overview.md
--dispatch <path>` turns the `## Checklist` into `run/workflows/<wp>.js`:
disjoint `{files:}` sets become `parallel` nodes of 3-5 items, an overlap forces
a `pipeline` edge, and gates A/B/C plus the second opinion are nodes carrying
`{model, effort}` from their own stage rows. The emitted script is launched
through the Workflow tool — a session surface.
