---
name: goalforge-verify
description: "Verify a WP at status `executing`: the SINGLE semantic gate. Confirms all child tasks are `implemented` and findings.md exists, runs ONE cumulative-diff review+simplify+second-opinion pass plus the WP goal.verification router, then promotes each task `implemented → verified`, backfills commit hashes, and advances `executing → verified`. Delegates to `superpowers:verification-before-completion`. TRIGGER: /goalforge-verify <wp-path> or when goalforge-run reaches the verify step in the chain. REFUSES to proceed if any child task is not at least `implemented` or `findings.md` is missing."
metadata:
  version: 2.0.0
hooks:
  Stop:
    - hooks:
        - type: command
          command: "$HOME/.claude/scripts/skill-measure.sh goalforge-verify"
        - type: command
          command: "$HOME/.claude/hooks/skill-trace.sh goalforge-verify:stop"
---

# SDD Verify

Advances a WP from `executing → verified` after confirming all evidence
requirements are met. Delegates to `superpowers:verification-before-completion`.

## Plans root

The `<wp-path>` argument points to a WP folder inside `<PLANS_ROOT>/<feature>/`.
Resolve `<PLANS_ROOT>` per `~/.claude/skills/goalforge/references/schema.md`
§PLANS_ROOT resolution: env `SDD_PLANS_DIR` → project git-root `plans/` →
global `~/.claude/plans/`.

## Preconditions

Before any verification work begins, this skill performs a hard gate check.
**Both conditions must be true, or the skill refuses and halts:**

1. **All child tasks are `implemented`** (or already `verified` on a re-run) —
   every `task-*.md` in the WP folder must have `status: implemented` (committed,
   deterministic eval passed) or `verified`. A task still `pending`/`in-progress`
   means execution is unfinished. (goalforge-verify is the gate that *promotes*
   `implemented → verified`; it does not require tasks to be `verified` going in.)
2. **`findings.md` exists** — the WP folder must contain a `findings.md` file.

This is the structural precondition; the final invariant from
`sdd/references/schema.md` — `verified` ⇒ all child tasks `verified` +
`findings.md` exists — is satisfied by the promotion step in Completion below.

If either condition is not met, the skill MUST:
- Print which tasks are not yet `implemented` (list them by name).
- State whether `findings.md` is present or absent.
- Refuse to advance the WP status.
- Suggest the remediation: finish outstanding tasks (goalforge-execute) or create
  `findings.md`.

## Verification procedure — the single semantic gate (cumulative WP diff)

