# Provider admission (wp-06)

`references/admitted-providers.yaml` is the table; `scripts/goalforge-admission.py`
is the loader, the task-class derivation, and the verdict function;
`scripts/goalforge-pick-agent.py` is the only caller and the only ledger writer.

The admission table decides the resolver verdict for role `implement`. Since
wp-08 it also gates EXECUTION: `goalforge-workflow-compile.py` emits an
admitted non-native implement row as a leaf leg run through
`scripts/goalforge-leaf-exec.sh`, but only from the shipped table, only when
its bytes are the committed HEAD content of a goalforge-guarded repository —
see `execute/references/dispatch-resolution.md` § Admitted execution.

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
| `leaf` | string | The agent-dispatch executable the evidence was gathered against, relative to `CLAUDE_CONFIG_DIR` (default `~/.claude`). Must equal the `providers[].leaf` of the dispatch row being resolved. |
| `leaf_sha256` | string | That file's sha256 at admission time. |
| `leaf_closure` | mapping | The leaf CLOSURE: leaf-root-relative path → sha256 for EVERY regular file under the `leaf` entry file's REAL parent directory (the directory the executed file runs from), recursively (the entry file included; no `source` line is parsed). A listed file missing or unreadable, a file under the tree absent from the manifest, or any symlink — at the entry path itself or anywhere under the entry's real parent tree — is a mismatch — refused (a symlinked ancestor above the leaf root, or an in-root symlinked directory between the root and the entry's directory, is resolved: the real path re-keys the closure), and `scripts/goalforge-leaf-exec.sh` exits 2 without running the leaf. Any edit under the leaf's tree therefore needs a re-pinned manifest. |
| `evidence.kind` | enum | `user-experience` \| `benchmark` \| `user-addition`. A closed set: `self-report` is not evidence. |
| `evidence.ref` | string | Where the evidence lives (a locator the user can re-read). |
| `permission_set` | list | The permission posture the admitted dispatch is meant to run under. Must be a LIST — a bare string is truthy but would explode into per-character permissions. POSTURE DOCUMENTATION, declared data — see "Declared, not enforced". |
| `max_egress` | enum | `none` \| `diff-only` \| `overview` \| `full` — the declared egress CEILING of the admitted dispatch. A dispatch row whose declared `egress` ranks above it (`none < diff-only < overview < full`) is refused, `egress incoherent`. Both values are declarations: this is a coherence check between two declarations, not a runtime egress control. |

Every key is required. The loader exits `2` naming the row index and the
offending key (`missing required key 'max_egress'`, `missing required key
'leaf_closure'`; an out-of-enum value reads
`max_egress '<v>' not in {none, diff-only, overview, full}`); nothing is
resolved from a table that failed validation.

## The table's HEAD binding (wp-08 T13)

An admitting table must be the committed HEAD content of the package's OWN
checkout, at the canonical table's own repository path. One shared helper,
`bind_table` in `scripts/goalforge-admission.py`, binds it for both bound
callers: the workflow compile (`resolve_and_log(bind_head=True)`) and the leaf
wrapper (`verify_leaf`). It takes no table path: it binds only
`ADMITTED_PATH`, and neither `verify_leaf`, `--verify-leaf` nor
`scripts/goalforge-leaf-exec.sh` accepts one. `ADMITTED_PATH` is
PKG_ROOT/references/admitted-providers.yaml, and PKG_ROOT is the admission
script's own real location (the wrapper finds that script at
`$(dirname "$0")`), so the package identity is bound instead (step 2): a shim
of symlinked scripts resolves to the package's own script and table; an
UNTRACKED shim of copied or hard-linked scripts at another path is refused by
step 2, and a COMMITTED shim passes step 2 and is refused by the guard-identity
walk of step 4. So no shim makes either caller bind another committed table.
`resolve_admitted_path` stays unbound, so `--test-tiers` and pick-agent's CLI
need no git work tree.

