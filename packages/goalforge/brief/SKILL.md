---
name: goalforge-brief
description: "PRIVATE child of goalforge. Authors a delta-only brief-<task-slug>.md (full task slug, e.g. brief-task-02-wire-stages.md) for a complexity-gated (medium/high) task, ONCE, at the task's pending→briefed transition. A strong tier (resolved via tier-map.md) writes pointers + doc context + skeleton signatures + a pointer to task-NN.md — never frozen implementation code — so a cheap tier can then execute the task. Invoked only by goalforge-execute's pre-dispatch flow; not a user-facing front door."
metadata:
  skill-kind: preference
  version: 1.0.0
hooks:
  Stop:
    - hooks:
        - type: command
          command: "$HOME/.claude/scripts/skill-measure.sh goalforge-brief"
        - type: command
          command: "$HOME/.claude/hooks/skill-trace.sh goalforge-brief:stop"
---

# goalforge-brief

Author a single, immutable brief for one complexity-gated task so a cheaper
executor tier can implement it without re-deriving the surrounding context.

## Visibility

PRIVATE child of the `goalforge` package. Discovery is one level deep, so this
nested SKILL is never a user-invocable front door. Its **only** call site is
`goalforge-execute`'s pre-dispatch flow (wp-06/task-04), which invokes it once
per gated task at the `pending → briefed` transition.

## Complexity gate (trigger condition)

Author a brief **only** when the task's frontmatter field
`complexity ∈ {medium, high}`. The gate reads the `complexity:` field directly
from the target `task-NN.md` frontmatter — it does **NOT** call
`goalforge-wp-complexity.sh` (that script computes a WP-level signal; this gate
is a per-task read).

- `complexity: low` → **skip** briefing entirely; the executor dispatches the
  task directly with no brief artifact.
- `complexity: medium | high` → author exactly one `brief-<task-slug>.md` sibling
  (full task filename minus `.md` — `brief-task-NN-<slug>.md`, the name
  `execute/brief-staleness.sh` resolves; a bare `brief-task-NN.md` is invisible
  to it).

Author once. A brief is **immutable** after authoring; re-authoring a task that
already has a sibling `brief-<task-slug>.md` is a no-op (staleness handling is the
executor's re-validation step, wp-06/task-04 — it records a re-brief request to
the task checkpoint block, it never mutates the brief in place).

## Dispatch tier

The brief is written by a **strong** tier, resolved via
`~/.claude/skills/goalforge/references/tier-map.md` (the human-readable
projection of `ROLE_TIER` in `scripts/goalforge-pick-agent.py` — the single
authoritative source). The resolved tier is stamped into the brief frontmatter
as `brief_tier`. The point of the stage is tier inversion: pay for a strong tier
once to author the brief, then let a cheap tier consume it per execution.

## Brief-authoring flow (delta-only)

Emit `<wp>/brief-<task-slug>.md` with frontmatter `{task, created, brief_tier}` and
these sections (per Interface Contract §4 as amended by decision A-FOLD —
delta-only, no duplication):

1. **References** — a `file:line` pointer plus the referenced file's **git blob
   SHA** (recorded per referenced file, one row each) to the code, docs, and spec
   the task touches. Pointers, not copies. The recorded blob SHA is the anchor the
   executor's staleness re-validation (wp-06/task-04) compares against current
   repo state. Then add **exactly one** goal-hash row
   `| goal:<wp-slug> | <goal-hash> |`, recording the WP goal-block hash from
   `scripts/goalforge-goal-hash.sh <wp-dir>` at authoring time — the second
   staleness anchor the executor re-validates (git blob SHA per file **plus** the
   WP goal-hash). Without this row the goal-hash leg of the staleness contract is
   dead: the executor only compares anchors the brief actually records.
2. **Context** — the relevant doc/design context distilled for this task:
   constraints, invariants, and the surrounding-code facts an executor needs.
3. **Skeleton** — signatures only: the function/type/module interface shapes the
   task will fill in. **Never** frozen or complete implementation code.
4. A **pointer to `task-NN.md`** for Steps and Acceptance — these are NOT
   duplicated into the brief; the brief is a delta over the task file.

Hard constraints:

- A brief is pointers + doc context + skeleton signatures + a task-NN.md pointer
  **only**. It must never contain frozen/complete implementation code.
- The brief is immutable after authoring.
- Low-complexity tasks are never briefed.

## Brief artifact schema (canonical template)

The emitted `<wp>/brief-<task-slug>.md` conforms exactly to this shape — frontmatter
is the three keys `{task, created, brief_tier}` and nothing else (no
`staleness_checked`, per A-FOLD: the brief is immutable, so a staleness result
never lives in it — it records to the task checkpoint block instead):

```markdown
---
task: task-NN-<slug>
created: <YYYY-MM-DD>
brief_tier: <resolved-strong-tier>
---

## References

| file:line | git blob SHA |
|---|---|
| path/to/file.ext:LINE | <blob-sha> |
| goal:<wp-slug> | <goal-hash> |

## Context

<stable facts: constraints, invariants, surrounding-code facts>

## Skeleton

```<lang>
<signatures / stubs only — never a complete function body>
```

## Task

See `task-NN.md` for Steps and Acceptance (not duplicated here).
```

The recorded git blob SHA per file References row is obtained with
`git rev-parse HEAD:<path>` (or `git hash-object <path>` for a working-tree file)
at authoring time; the executor's staleness re-validation re-computes it and
compares. The single `goal:<wp-slug>` row's value is the WP goal-block hash from
`scripts/goalforge-goal-hash.sh <wp-dir>`; the executor re-computes it the same
way and compares recorded-vs-current. The `Skeleton` fence carries signatures/stubs only — asserting it never
holds a complete function body is a brief-authoring invariant (fixture-checked in
wp-06/task-05).

## Gotchas

- **References cells are BARE — never backtick-wrap them.** The staleness
  parser (`execute/brief-staleness.sh`) splits each row on `|` and uses the
  cell text verbatim: a backticked path fails `os.path.exists`, a backticked
  SHA never equals the recomputed hash, and a backticked `goal:` prefix is
  misread as a file path. Backticked cells make every anchor report drift or
  MISSING.
- **Never anchor a References row on the WP's own `overview.md` or on the
  task file being briefed.** The pending→briefed status write mutates both
  immediately after authoring, so the recorded blob SHA is stale by
  construction (self-invalidation). For goal-block context use the
  `goal:<wp-slug>` hash row — it re-computes over the goal block only and
  survives status-line writes.

## Consumed by

`goalforge-execute` (wp-06/task-04): pre-dispatch invocation (this child) and
staleness re-validation of the emitted brief against current repo state
(recorded git blob SHA per referenced file + task/WP goal-hash) before a cheap
tier consumes it.
