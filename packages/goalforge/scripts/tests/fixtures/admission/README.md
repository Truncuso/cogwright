# admission fixtures (wp-06)

Tables, dispatch configs and WP frontmatter for `goalforge-admission.test.sh`.
Every admission fixture names its task class in the LITERAL-extension spelling
(`code/py`, `code/sh`, `code/yaml`) — the only spelling the derivation emits.

* `admitted-ok.yaml` — the one valid table: `code/py` on `ollama`/`glm-5.3:cloud`.
* `bad-*.yaml` — one sabotage per required key (and one `self-report` kind).
* `dispatch-*.yaml` — dispatch configs whose `implement` row names a provider.
* `wp-*.md` — WP frontmatter: task class, owned_files, verification command.

Fix lap (S-1/S-2/S-3): admission binds the EXECUTABLE and derives the provider
kind, so these carry the trust-boundary cases:

* `leaf/headless_dispatch` — the executable `admitted-ok.yaml` binds. The test
  installs it under a temp `CLAUDE_CONFIG_DIR`, so the leaf hash never depends
  on the host's corpus; editing it means re-recording `leaf_sha256`.
* `admitted-leaf-repoint.yaml` / `admitted-leaf-stale-hash.yaml` /
  `bad-missing-leaf.yaml` — the leaf binding refused three ways.
* `dispatch-native-with-leaf.yaml` (loader), `dispatch-native-endpoint-leaf.yaml`
  (resolution) and `fallback_target.py` (fallback target, library entry point) —
  a self-declared `kind: native` that would skip the table.
* `dispatch-dup-names.yaml` — two provider rows, one name.

wp-08 (admitted execution): every row carries the required `max_egress`, and
`leaf/headless_dispatch` touches `$LEAF_MARKER` and exits `${LEAF_EXIT:-0}`
when run, so the leaf-wrapper cases can tell "executed" from "refused".

* `admitted-egress-{none,diff-only,full}.yaml` — `admitted-ok.yaml` differing
  only in `max_egress` (coherence pairs; `--test-tiers` egress case).
* `admitted-empty.yaml` — a well-formed table that admits nothing.
* `admitted-fable.yaml` — admits `fable`; the compile must still refuse it.
* `admitted-other-model.yaml` / `admitted-code-sh.yaml` — same provider,
  another model / another task class only (`--test-tiers` existential rule).
* `bad-missing-max-egress.yaml` / `bad-max-egress-enum.yaml` — loader refusals.
* `compile_seam.py` / `tiers_seam.py` — drive the compiler and `--test-tiers`
  in process through `goalforge_admission.ADMITTED_PATH` (and the dispatch
  loader's path); no CLI flag exists for either.
