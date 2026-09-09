---
name: goalforge-verify
description: "goalforge-internal — use entry commands; do not auto-trigger Verify a work package at `status: implemented`: gate A deterministic (lint, typecheck, verification.command, diff ⊆ owned_files), gate B one fresh-context review of the WP diff, gate C goal judge plus one foreign second opinion. Advances `implemented → verified` — the sole authority for that edge. TRIGGER: /verify <wp-path>, or when the chain reaches the verify step."
metadata:
  skill-kind: preference
  version: 3.0.0
---

# goalforge-verify

## Contract

Three gates over the WP's single commit, then `implemented → verified` — the
sole authority for that edge. `${CLAUDE_PLUGIN_ROOT}` is the package root
(`packages/goalforge/` on a direct load); frontmatter, the status enum, and
`<PLANS_ROOT>` resolution: `${CLAUDE_PLUGIN_ROOT}/references/schema.md`.

## Preconditions

`status: implemented` (or `verified` on an idempotent re-run). Anything else —
refuse, name the current status, and say what produces `implemented`
(`goalforge-execute`: checklist done, `verification.command` green, one commit).
Never partially verify: a WP still at `executing` was built outside the chain, so
re-run it through `/implement`. Then compute the cumulative WP diff once — the
WP's commit(s) against the pre-WP baseline — and feed that range to all three
gates.

## Gate protocol

Before each gate, ask the budget script whether it may run; after each gate,
emit its verdict:

```bash
bash ${CLAUDE_PLUGIN_ROOT}/scripts/goalforge-gate-budget.sh <gate> --feature-dir <PLANS_ROOT>/<feature>   # 0 run, 4 disabled, 2 error
${CLAUDE_PLUGIN_ROOT}/scripts/goalforge-trace-emit \
  --feature-dir <PLANS_ROOT>/<feature> --event '<gate.result payload>'
```

Exit 4 = the gate BLOCKed twice this session with no shipped fix: the script
writes the `gate.disabled` WARN row, you skip that gate and note it in
`<wp>/findings.md`. A gate's internal error is exit 2 — a failure, never a pass.

## Gate A — deterministic

1. Repo lint and type-check, whole-repo, once.
2. The WP's `goal.verification.command`, exactly as written.
3. **Boundary check:** every path in the cumulative diff is inside the WP's
   `owned_files:`. A path outside it BLOCKS — the WP wrote where it does not own.

Any failure BLOCKs: record it in `<wp>/findings.md` and send the WP back to
`executing` with a `--reason`. B and C do not run on a red gate A.

## Gate B — review

ONE review pass on the cumulative diff, in a **fresh context**, with a **model
different from the executor's** (role `wp-verify` in
`${CLAUDE_PLUGIN_ROOT}/references/tier-map.md`; the brief states model and
effort). It reads the diff, not the plan files: correctness, error handling,
complexity delta, AI-slop anti-patterns, and the root-cause gate
(`~/.claude/rules/common/code-review.md`). CRITICAL findings BLOCK; HIGH ones are
recorded and re-dispatched to `goalforge-execute` once.

## Gate C — goal judge

Judge the diff against the WP `goal:` object. Until wp-02 ships the
evaluation-expert roster, use this generic binary rubric — each item PASS/FAIL
with quoted `file:line` evidence:

1. **Outcome** — every facet of `goal.outcome` is realized in the diff.
2. **Behaviors** — every `goal.verification.behaviors[]` id has an oracle that
   ran against the system and passed; a check that cannot fail is a FAIL.
3. **No shim** — no widened `try/catch`, loosened assertion, magic sleep,
   narrowed or deleted test, or hard-coded special case standing in for a fix.
4. **Scope** — the diff does what the `## Checklist` says and nothing more.

Any FAIL is a not-met verdict and BLOCKs. Then take ONE foreign second opinion
on that verdict:

```bash
${HOME}/.claude/skills/agent-dispatch/ollama/scripts/headless_dispatch \
  --model deepseek-v4-flash:cloud \
  --prompt-file ${HOME}/.claude/prompts/<wp-slug>-second-opinion.md \
  --output <PLANS_ROOT>/<feature>/second-opinion.json
```

The prompt file carries the wp-20 frontmatter (`mode`, `session_id`, `created`,
`project`, `slug`, `role`, `expected_artifact`) and a `## Suggested skills`
section. Record the outcome in the trace as `second_opinion.ok` (verdict quoted)
or — dispatcher absent or unreachable — `second_opinion.skipped` with the reason;
a skip is legal, a silent omission is not. **Judge/second-opinion disagreement
escalates to the human** (unattended: park with both verdicts in `findings.md`);
never break the tie yourself.

## Completion

1. Advance the status, then emit `wp.verified`:
   ```bash
   bash ${CLAUDE_PLUGIN_ROOT}/scripts/goalforge-transition.sh <wp> verified \
     --from implemented --reason "gates A/B/C passed" --actor goalforge-verify
   ```
2. **Last WP?** If every sibling `wp-*/overview.md` is now `verified`, run one
   integration review over the whole-feature diff (role `integration-review`)
   with the repo build and test suite green. A blocking finding holds the
   feature at `active`; otherwise set the feature `status: completed`. Under
   `SDD_AUTONOMY=unattended` this parks — it never silently no-ops.

## Gotchas

- **A gate that does not emit `gate.result` is not a gate** — an unrecorded
  verdict cannot be budgeted (b8), replayed (b2), or trusted afterwards.
- **The second opinion checks the judge, not the code** — feed it the verdict
  and the diff; a reviewer with no verdict to disagree with adds a model call.
- **Refusal is cheap, partial verification is not** — a WP that is not
  `implemented` has no single commit to diff, so gate A's boundary check has
  nothing to check.
