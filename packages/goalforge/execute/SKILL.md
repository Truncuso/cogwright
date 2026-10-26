---
name: execute
description: "Run ONE work package from `status: ready` to `implemented`: dispatch one owning agent against the WP checklist, run the deterministic verification, land exactly one conventional commit. Never writes `verified` — that edge belongs to goalforge-verify. TRIGGER: /implement <wp-path>, or when the chain reaches the execute step."
metadata:
  skill-kind: preference
  version: 3.0.0
hooks:
  Stop:
    - hooks:
        - type: command
          command: "$HOME/.claude/hooks/skill-trace.sh goalforge-execute:stop"
---

# goalforge-execute

## Contract

Reads a WP `overview.md` at `status: ready` and drives `ready → executing →
implemented` = every `## Checklist` item done, `goal.verification.command` green,
one commit landed — not quality-signed-off: `verified` is written only by
`goalforge-verify`. `${CLAUDE_PLUGIN_ROOT}` is the package root; frontmatter, the status enum, and `<PLANS_ROOT>` live in `references/schema.md`, C1-C7 in `spec.md`.

## 1 — Entry

1. Read `<wp>/overview.md`. Already `executing` ⇒ re-entry: skip the transition
   (ticked boxes plus the git log are the resume state), continue at step 2.
2. Otherwise assert `status: ready` and advance through the single writer —
   never hand-edit `status:`:
   ```bash
   bash ${CLAUDE_PLUGIN_ROOT}/scripts/goalforge-transition.sh <wp> executing \
     --from ready --reason "goalforge-execute entry" --actor goalforge-execute
   ```
3. Read `register:`, `severity:`, `owned_files:`, `human_required:`, `goal:`, `##
   Checklist`. A set `human_required:`, or `register: production` with `severity:
   HIGH`, is a human gate (C7): render it through the one human template, wait.
   ```bash
   bash ${CLAUDE_PLUGIN_ROOT}/scripts/goalforge-stage-report.sh execute <wp-id> --json <report.json> --feature-dir <feature>
   ```
4. Before any dispatch run `bash ${CLAUDE_PLUGIN_ROOT}/scripts/goalforge-harness-check.sh <availability-file>`, the file written from this session's actual tool list (never a fixture); hard-required per `references/harness-dependencies.md`: Agent tool, git, python3, jq, flock, timeout, realpath, tar, PyYAML; a WARN names the lost fallback; a non-zero exit stops the run per §5 (exit 1 floor breach, exit 2 bad declaration).

## 2 — Register switch

- **`production`** — the deterministic gate is mandatory: tests come from
  `goal.verification.behaviors[]`, `goal.verification.command` must pass first.
- **`spike`** — the WP answers ONE design question; spike code is never merged,
  the findings doc is the deliverable and the content of the one commit, and the
  verdict comes from the declared `judge`/`human` strategy, never a deterministic run over spike code.

## 3 — Ownership decision (C5)

One agent owns the whole WP by default. Split into batches ONLY when
`owned_files:` holds more than 8 entries, or when checklist items have pairwise
disjoint `{files:}` sets AND the WP is `parallel: true`; overlapping `{files:}` is
a malformed split — fall back to one owner. Batches run concurrently, return their work as DATA, and **never commit**: the one WP commit is yours (step 6).

Resolve the dispatch deterministically from `references/dispatch.yaml` — the brief states model AND effort explicitly, never the agent default, and blast radius or `severity: HIGH` escalates the tier (detail: `references/dispatch-resolution.md`):
```bash
python3 ${CLAUDE_PLUGIN_ROOT}/scripts/goalforge-pick-agent.py --task <wp>/overview.md --role implement
```
Its JSON fills `model`, `effort`, `provider`, `endpoint`, the owning agent, and
the §4 `Expertise refs:` slot. When batching applies, compile the checklist and
launch the emitted script through the Workflow tool (degradable, see `references/harness-dependencies.md`):
```bash
python3 ${CLAUDE_PLUGIN_ROOT}/scripts/goalforge-workflow-compile.py <wp>/overview.md \
  --dispatch ${CLAUDE_PLUGIN_ROOT}/references/dispatch.yaml   # -> run/workflows/<wp>.js
```
Emit `dispatch.launched` on dispatch and, on return, `dispatch.completed`
carrying integer `tokens` and `tool_uses`:
```bash
${CLAUDE_PLUGIN_ROOT}/scripts/goalforge-trace-emit --feature-dir <PLANS_ROOT>/<feature> --event '<payload>'
```

## 4 — The WP brief

One brief per dispatch, written in-session. No brief files, no task files.
```
Role: implement <wp-slug> — <goal.outcome>.
Model: <model>   Effort: <effort>          (from pick-agent; not a default)
Owned files: <owned_files, or this batch's {files:} sets>.
Off-limits: every other path — a needed edit outside the set is a BLOCKED return.
Checklist: <the `## Checklist` lines verbatim, with {files:} and [behavior ids]>
Verification: run `<goal.verification.command>`; it must pass before you return.
Expertise refs: <the `expertise` list from pick-agent, verbatim>
Return: DATA — files changed, verification output, blockers. Do NOT commit.
Premise check: a referenced symbol, file, or invariant that does not exist is a
  BLOCKED return naming the exact `file:line` and the unmet premise — a
  first-class success outcome, not a failure to route around.
```

## 5 — Stop rule (C4)

STOP the moment any holds: the goal is met (step 6 green — stop, do not polish);
`attempts >= 2` on the same checklist item; session tokens `>=
SDD_WP_TOKEN_CEILING` (default `400000`); a premise-blocked return; the same gate
failed twice with the same reason. On every stop except "goal met": append the reason to
`<wp>/findings.md`, emit `finding.recorded` (`wp` required), leave `status: executing`, escalate to the human through the stage report (C7) — under `SDD_AUTONOMY=unattended`, park and exit cleanly. A status is never advanced past a blocker.
```bash
bash ${CLAUDE_PLUGIN_ROOT}/scripts/goalforge-stage-report.sh execute <wp-id> --json <report.json> --feature-dir <feature>   # stop/escalate
```

## 6 — Deterministic eval, then the one commit

1. Run `goal.verification.command` exactly as written, plus repo lint and type
   check. On failure re-dispatch with the full failure output as context, bounded
   by step 5 — never silent-pass a red eval.
2. Tick the completed `## Checklist` boxes in `<wp>/overview.md`.
3. Run `bash scripts/goalforge-generate.sh` from the repo root to regenerate the
   `plugins/goalforge/` mirror — generated, outside `owned_files:`, exempt gate A.
4. Stage only paths inside `owned_files:` and make **exactly one** conventional
   commit (`<type>(<scope>): <subject>`, <=72 chars, body for `feat`/`fix`, no AI
   co-author trailer); emit `commit.linked` with its sha.
5. Advance the status and hand off to `goalforge-verify`:
   ```bash
   bash ${CLAUDE_PLUGIN_ROOT}/scripts/goalforge-transition.sh <wp> implemented \
     --reason "checklist complete; verification.command green" \
     --actor goalforge-execute
   ```

## Gotchas

- **`verified` is never written here** — `goalforge-verify` is the sole authority
  for `implemented → verified`; a second advance path lets unreviewed work claim a
  quality sign-off.
- **Batches never commit** — verify gate A checks `diff paths ⊆ owned_files` over the one WP commit and b1 asserts `commit.linked` count == 1.
- **One owner is the default, not the fallback** — splitting a WP that clears neither C5 condition buys a brief, a merge, and a review round per batch.