This is the **one** place the expensive semantic review runs — once, on the
**cumulative WP diff** (every task's commits since the WP began), not per task.
goalforge-execute deliberately does NOT run review/simplify/second-opinion per task.
Resolve the dispatch for this pass from the canonical role→tier map — role
**`wp-verify`** (`sdd/scripts/goalforge-pick-agent.py`: high under `semi-autonomous`,
medium under `autonomous-minimal`), instantiated to an explicit `{model, effort}`
via `resolve_dispatch` — the brief states both, never the agent `.md` defaults.

Compute the cumulative diff once (the range from the WP's first task commit to
HEAD; goalforge-watchdog uses the same range). Then, in order:

1. **Whole-repo lint + type-check, once.** Run the repo-appropriate lint and
   type-check across the whole repo a single time (the per-task tier only
   diff-scoped lint + incremental type-check; this is the authoritative full
   pass). A failure here blocks — fix before proceeding.
2. **ONE `verify-and-simplify` pass on the cumulative diff** — review + simplify +
   second-opinion, including the AI Slop Anti-Patterns check
   (`~/.claude/rules/common/code-review.md`; pay attention to **missing tests at
   changed seams** and **swallowed errors**) and the **root-cause gate** (a fix
   must name reproduction + root cause + contrast, not a shim). Do NOT reimplement
   `verify-and-simplify` — invoke it by name on the diff.
3. **Post-simplify deterministic re-run.** After `verify-and-simplify` returns,
   **re-run the deterministic eval suite** (each task's `verify:` + the whole-repo
   lint/type-check from step 1) to confirm the simplification did not break green.
   This is the relocated per-task Step 7.3 — simplify-breaks-green is caught here,
   at the WP boundary, not silently shipped.
4. **WP `goal.verification` strategy router (the authoritative verdict).** Evaluate
   the WP goal object via its declared strategy (`deterministic | numeric | judge |
   human`) — this is the authoritative completion verdict for the WP (schema.md
   §Task level: the WP `goal.verification` is the authoritative gate, with
   facet-coverage over every `goal.outcome` facet). A not-met verdict blocks.
5. **`superpowers:verification-before-completion` fed the DIFF** (not every
   `task-*.md`): confirm the cumulative diff is consistent with the WP goal, no
   contradictions, evidence is concrete. Feeding the diff (not N task files) is
   the token-efficient form.

Only when steps 1–5 all pass does Completion run.

## Completion

**Step A — Promote tasks + backfill commit hashes.** With the semantic gate
passed, for every child task at `status: implemented`:

1. Read its `checkpoint.commit_sha` (stashed by goalforge-execute Step 8.4) and write
   `commit: <sha>` into the task's frontmatter. This is the **deferred backfill** —
   the per-task `commit:` was intentionally not written during execution to avoid
   frontmatter churn; it is written here, in one batch.
2. Set the task `status: implemented → verified` — **in the same edit**, update its
   row in the WP `overview.md` `## Tasks` table Status cell to `verified` (the
   wp-01 drift-detector hard-fails on a frontmatter/cell mismatch).

A task missing its `checkpoint.commit_sha` (no recorded commit) is a real error —
do not fabricate a hash; halt and report (the task was not committed). **Backfill
+ promote MUST happen before the `--require-commit` gate below**, or the gate
false-blocks on the not-yet-written `commit:` fields.

**Step B — Validator gate (fail-closed).** Now run the validator with both flags:

```bash
bash ~/.claude/skills/goalforge/scripts/goalforge-validate.sh --strict --require-commit <PLANS_ROOT>/<feature>
```

`--strict` enforces zero-drift and fresh rollup; `--require-commit` additionally
enforces that every verified task carries its `commit:` hash (just backfilled in
Step A). The pre-commit hook uses `--strict` alone (never `--require-commit`) so
it never false-blocks a commit; commit-hash provenance is enforced HERE at
verify-time, after the batch backfill.

If this exits non-zero, do **NOT** advance `status: verified`. Report all
`ERROR` lines (stale rollup, missing commit hashes, or drift) and halt. Only on
exit 0 proceed to the finalization steps below.

**Semantic gap audit (delegated to `goalforge-watchdog`).** With the acceptance gate
passed, delegate a semantic spec-vs-diff gap audit to `goalforge-watchdog` (light
summary by default; deep `verify-gap.md` only on opt-in). It reconstructs the WP
contract and reads the **same cumulative WP-diff range computed above** (diff vs
the pre-WP baseline — robust to one-commit-per-WP trace cleanup) plus neighbors,
and reports claimed-vs-implemented / missing-tests-docs / deviation gaps into
`findings.md` (recording any material gap as a `recap.md` loop-back via
`goalforge-recap`). It is folded into this single verify pass (one audit, not per task)
and stays **advisory** — a `gaps-found` verdict is recorded for human follow-up
but does **NOT** block the `executing → verified` transition below.

**Learning-leg detection (delegated to `goalforge-learning-route.sh`).** At this
`executing → verified` boundary, run capture-learning Phase-1 detection over the
WP's verified fix — emit a tactical detection record (fix + root cause +
passing-vs-failing contrast) and flag any candidate strategic insight. This is
**best-effort and degrade-not-block**: an absent router/`capture-learning` skill,
a missing `findings.md`, or no fix at this boundary is a no-op (exit 0), never a
verify failure — hence the trailing `|| true`.

