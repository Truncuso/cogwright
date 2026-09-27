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
   `admitted_override` name the table that produced the verdict —
   `admitted_source` package-relative (`references/`) or plans-relative
   (`plans/…`), never an absolute host path. Ledger I/O degrades, never blocks.
7. **Admission** — `admission.resolve(role, task_class, provider, model)` runs
   for role `implement`: the admission table decides the resolver verdict
   (`references/admission.md`). A provider's `kind` is DERIVED, not taken from
   the row: `kind: native` carrying a `leaf`, or reached through a stage row
   whose `endpoint` is not `session` or `egress` not `none`, is refused at exit
   2 (it would otherwise skip the table entirely), as are two provider rows
   sharing a `name`. An admitted row binds the leaf closure as well as the
   triple — `leaf` + `leaf_sha256` must match the provider row's leaf and that
   file's current content, and `leaf_closure` must hash every regular file
   under the leaf's directory tree, so repointing `providers[].leaf` or editing
   a sibling the leaf sources inherits nothing.
   `--admitted <path>` overrides the shipped
   `references/admitted-providers.yaml` from inside the package root or the
   plans root only (resolved, symlinks followed, exit 2 outside, one stderr
   WARN when active); its absence reads the shipped table and
   is never a skip. A refused non-native provider is replaced by the first
   `kind: native` provider (exit 2 when the dispatch file lists none, or when
   that fallback target is itself incoherent); an
   admitted one carries the containment block, the evidence ref and the
   permission set as DECLARED data, with a stderr WARN saying so. A matching
   row whose `max_egress` ranks below the stage row's `egress` is refused
   (`egress incoherent`). Whether an admitted row EXECUTES is the workflow
   compile's decision — see "Admitted execution" below.

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

## Admitted execution (wp-08)

An `implement` row on a non-native provider compiles if and only if the
admission table admits it for the WP; every other non-native implement row
exits 2 naming the missing `(task_class, provider, model)` admission.

- **Default table only.** The compiler reads ONLY the shipped
  `references/admitted-providers.yaml` (`goalforge_admission.ADMITTED_PATH`,
  read at call time) through `goalforge-pick-agent.resolve_and_log`, which
  writes the one ledger row. Its interface contract carries NO override: no
  flag, no environment variable and no dispatch-file key names another table,
  so a non-default admission table is refused unconditionally. A missing or
  unreadable table fails CLOSED with its own reason, never as an empty table.
- **Coherence.** The dispatch row's `egress` must be `<=` the admitting row's
  `max_egress` over `none < diff-only < overview < full`.
- **HEAD binding.** The table path is resolved exactly ONCE, by the caller,
  and that one real path serves the byte read, the HEAD read and the guard
  check. The admitting table's bytes (read once) must equal
  `git show HEAD:<rel>` in the repository enclosing that real path, read with
  every `GIT_*` variable scrubbed, `<rel>` taken against the physical
  `--show-toplevel` (a symlinked ancestor is fine) and required to match the
  pre-commit guard's set `(?:.*/)?references/admitted-providers\.yaml` end to
  end, with no control character; outside a git work tree, absent from HEAD,
  or a real path outside that set, the compile exits 2. That repository must
  also carry the goalforge pre-commit
  (`scripts/goalforge-install-hooks.sh`'s marker block invoking this package's
  `hooks/goalforge-pre-commit.sh`), and no global or system `core.hooksPath`
  may be set. Consequence: admitted execution needs a git checkout with the
  goalforge pre-commit installed — an installed plugin copy with no `.git`
  never admits. The pre-commit in turn blocks any commit that adds or changes
  an `admitted:` row unless the user confirms interactively on the terminal.
- **Leaf-leg emission.** The foreign model is never an `agent()` node.
  Pipeline stage 1 is a NATIVE runner `agent()` (the `discovery` row's
  model/effort, output schema `{exit_code, stderr, stdout}`) whose only action
  is the call `scripts/goalforge-leaf-exec.sh <task_class> <provider> <model> <
  <brief file>` — keyed by the admission row, with no hash and no table
  argument. The brief is the WP overview.md bytes at HEAD when the overview is
  tracked (in the index of the repository enclosing its real path, which may
  be a nested `plans/` repository; a tracked overview whose HEAD read fails,
  e.g. staged but never committed, exits 2), else its working-tree bytes; the
  one ledger row carries `brief_source: head|worktree`. The compile writes it
  to `plans/<feature>/<wp>/leaf-brief.txt` (a plans root outside any git work
  tree exits 2). Gate B and gate C are stages 2 and 3, each run only when
  stage 1's `exit_code` is 0. The leg's provider, model, effort (the runner
  node's only; the leaf runs at its provider default), evidence ref,
  permission set, containment block, `leaf` + `leaf_sha256` and
  `enforced: false` travel as data.
- **The wrapper.** `goalforge-leaf-exec.sh` accepts exactly the three row-key
  arguments, reads the table only script-relative, re-derives `leaf`,
  `leaf_sha256` and `leaf_closure` from the HEAD-bound table, requires the
  leaf's real path to lie under the leaf root, re-hashes the leaf and its
  closure and exits 2 without running it on any mismatch. A brief over
  `goalforge-second-opinion.sh`'s `MAX_PAYLOAD_CEILING` raw bytes or holding a
  NUL also exits 2. Otherwise it runs the leaf per leaf-interface v1 as
  `--model <model> --provider <provider> --prompt <brief> --output <tmp file>`,
  prints the `--output` file to stdout and returns the leaf's status.
- **`--test-tiers`** has no WP and so no task class. It applies the
  EXISTENTIAL rule: a non-native implement row passes iff SOME admission row,
  for any task class, binds its provider, model, the provider row's leaf, a
  current `leaf_sha256` and `leaf_closure`, and `max_egress >= egress`. The per-WP task-class
  decision, the HEAD binding and the wrapper stay with the compile.
- **Advisor-only.** An implement row whose model is `fable` exits 2 on both
  the admitted and the native path.
