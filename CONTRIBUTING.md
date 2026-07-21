# Contributing to cogwright

Thanks for considering a contribution. This marketplace values small, verified,
honestly-labelled changes over big ambitious ones.

## Ground rules

- **Surgical changes.** Touch only what your change requires; match existing
  style; don't reformat or "improve" adjacent code.
- **Every skill ships evals.** A new or changed skill includes deterministic
  eval cases (`skills/<name>/evals/`) that pass locally. CI validates plugin
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

```
plugins/<name>/
  .claude-plugin/plugin.json     # name, version, description
  relations.yaml                 # optional: declared relations (requires/recommends/vendors/…)
  skills/<skill>/SKILL.md        # + scripts/, references/, evals/ per skill
  commands/  hooks/              # optional
  .vendored-allowlist.txt        # if anything is vendored
```

## Workflow

1. Fork, branch from `main`.
2. Make the change; run the plugin's evals and the structure validation.
3. Conventional Commits (`type(scope): subject`, ≤72 chars; body for feat/fix).
4. Open a PR describing what changed and how you verified it.

Questions and proposals: open an issue first for anything structural.