1. The top level is the physical `git rev-parse --show-toplevel` of
   realpath(PKG_ROOT); no top level exits 2, failed CLOSED. It must contain
   realpath(PKG_ROOT), else exit 2, failed CLOSED (a repository-local
   `core.worktree` can move it below the package).
2. The package identity: the admission script's real path, resolved once at
   module scope (`_OWN`, from which PKG_ROOT is derived), must be committed at
   its path under that top level and byte-equal to that HEAD blob
   (`git show HEAD:<rel>`), else exit 2. An UNTRACKED copy, or a hard link at
   a stray path, is absent from HEAD and refused here; a hard link AT the
   tracked path is the file itself. A COMMITTED shim (copy or hard link at
   another tracked path) passes this step: its PKG_ROOT then names a guard
   location that is not the installed one, and step 4 refuses it.
3. The table path is walked component by component. A symlink component
   located at or below that top level (the table file, `references/`, or any
   directory between) exits 2 naming the symlink. A symlink component located
   above it is resolved with one full realpath, which follows its whole target
   chain, in-tree hops included. In production no such component exists:
   ADMITTED_PATH is built on realpath(PKG_ROOT), so only `references/` and the
   file can be symlinks, and both are refused. Only the in-process seam can
   pass a logical path through an ancestor symlink (`~/.claude ->
   dotfiles/claude`). The walked path must lie inside realpath(PKG_ROOT); its
   rel is taken against the top level.
4. The HEAD read and the guarded-repository check run `git -C <top level>`
   with that rel, never at the table's own directory. So neither a linked
   worktree, a nested or foreign repository, nor a path swapped in after the
   walk supplies the bytes: a swap can only cause a mismatch. The guard's
   identity, PKG_ROOT/hooks/goalforge-pre-commit.sh, is walked the same way
   (a symlink component at or below the top level exits 2) and must equal the
   realpath of a path the installed marker block invokes. The comparison is
   asymmetric: the package side is walked (in-tree symlinks refused), the
   marker-block side is fully realpath'd (in-tree symlinks followed). So it
   pins the guard's LOCATION, not the hook file's content: overwriting the
   tracked hook in place is the accepted forged-hook residual.
5. Every git call of the binding and the brief's HEAD read runs
   `git -c core.useReplaceRefs=false` with `GIT_NO_REPLACE_OBJECTS=1` set
   after the `GIT_*` scrub. The variable alone is not enough: a
   repository-local `core.useReplaceRefs=true` re-enables replace refs over
   it, while command-line config outranks repository config. Together they
   keep a `refs/replace` entry from substituting bytes the pre-commit guard
   never saw.

The guard-set `re.fullmatch` of `(?:.*/)?references/admitted-providers\.yaml`
and the refusal of a rel holding a control character are defense in depth:
with the production path fixed to the canonical table for both the compile and
the wrapper, they are reachable only through the in-process `ADMITTED_PATH`
seam, not the binding.

Residual: an actor able to write the repository's `.git/config` is outside the
threat model, the same trust class as a forged hook file. The two reproduced
`.git/config` routes (`core.useReplaceRefs`, a `core.worktree` below the
package) are closed anyway by steps 5 and 1. Further repository-local keys
that redirect object or work-tree lookup (for example a `core.worktree` above
the real top level) are recorded, not fixed.

