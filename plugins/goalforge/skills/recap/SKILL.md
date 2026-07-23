---
name: goalforge-recap
description: "Maintain a living, resumable recap.md per feature that traces the per-WP execution loop. The authoritative trace is ONE row per WP (record-wp): the task list, loop-back entries, and a per-WP status line carrying the SINGLE WP commit at WP altitude (no per-task commit column — the answer to 'trace too many commits'). append-task is optional live-progress. Regenerates the feature rollup on demand. Invoked by goalforge-execute (optional live append) and goalforge-verify (record-wp at WP finalization). Trigger: goalforge-execute or goalforge-verify delegates a record-wp, append-task, append-loopback, or rollup operation for a feature WP."
metadata:
  version: 2.0.0
---

Maintains `recap.md` — a living, idempotent execution trace for a feature's WP
loop. Each WP section records which tasks ran (task list, **no per-task commit
column**), any loop-backs (retries), and a finalized green/yellow/red status line
**carrying the single WP commit** at WP altitude. A `## Feature rollup` section at
the bottom tallies the per-color WP counts. The commit moved from per-task rows to
the per-WP Status line — the recap shows **one commit per WP**, the direct answer
to "trace too many commits" (it holds even when git history stays per-task).

Script: `${CLAUDE_PLUGIN_ROOT}/scripts/recap.sh`

---

## Trigger

Invoked by `goalforge-execute` (after each task, after each loop-back) and
`goalforge-verify` (at WP finalization). Also callable directly for manual audits.

---

## recap.md Lifecycle

```
init          → create the file with header (no-op if already present)
record-wp     → AUTHORITATIVE one-call WP record: ensure section + task rows +
                Status line carrying the single WP commit (green/yellow/red)
append-task   → OPTIONAL live-progress: add/UPDATE a task row (no commit column)
append-loopback → add a loop-back entry under the WP section
finalize      → write/UPDATE the WP Status line without a commit (legacy/manual)
rollup        → regenerate ## Feature rollup from all per-WP Status lines
```

Each operation is **idempotent**: running it twice with the same arguments
produces the same file. Task rows are never duplicated — the same
`<task-slug>` in the same WP section is updated in place.

---

## recap.md Section Model

The file follows this exact contract (all consumers and evals depend on it):

```markdown
# Recap — <feature-slug>

<!-- maintained by goalforge-recap (scripts/recap.sh); do not hand-edit -->

## <wp-slug>

| Task | Result |
|------|--------|
| <task-slug> | ok |

Loop-backs:
- iter <n>: <reason> (re-executed <task-slug>)

Status: <green|yellow|red> — <wp-commit-or--> — <summary>

## Feature rollup

- <g> green, <y> yellow, <r> red (of <total> WPs)
```

Rules:
- The `Loop-backs:` block and `Status:` line belong to the WP section above them.
- Each WP section appears **once**; it is extended in place, never duplicated.
- Finalize semantics:
  - **green** — all tasks `ok`, no loop-backs
  - **yellow** — WP completed but had loop-backs / retries / warnings
  - **red** — blocked / escalated / not all tasks verified
- The Status line is the one-line WP summary ("quick recap").
- `## Feature rollup` is always the last section; `rollup` rewrites it atomically.

---

## Script Interface

All subcommands are in `${CLAUDE_PLUGIN_ROOT}/scripts/recap.sh`.

| Subcommand | Arguments | Effect |
|-----------|-----------|--------|
| `init` | `<recap-path> <feature-slug>` | Create header; no-op if file exists |
| `record-wp` | `<recap-path> <wp-slug> <green\|yellow\|red> <wp-commit> <summary> [task-slug ...]` | **Authoritative** one-call WP record: ensure section + upsert task rows (result `ok`) + Status line carrying the single WP commit. Idempotent. |
| `append-task` | `<recap-path> <wp-slug> <task-slug> <result>` | OPTIONAL live-progress: add/UPDATE a task row (2-col, **no commit column**) |
| `append-loopback` | `<recap-path> <wp-slug> <iter> <reason> [task-slug]` | Add loop-back entry under WP |
| `finalize` | `<recap-path> <wp-slug> <green\|yellow\|red> <summary>` | Write/UPDATE WP Status line **without** a commit (legacy/manual; prefer `record-wp`) |
| `rollup` | `<recap-path>` | Regenerate `## Feature rollup` from per-WP Status lines |
| `--self-test` | _(none)_ | Full lifecycle smoke test; exits 0 on all-pass |

The WP commit passed to `record-wp` is the single WP-altitude commit (the caller —
`goalforge-verify` — supplies it). `record-wp` records `-` when the commit is empty
(test fixtures / no git).

---

## Reuse of goalforge-rollup Cadence

`recap.sh` mirrors the idempotency discipline of `goalforge-rollup.sh`:
- Paths resolved via `python3 os.path.realpath` — no `cd` tricks.
- Deterministic output: append/finalize upsert in place and `rollup`
  regenerates from the Status lines (no duplicate rows, loop-back entries, or
  rollup sections), so a re-run with the same arguments produces a byte-identical
  file.
- Python3 heredoc delegates all multi-line markdown manipulation; bash handles
  argument parsing and file guards only.

---

## Gotchas

1. **Duplicate WP sections**: `append-task` must locate the correct `## <wp-slug>`
   header before inserting; if the WP slug appears in a task name or comment, the
   first `## ` match is used — keep WP slugs unique within a feature.
2. **Commit hash outside a repo**: `git rev-parse --short HEAD` exits non-zero
   outside a git repo. `recap.sh` catches this and substitutes `-` so CI fixtures
   don't break.
3. **Rollup ordering**: `rollup` counts Status lines in file order (top → bottom);
   WPs added out of order will appear out of order — this is intentional (insertion
   order = execution order).
4. **Hand-edits**: the `<!-- maintained by goalforge-recap ... -->` comment is a hard
   warning; downstream tools may overwrite the rollup section on next `rollup` call.
5. **Empty summary on finalize**: the `<summary>` argument may not be empty —
   `recap.sh` exits non-zero if it is, to prevent Status lines like `green — `.
6. **recap is an audit artifact, NOT the recovery/evidence mechanism.** Crash
   recovery rides on per-task git commits + task checkpoints (goalforge-execute Step 9);
   the evidence invariant rides on task `checkpoint:` blocks. recap only *records*
   what happened. Losing/regenerating recap.md never affects recoverability.
7. **One commit per WP, at WP altitude.** The commit lives on the Status line via
   `record-wp` (`Status: <color> — <commit> — <summary>`), not in the task table.
   `append-task` is optional live-progress and carries no commit. The rollup regex
   still matches (`Status:\s*(green|yellow|red)\s*—`), so the commit segment does
   not disturb the per-color tally.
