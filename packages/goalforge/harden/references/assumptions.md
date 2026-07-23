# Machine-checkable Assumptions block (harden → execute recheck)

Full protocol for the `## Assumptions` block goalforge-harden writes into a WP's
`overview.md`. Inline summary lives in `SKILL.md` § Assumptions; this file is the
format + trust-boundary + recheck-row detail, consulted only when authoring an
assumption block or debugging a recheck.

Harden records the WP's working assumptions as a **machine-checkable**
`## Assumptions` block so `goalforge-execute` can re-verify them at preflight before
building on a stale premise. This is distinct from the dated
`## [DATE] Assumption: …` rationale entries appended to `findings.md` in Step 1
(those are the human-readable audit trail; this block is the **recheck input**).

Write the block into the WP's `overview.md` body — one list entry per assumption:

```
## Assumptions

- key: <stable-slug>               # the findings mismatch row is keyed on this
  assumption: <one-line statement>
  check: <cheap shell command>     # OPTIONAL — author-written, RUN at recheck
  expect: <substring stdout must contain>   # OPTIONAL
```

- `check` is **optional** — an assumption with no `check` is documentation only
  (recorded, never re-run).
- With a `check` and a non-empty `expect`, a mismatch is `expect` not appearing in
  the command's stdout. With a `check` and an empty `expect`, a mismatch is the
  command exiting non-zero.

**Trust boundary (distinct from the task `verify:` lint).** The `check` commands
here are **author-written to be executed** at recheck — the harden author wrote
them and vouches for them. This is NOT the untrusted task `verify:` string, which
the verb-lint only inspects (`command -v` on its first token) and **never runs**.
Keep the two separate: assumption `check`s are executed; `verify:` strings are
linted.

**Execute Step 0b re-runs them.** At the goal-resolution preflight `goalforge-execute`
calls `~/.claude/skills/goalforge/scripts/goalforge-assumption-recheck.sh <wp>/overview.md`,
which runs each `check` and, on a mismatch, writes a keyed, idempotent row to the
WP's `findings.md`:

```
## [YYYY-MM-DD] Assumption mismatch: <key>
assumption: <text>
expected: <text>
actual: <text>
check-cmd: <text>
```

Re-running updates the keyed row in place — it never appends a duplicate.

**Script detects; human decides (the split).** The recheck script
*deterministically* detects and *logs* a stale assumption; it does **not** gate. A
logged mismatch is **not** an auto-abort — `goalforge-execute` records it and leaves the
proceed-or-stop call to operator judgment (assumption-recheck is judgment, not a
deterministic gate, per the WP goal constraint).