This binding and the `leaf_closure` rule (c) govern different paths and do not
conflict. Rule (c) governs the LEAF path under the leaf root, where an in-root
symlinked directory between the root and the entry's directory is RESOLVED:
the leaf's integrity rests on content (the entry hash plus a closure manifest
keyed by real path, so a repoint changes the keys and is caught). The table
binding governs the TABLE path under PKG_ROOT, where every symlink component
located at or below the top level is REFUSED: the table's integrity rests on
location (the HEAD read of the one path the pre-commit guard watches, at the
package's own top level). Both resolve a symlink component located above
their root with a full realpath (binding step 3).

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

The `kind` a provider row DECLARES is not evidence of what it is. `native` is
the one kind that skips the table outright and the target every refusal falls
back to, so it is DERIVED: a row declaring `kind: native` while carrying a
`leaf`, or reached through a stage row whose `endpoint` is not `session` or
whose `egress` is not `none`, is incoherent and the resolver exits `2` naming
it — at load time for the row itself, at resolve time for the stage pairing,
and again on the fallback target. Two provider rows sharing a `name` are
refused at load for the same reason: only the first would ever be read.

`resolve(role, task_class, provider, model, table, *, leaf_root=None)`:

* provider `kind: native` — admitted, unconditionally; the table governs
  non-native providers.
* a row whose `task_class`, `provider` and `model` all match AND whose
  `leaf`/`leaf_sha256` match the provider row's leaf path and that file's
  current content AND whose `leaf_closure` matches the leaf's directory tree
  AND whose `max_egress` covers the stage row's `egress` — admitted, carrying
  `evidence.ref`, `permission_set`, `leaf`, `leaf_sha256` and `max_egress`.
* a row matching the triple whose `leaf` names another path, whose recorded
  hash is not the file's current one, whose leaf cannot be read, or whose
  `leaf_closure` does not match the tree — refused: admission binds the leaf
  closure, and repointing `providers[].leaf` under an admitted provider name
  inherits nothing.
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
none-means-skip path. `--admitted` is a test seam, not an arbitrary-file read:
the path is RESOLVED (symlinks followed) and must land under the package root
or the plans root, or the resolver exits `2` — the same containment the default
table is held to. An active override prints one WARN line on stderr naming the
table it reads, and the ledger records which table produced the verdict. A
table the caller NAMED must exist: a missing
`--admitted` / `--table` path exits `2` rather than degrading to an empty
table, so a typo cannot become a silent blanket refusal at exit 0. Only the
shipped table may be absent, and then it is empty — for the resolver verdict
alone. The EXECUTION decision (the workflow compile, the leaf wrapper) has no
empty-table fallback: a missing or unreadable table fails CLOSED with its own
load-failure reason.

## The ledger row

One shape, one writer (`append_ledger_row` in `goalforge-pick-agent.py`), one
row per dispatch decision. The keys are the writer's existing
`{ts, wp, role, provider, model, effort, endpoint, decision}` plus
`{task_class, reason, evidence_ref, admitted_source, admitted_override}`:

* `decision` is the sole discriminator over `admitted | refused | propose-only`.
* `provider`/`model` on a `refused` row name the provider that was REFUSED, not
  the native provider resolved in its place.
* `admitted_source` is the resolved path of the table that produced the verdict,
  recorded RELATIVE to the root that contains it (`references/` under the
  package, `plans/…` under the plans root) — never the absolute host path.
* `admitted_override` is `true` iff `--admitted` was passed — so a reader can
  tell a production decision from a fixture one.
* `reason`/`evidence_ref` are empty strings on a `propose-only` row.
* `brief_source` (`head` | `worktree`) appears only on the workflow compile's
  implement row: where the admitted leaf's brief came from (the tracked
  overview at HEAD, or an untracked/gitignored overview's working-tree bytes).

## Declared, not enforced

The leaf binding is the one thing this package CHECKS rather than declares: an
admitted verdict has hashed the leaf closure the dispatch row would run (the
entry file and every file under its directory tree). It is a check at VERDICT
time; for an admitted compile, `scripts/goalforge-leaf-exec.sh` re-hashes the
entry file and the closure against the HEAD-bound table immediately before
running it. That narrows, but does not close, the gap the risk row below names:
dependencies outside the leaf's tree (`PATH` binaries, env-selected paths) are
not hashed, and the leaf re-reads its files after the wrapper hashed them.

The containment block and `permission_set` are validated and carried as DATA.
Nothing in this package enforces them at dispatch time: agent-dispatch's only
knob today is `security.allow_skip_permissions_backends`, and there is no
per-dispatch permission flag. An admitted resolution therefore prints ONE WARN
line on stderr stating that containment and `permission_set` are declared and
not enforced. That WARN is the runtime signal for the
`permission-set-declared-not-enforced` risk in the wp-06 overview; the shipped
table is empty precisely so the risk stays latent until a user accepts it.
