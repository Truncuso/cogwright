# Contributing to cogwright

Thanks for considering a contribution. This marketplace values small, verified,
honestly-labelled changes over big ambitious ones.

## Ground rules

- **Surgical changes.** Touch only what your change requires; match existing
  style; don't reformat or "improve" adjacent code.
- **`packages/` is authored, `plugins/` is generated.** Edit the package tree,
  then run `scripts/goalforge-generate.sh` to regenerate the plugin artifact;
  never hand-edit anything under `plugins/`. `scripts/goalforge-generate.sh
  --check` fails CI when the two disagree. See the Repository-layout table in
  the README.
- **Every skill ships evals.** A new or changed skill includes deterministic
  eval cases that pass locally. Two shapes, both authored: per-skill cases under
  `packages/<pkg>/<skill>/evals/` (e.g. `packages/goalforge/execute/evals/`),
  and package-level cases spanning several skills under `packages/<pkg>/evals/`
  (e.g. `packages/goalforge/evals/`). Evals live in the authored tree only — the
  generator excludes them from the plugin artifact. CI validates plugin
  structure on every push.
- **Honest status.** Don't label anything further along than it is — README
  catalog statuses are *shipped / in development / planned* and must stay true.
- **One name per thing.** Before adding a system/skill, check the catalog and
  existing plugins for a prior name; duplicates are treated as bugs.
- **Vendored content is declared.** Any file copied from elsewhere gets a line
  in the plugin's `.vendored-allowlist.txt` with source and retrieval date.
- **Attribution.** If your contribution adopts someone's published idea or
  pattern, add the source to the plugin's docs and (suite-wide inspirations)
  `ACKNOWLEDGEMENTS.md` — miscrediting is a bug, see that file.

## Plugin shape

This is **generated output** — the shape `scripts/goalforge-generate.sh` emits
from the authored package tree. Do not edit it by hand.

```
plugins/<name>/
  .claude-plugin/plugin.json     # name, version, description
  relations.yaml                 # optional: declared relations (requires/recommends/vendors/…)
  skills/<skill>/SKILL.md        # + scripts/, references/ per skill
  commands/  hooks/              # optional
  .vendored-allowlist.txt        # if anything is vendored
```

## Prerequisites

- `claude` — Claude Code CLI on your `PATH`; check with `claude --version`.
  Required for the structure validation (`claude plugin validate --strict`),
  which CI skips with a warning when the CLI is absent. The eval harnesses are
  plain bash and do not invoke it.
- `bash`, `git`, `python3` (with PyYAML), `jq` — as in [INSTALL.md](INSTALL.md).

## Workflow

1. Fork, branch from `main`.
2. Make the change; run the plugin's evals and the structure validation.
3. Conventional Commits (`type(scope): subject`, ≤72 chars; body for feat/fix).
4. Open a PR describing what changed and how you verified it.

Questions and proposals: open an issue first for anything structural.
