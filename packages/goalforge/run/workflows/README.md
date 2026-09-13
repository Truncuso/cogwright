# run/workflows/ — compiler output

`scripts/goalforge-workflow-compile.py <wp>/overview.md` writes `<wp-name>.js`
here: the WP checklist as a Workflow-tool script (batch nodes by `{files:}`
disjointness, then gates B and C as `agent` nodes; gate A and the second
opinion are `log()` lines naming their deterministic command / leaf script).

Compiled scripts are checked in on purpose — they are meant to be read and
diffed before anyone runs `Workflow({scriptPath: "…"})`. Regenerate rather
than hand-edit; every file here carries a GENERATED banner.
