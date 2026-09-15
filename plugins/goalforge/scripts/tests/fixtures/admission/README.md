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