```bash
bash ~/.claude/skills/goalforge/scripts/goalforge-learning-route.sh \
  --wp <wp> \
  --fix "<one-line fix>" --cause "<root cause>" --contrast "<passing-vs-failing>" \
  [--strategic "<candidate insight>"] || true
```

The script does the deterministic plumbing only and emits the detection record to
stdout; routing (tactical → `findings.md`, strategic → propose-only) and the
`capture-learning` L1/L2/L3 invocation are added in task-02.

1. Advance the WP `executing → verified` **through the transition mechanism**.
   `goalforge-verify` remains the sole authority that *decides* this edge; only the
   *write* moves to `goalforge-transition.sh`, which writes `status:` + `stage_updated:`,
   appends the provenance ledger row, and refreshes the status cells + feature
   `todo.md`. Do not hand-edit `status:` or a status-table cell:
   ```bash
   bash ~/.claude/skills/goalforge/scripts/goalforge-transition.sh <wp> verified \
     --reason "verification passed; all tasks verified + findings present" \
     --actor goalforge-verify
   ```

2. **Reconcile the WP `todo.md`:** under `## Open Items`, remove items that
   are resolved (a verified WP has no outstanding work); under `## Blocked On`,
   clear resolved blockers. Leave any item that is genuinely still open (rare).
   NEVER fabricate content; NEVER remove a human note that remains relevant.
   This writes only the skill's derived view — it does not touch any human
   prose elsewhere.

3. **Last-WP rule — integration review, then advance the feature to `completed`:**
   scan every sibling `wp-*/overview.md` `status:` field. If ALL sibling WPs
   (including this one) are now `verified`:
   - **Cross-WP integration review (last-WP only).** Before declaring the feature
     done, run one integration review over the *whole feature* diff — the place
     where cross-WP contracts, shared-file interactions, and end-to-end behavior
     are checked as a whole (per-WP verify only saw one WP's diff). Resolve its
     tier from the canonical role→tier map (role `integration-review`). Findings
     go to the feature `findings.md`; a blocking finding holds the feature at
     `active` (do not advance to `completed`). **Under `SDD_AUTONOMY=unattended`
     this PARKS** (write the review prompt/findings, stop) — it never silently
     no-ops. `goalforge-archive` Step 1.5 is a terminal *confirmation* of this review,
     not a substitute for it.
   - Set `status: completed` and `updated: <today>` in the feature `overview.md`
     frontmatter. **Feature terminal status is `completed`; `verified` is a
     WP-only status — never write `status: verified` to a feature overview.**
   - Update the feature `overview.md` WP-table Status cell for this WP to
     `verified`.

4. **Refresh the feature rollup:**
   ```bash
   bash ~/.claude/skills/goalforge/scripts/goalforge-rollup.sh <PLANS_ROOT>/<feature>
   ```
   This regenerates `<feature>/todo.md` to reflect the current WP and task
   statuses (including the new `verified` WP and any feature completion).

   Then **record the WP's trace** (delegated to `goalforge-recap`). This is record-only,
   runs AFTER the `status: verified` write above, and is the **authoritative
   one-row-per-WP trace** (no per-task commit column). Use `record-wp`: it writes
   the task list, the WP color
   (`green` when the WP had no loop-back entries, `yellow` when it did), the
   **single WP commit** at WP altitude, and the accumulated loop-backs, in one
   idempotent call; then regenerate the feature rollup:
   ```bash
   RECAP=<PLANS_ROOT>/<feature>/recap.md
   bash ~/.claude/skills/goalforge/scripts/recap.sh record-wp "$RECAP" <wp-slug> <green|yellow> <wp-commit-sha> "<one-line summary>"
   bash ~/.claude/skills/goalforge/scripts/recap.sh rollup "$RECAP"
   ```

5. **Commit finalization edits, then ensure clean.** Stage and commit ONLY the
   feature plan artifacts:
   ```bash
   git add <PLANS_ROOT>/<feature>
   git commit -m "docs(sdd): finalize <wp> verification" -- <PLANS_ROOT>/<feature>
   ```
   The explicit `-- <pathspec>` is required: parallel sessions share `.git/index`,
   and a bare commit would sweep another session's staged files (repos with
   `shared_index_guard: true` block it at the harness layer).
   Use a `docs`/`chore` type; no body is needed. Commit on the **current branch**
   — in the dotfiles repo that is `master` (no feature branch, no push). Then
   confirm no uncommitted artifacts remain under the feature path:
   ```bash
   bash ~/.claude/skills/goalforge/scripts/goalforge-ensure-committed.sh <PLANS_ROOT>/<feature>
   ```
   On non-zero exit, report the dirty paths and **HALT** — do not declare the WP
   done. The check is path-scoped (unrelated dirt elsewhere never false-blocks)
   and branch-agnostic (passes on `master` under the dotfiles exception).

