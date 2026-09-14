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
6. **Dispatch decision ledger** — one row per decision at
   `GOALFORGE_DISPATCH_LEDGER` (default
   `${CLAUDE_CONFIG_DIR:-$HOME/.claude}/data/dispatch-decisions.jsonl`), written
   by the ONE writer in `goalforge-pick-agent.py`: a resolution left at the
   non-native default, and every admission decision (§7 — the admission table
   decides the resolver verdict). `decision` discriminates
   `propose-only | admitted | refused`, and `admitted_source` /
   `admitted_override` name the table that produced the verdict. Ledger I/O
   degrades, never blocks.
7. **Admission** — `admission.resolve(role, task_class, provider, model)` runs
   for role `implement`: the admission table decides the resolver verdict
   (`references/admission.md`). `--admitted <path>` overrides the shipped
   `references/admitted-providers.yaml`; its absence reads the shipped table and
   is never a skip. A refused non-native provider is replaced by the first
   `kind: native` provider (exit 2 when the dispatch file lists none); an
   admitted one carries the containment block, the evidence ref and the
   permission set as DECLARED data, with a stderr WARN saying so. The compiler
   still refuses to emit a non-native `implement` row until
   `wp-08-admitted-execution`.

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
  `--max-budget-usd` from the provider row. Propose-only unless the admission
  table decides the resolver verdict is `admitted` for the WP's task class. The payload
  goes as a `--prompt` **argv value** under the configured
  `second_opinion.max_payload_bytes` cap (clamped to the reviewed ceiling
  `102400` with a WARN — one argv string must stay inside `MAX_ARG_STRLEN`).
  `--prompt-file` is NOT used because the configured leaves ollama, zai and
  deepseek route it through `_core/prompt_file.py` as a structured handoff
  brief (raw payload → leaf-exit-3); the codex leaf reads it raw and would
  accept one, so this is a property of the configured row, not of
  leaf-interface v1 (verified 2026-09-13).

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
--dispatch <path> [--expertise <path>]` turns the `## Checklist` into
`run/workflows/<wp>.js`: disjoint `{files:}` sets become `parallel` nodes of 3-5
items, an overlap forces a `pipeline` edge, and gates B and C are `agent` nodes
carrying `{model, effort}` from their own stage rows. Gate A (deterministic) and
the second opinion (a leaf leg on a non-native provider, so its `model` is a
provider id `agent()` cannot dispatch) are `log()` lines naming their command —
no `agent` node the compiler emits ever carries a non-Claude model id. The
emitted script is launched through the Workflow tool — a session surface.
