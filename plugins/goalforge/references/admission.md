# Provider admission (wp-06)

`references/admitted-providers.yaml` is the table; `scripts/goalforge-admission.py`
is the loader, the task-class derivation, and the verdict function;
`scripts/goalforge-pick-agent.py` is the only caller and the only ledger writer.

The admission table decides the resolver verdict for role `implement`. It does
NOT decide execution: `goalforge-workflow-compile.py` still refuses to emit an
`agent()` node for a non-native stage row, so an admitted resolution is data
until `wp-08-admitted-execution` owns the compile-level exception.

## The three user conditions

From `plans/ideas/foreign-implement-dispatch-gated.md` (user direction
2026-09-10):

1. **Containment** — an admitted resolution carries a containment block
   (`owned_files` boundary, the WP's `verification.command`, `commit: false`).
2. **Evidence-only admission** — a row exists only because a closed-kind
   evidence record exists. No row, no admission.
3. **Per-task-class expression** — admission is granted for one task class at a
   time, never for a provider wholesale.

## Row shape

| Key | Type | Semantics |
|---|---|---|
| `task_class` | string | `<task_type>/<ext>` — see below. |
| `provider` | string | A `references/dispatch.yaml` `providers[].name`. |
| `model` | string | The provider's own model id. Admission binds the TRIPLE `(task_class, provider, model)`, never `(task_class, provider)` alone: a different model on the same provider is a different capability and needs its own evidence. |
| `evidence.kind` | enum | `user-experience` \| `benchmark` \| `user-addition`. A closed set: `self-report` is not evidence. |
| `evidence.ref` | string | Where the evidence lives (a locator the user can re-read). |
| `permission_set` | list | The permission posture the admitted dispatch is meant to run under. Must be a LIST — a bare string is truthy but would explode into per-character permissions. DECLARED data — see "Declared, not enforced". |

Every key is required. The loader exits `2` naming the row index and the
offending key; nothing is resolved from a table that failed validation.

## The task-class key

Deterministic, derived from the WP frontmatter alone:

    <task_type>/<ext>

`<ext>` is the LITERAL extension, no aliasing — `code/py`, `code/sh`,
`code/yaml`, never `code/python` or `code/bash`. It is the most frequent
extension over the FILE entries of the WP's own `owned_files` (directory
entries are excluded), ties broken by the lexicographically smallest
extension, and `-` when no file entry carries one.

The derivation input is the frontmatter's own `owned_files`, never a
per-invocation touched-file list: the key must not vary by caller, or the
admission decision would not be reproducible.

## Verdict

Before the table is consulted at all, the stage row must be able to DESCRIBE
the dispatch it would authorize. A non-native row is refused outright when:

* its `model` is a Claude tier rather than the provider's own model id — that
  model is the admission KEY, and a leaf exits 2 on a tier name (schema.md
  §`stages.<stage>`), so no honestly-authored row could match it;
* its `endpoint` is not `leaf`, or its `egress` is `none` — those two values are
  copied into the resolution, and a leaf dispatch declared as in-session or as
  non-egressing is a false declaration.

`resolve(role, task_class, provider, model, table)`:

* provider `kind: native` — admitted, unconditionally; the table governs
  non-native providers.
* a row whose `task_class`, `provider` and `model` all match — admitted,
  carrying `evidence.ref` and `permission_set`.
* a row matching `task_class` + `provider` but not `model` — refused, the
  reason naming both model ids.
* anything else — refused, the reason naming the missing admission.

A refused `implement` resolution falls back to the dispatch file's first
`kind: native` provider, with the implement STAGE row's model/effort resolved
as for a native provider and `endpoint`/`egress` narrowed to the in-session
pair (`session` / `none`) — the refused row's leaf endpoint and egress class
never survive the fallback. If the dispatch file lists no native provider there
is nothing to fall back to and the resolver exits `2` naming
`no native provider for fallback` — the refused row is never kept and never
resolved.

## Fail-closed default

`goalforge-pick-agent.py --admitted <path>` overrides the table path; ABSENT,
the shipped `references/admitted-providers.yaml` is read. There is no
none-means-skip path. `--admitted` is a test seam, and the ledger records which
table produced the verdict. A table the caller NAMED must exist: a missing
`--admitted` / `--table` path exits `2` rather than degrading to an empty
table, so a typo cannot become a silent blanket refusal at exit 0. Only the
shipped table may be absent, and then it is empty.

## The ledger row

One shape, one writer (`append_ledger_row` in `goalforge-pick-agent.py`), one
row per dispatch decision. The keys are the writer's existing
`{ts, wp, role, provider, model, effort, endpoint, decision}` plus
`{task_class, reason, evidence_ref, admitted_source, admitted_override}`:

* `decision` is the sole discriminator over `admitted | refused | propose-only`.
* `provider`/`model` on a `refused` row name the provider that was REFUSED, not
  the native provider resolved in its place.
* `admitted_source` is the RESOLVED path of the table that produced the verdict.
* `admitted_override` is `true` iff `--admitted` was passed — so a reader can
  tell a production decision from a fixture one.
* `reason`/`evidence_ref` are empty strings on a `propose-only` row.

## Declared, not enforced

The containment block and `permission_set` are validated and carried as DATA.
Nothing in this package enforces them at dispatch time: agent-dispatch's only
knob today is `security.allow_skip_permissions_backends`, and there is no
per-dispatch permission flag. An admitted resolution therefore prints ONE WARN
line on stderr stating that containment and `permission_set` are declared and
not enforced. That WARN is the runtime signal for the
`permission-set-declared-not-enforced` risk in the wp-06 overview; the shipped
table is empty precisely so the risk stays latent until a user accepts it.