6. **Close-the-loop archive prompt** — only when the last-WP rule fired and the
   feature advanced to `completed`. Print a gated offer and STOP; do not act on
   it:
   ```
   Feature <feature> is now `completed`. Archive it (terminal historical
   record)? Supersede another feature? Run:
     goalforge-archive <feature> [--supersedes <old>]
   ```
   Do **NOT** set `status: archived` here — archival is an explicit user action
   only, performed by `goalforge-archive`. goalforge-verify never writes a feature to
   `archived`.

If the verification pass returns failures:
- Do **not** advance `status:`.
- Log the specific failures in `findings.md` under a dated heading:
  ```
  ## [YYYY-MM-DD] Verification failures
  - <task name>: <what was missing or failed>
  ```
- Report to the user and halt.

## Files read / written

| File | Access |
|------|--------|
| `<wp>/overview.md` | read (goal/scope) + write `status:`/`stage_updated:` **via `goalforge-transition.sh`** + `## Tasks` cell promotion to `verified` (Completion Step A) |
| `<wp>/task-*.md` | read (status + verify evidence) + write (promote `implemented → verified`; backfill `commit:` from `checkpoint.commit_sha`, Completion Step A) |
| `<wp>/findings.md` | read (required for gate) + write (append failures if any) |
| `<wp>/todo.md` | write (reconcile resolved open items when WP reaches `verified`) |
| `<feature>/overview.md` | write (`status: completed`, `updated:`, WP-table cell) when all sibling WPs are `verified` |
| `<feature>/todo.md` | write (via `goalforge-rollup.sh` after every Completion run) |

## State transition

```
executing → verified        (only after all tasks verified + findings.md present)
feature: active → completed  (last-WP rule: when all sibling WPs are verified;
                              feature terminal = completed, NOT verified)
feature: completed → archived (explicit user action only — via goalforge-archive)
```

## Delegated skills

- `verify-and-simplify` — the ONE cumulative-diff review + simplify + second-opinion
  pass (procedure step 2), tier via role `wp-verify`. Not reimplemented here.
- `superpowers:verification-before-completion` — evidence review, fed the cumulative
  WP **diff** (not every `task-*.md`).
- `goalforge-watchdog` — advisory semantic spec-vs-diff gap audit over the same WP-diff range.
- `goalforge-recap` (`record-wp`) — authoritative one-row-per-WP trace (single WP commit).
- integration review (role `integration-review`) — cross-WP/whole-feature review at the
  last-WP→`completed` transition; parks under `SDD_AUTONOMY=unattended`.

## Refusal template

When preconditions are not met, output:

```
goalforge-verify REFUSED — preconditions not satisfied:

Tasks not yet implemented:
  - task-01-foo (status: in-progress)
  - task-03-bar (status: pending)

findings.md: [present | MISSING]

Finish all tasks (goalforge-execute → `implemented`) and ensure findings.md exists
before retrying. goalforge-verify promotes `implemented → verified` itself.
```

