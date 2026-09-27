# admission fixtures (wp-06)

Tables, dispatch configs and WP frontmatter for `goalforge-admission.test.sh`.
Every admission fixture names its task class in the LITERAL-extension spelling
(`code/py`, `code/sh`, `code/yaml`) — the only spelling the derivation emits.

* `admitted-ok/references/admitted-providers.yaml` — the one valid table:
  `code/py` on `ollama`/`glm-5.3:cloud`. Every ADMITTING table lives at
  `<case>/references/admitted-providers.yaml` (wp-08 T12): the compile's HEAD
  read admits only from a path the pre-commit guard's set
  `(?:.*/)?references/admitted-providers\.yaml` fully matches.
* `bad-*.yaml` — one sabotage per required key (and one `self-report` kind).
* `dispatch-*.yaml` — dispatch configs whose `implement` row names a provider.
* `wp-*.md` — WP frontmatter: task class, owned_files, verification command.

Fix lap (S-1/S-2/S-3): admission binds the leaf closure and derives the
provider kind, so these carry the trust-boundary cases:

* `leaf/` — the tree `admitted-ok.yaml` binds: `headless_dispatch` (the entry
  file, `leaf_sha256`), `helper.sh` and `lib/common.sh` (with the entry file,
  the `leaf_closure` manifest). The tests install the whole tree under a temp
  `CLAUDE_CONFIG_DIR`, so no hash depends on the host's corpus; editing any
  file under `leaf/` means re-recording `leaf_sha256` / `leaf_closure` in every
  `admitted-*` / `bad-*` fixture. The entry file enforces leaf-interface v1 §3
  (exit 1 without `--model`, `--prompt`, `--output`).
* `admitted-leaf-repoint.yaml` / `admitted-leaf-stale-hash.yaml` /
  `bad-missing-leaf.yaml` — the leaf binding refused three ways.
* `dispatch-native-with-leaf.yaml` (loader), `dispatch-native-endpoint-leaf.yaml`
  (resolution) and `fallback_target.py` (fallback target, library entry point) —
  a self-declared `kind: native` that would skip the table.
* `dispatch-dup-names.yaml` — two provider rows, one name.

wp-08 (admitted execution): every row carries the required `max_egress` and
`leaf_closure`, and `leaf/headless_dispatch` writes its argv (NUL-separated)
to `$LEAF_MARKER`, a JSON envelope to `--output`, and exits
`${LEAF_EXIT:-0}` when run, so the leaf-wrapper cases can tell "executed"
from "refused" and read the argv the wrapper built.

* `admitted-egress-{none,diff-only,full}/references/admitted-providers.yaml` —
  `admitted-ok` differing only in `max_egress` (coherence pairs; `--test-tiers`
  egress case).
* `admitted-empty.yaml` — a well-formed table that admits nothing.
* `admitted-fable/references/admitted-providers.yaml` — admits `fable`; the
  compile must still refuse it.
* `admitted-other-model.yaml` / `admitted-code-sh.yaml` — same provider,
  another model / another task class only (`--test-tiers` existential rule).
* `bad-missing-max-egress.yaml` / `bad-max-egress-enum.yaml` /
  `bad-missing-leaf-closure.yaml` — loader refusals.
* `compile_seam.py` / `tiers_seam.py` — drive the compiler and `--test-tiers`
  in process through `goalforge_admission.ADMITTED_PATH` (and the dispatch
  loader's path); no CLI flag exists for either.
* `mutate.py` — named, anchored known-bad mutations (the wp-08 T8-T12 ones are
  applied to the compile test's package replica by its `red()` helper).
* `structural.py` — AST checks: T9 (the leaf entry resolved once, by the
  caller) and T10 `single-resolution` (the table path resolved once).
