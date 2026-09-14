# admission fixtures (wp-06)

Tables, dispatch configs and WP frontmatter for `goalforge-admission.test.sh`.
Every admission fixture names its task class in the LITERAL-extension spelling
(`code/py`, `code/sh`, `code/yaml`) — the only spelling the derivation emits.

* `admitted-ok.yaml` — the one valid table: `code/py` on `ollama`/`glm-5.3:cloud`.
* `bad-*.yaml` — one sabotage per required key (and one `self-report` kind).
* `dispatch-*.yaml` — dispatch configs whose `implement` row names a provider.
* `wp-*.md` — WP frontmatter: task class, owned_files, verification command.