**Named cause — `executor-divergence`.** When tasks are not `implemented` **and**
no `task-*.md` carries a `checkpoint:` block (and the WP is `executing` or the
`checkpoint.commit_sha` backfill has nothing to read), the likely cause is that the
WP was built **outside `goalforge-execute`** — e.g. the bare `implement` skill or manual
edits, neither of which advances task `status:` or writes a `checkpoint:` block.
This is `executor-divergence`. Remediation: **re-run the WP through `goalforge-execute`
(`/implement`)** — it resumes from checkpoints and is the only path that advances
task status; task status is advanced only by `goalforge-execute`, never by bare
`implement`. Emit this named cause in the refusal so the failure is diagnosable,
not a mystery.

## Gotchas

- Preconditions are a hard gate — if ANY task is not at least `status: implemented`, the skill REFUSES entirely; it does not partially verify completed tasks or emit a warning and continue. One `pending`/`in-progress` task blocks the entire WP. (goalforge-verify *promotes* `implemented → verified` itself — it does not require tasks to be `verified` going in; requiring that was the old per-task model.)
- `findings.md` must exist as a file — an empty `findings.md` satisfies the gate; a completely absent file causes refusal even if every task is `verified`. The file is created by `goalforge-harden`; a WP that skipped hardening will always fail this gate.
- The `executing → verified` transition is the sole responsibility of goalforge-verify, not goalforge-execute — calling goalforge-verify directly (outside the execute outer loop) is the correct manual recovery path when goalforge-execute left the WP at `executing` without completing.
- On verification failure, the skill logs failures to `findings.md` under a dated heading — but if `findings.md` was created by `goalforge-harden` with no resolved items (only the template marker), failure entries land after placeholder text that can read as real content to a casual reviewer. (goalforge-verify never creates `findings.md`; its precondition refuses when the file is absent.)
- The AI Slop Anti-Patterns check is delegated to `superpowers:verification-before-completion` — if that superpower is unavailable or misconfigured, the check may not run (or may error, depending on the session); a missed delegation can yield a false-positive "clean" verdict. Confirm the superpower loaded before trusting a pass.
- Feature terminal status is `completed`, not `verified`. WP enums terminate at `verified`; feature enums terminate at `completed` (draft→ready→active→completed→archived). Writing `status: verified` to a feature `overview.md` is always a bug — the feature has no `verified` state.
- Last-WP rule: after advancing a WP to `verified`, always scan sibling `wp-*/overview.md` statuses before exiting. Skipping the scan leaves the feature stuck at `active` even when all work is done.
- goalforge-verify is fail-closed on `sdd-validate --strict --require-commit` — a verified task missing its `commit:` hash, or a stale rollup, BLOCKS finalization. **Order matters:** the commit hashes are backfilled from each task's `checkpoint.commit_sha` and the tasks promoted `implemented → verified` in Completion Step A, which MUST run BEFORE the `--require-commit` gate (Step B) — otherwise the gate false-blocks on the not-yet-written `commit:` fields. The `--require-commit` flag is exclusive to verify-time; the pre-commit hook uses `--strict` alone so it never false-blocks. A task with no `checkpoint.commit_sha` is a real error (it was never committed) — halt, do not fabricate a hash.
- The semantic review runs **once here on the cumulative WP diff**, not per task — goalforge-execute deliberately skips per-task `verify-and-simplify`. After `verify-and-simplify`, goalforge-verify **re-runs the deterministic eval suite** (relocated Step 7.3) so a simplification that breaks green is caught at the boundary, not shipped. If you find yourself wanting per-task review, that is the opt-in high-risk exception in goalforge-execute, not the default.
- The completion commit gate (step 5) is **path-scoped and branch-agnostic**: it commits only `<PLANS_ROOT>/<feature>` and runs `goalforge-ensure-committed.sh` against that same path, so unrelated dirt elsewhere never false-blocks, and it passes on `master` under the dotfiles exception (commit directly — no branch, no push). The archive prompt (step 6) is OFFERED, never performed: goalforge-verify never writes a feature to `status: archived` — that is `goalforge-archive`'s explicit, human-gated job.
