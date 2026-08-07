<!--
Source: docs/handoffs/_archived/goalforge-package-maintenance/2026-07-28-handoff.md (untracked, local-only handoff doc)
Scrubbed: absolute personal paths ($HOME/... -> ~), session UUID left as-is
(not personally identifying), no other changes.
-->

# Example: session handoff

Where this sits in the chain: emitted by the `handoff` skill at a session
boundary (context filling up, a milestone reached, or a feature closing out)
so a fresh agent — possibly days later, possibly a different model — can pick
up cleanly without re-deriving state from the repo and chat history. Picked
up via `/handoff-pickup`. This one closes out a completed feature and carries
forward a short residue agenda; it is real, unedited apart from path
scrubbing.

What to notice:

- `## Goal (next session)` states up front that there is *no* in-flight
  work — the handoff exists purely to carry three small, user-gated residue
  items forward, so the next session doesn't have to reconstruct that from
  a stale-looking backlog.
- `## State of play (clean)` is a verification snapshot (branch state,
  harness pass/fail counts, memory pointers) — evidence, not a claim, of
  where things stand.
- `## DO / DON'T` and `## Gotchas` are the accumulated, load-bearing
  constraints that would otherwise get relearned the hard way by whoever
  picks this up next.
- `## Learnings` captures durable process lessons (a review catching what a
  deterministic gate missed) — this is what feeds `capture-learning`.
- `## Suggested skills next session` ends the doc with an actionable first
  move, not just a status report.

---

```markdown
---
mode: session
session_id: "e5365de5-bc7b-4eb4-89d1-0adf815ee730"
created: "2026-07-28T00:00:00Z"
project: "~/10_projects/cogwright"
branch: "main"
slug: "goalforge-package-maintenance"
model: "claude-fable-5[1m]"
provider: "anthropic"
status: picked_up
picked_up_by_session: e5365de5-bc7b-4eb4-89d1-0adf815ee730
picked_up_by_model: claude-fable-5[1m]
picked_up_by_provider: anthropic
picked_up_at: "2026-07-28T14:20:26Z"
archived_at: "2026-07-28T14:20:26Z"
archive_reason: "picked-up"
---

Resume: docs/handoffs/_archived/goalforge-package-maintenance/2026-07-28-handoff.md

# Handoff — goalforge-package-maintenance (feature CLOSED; residue agenda)

## Goal (next session)

The goalforge-prototype-native feature is **completed and archived** — there is
no in-flight work. This handoff carries the residue agenda, all user-gated or
user-triggered:

1. **`/idea-review`** on cogwright's live backlog (3 ideas, pre-ranked below).
2. **brief/ tenancy decision** (`plans/ideas/brief-tenancy.md`) — user gate on
   how the parent SKILL.md classifies `brief/` (Children-table row vs
   co-tenancy note vs a third "chain-support asset" class). 10-minute
   interview, then a one-line parent edit + mirror regen.
3. **plans/ tracking substrate** — still parked from 2026-07-27: `plans/` +
   `docs/handoffs/` are gitignored (main commit 24b326b), so plan/ledger/
   handoff writes have no git history. Options user named: private repo /
   nested git / stay-untracked. Ask before touching.

## Session 2026-07-28 (this session, e5365de5)

All committed to main (80f78c7 → 39905bb):

| Item | State | Commits |
|---|---|---|
| wp-07-package-conformance | verified, ff-merged | 368fd49, c205078, 96602b4, 26aafe8, 141983c (gate fold) |
| WP-gate review (opus/high) | FAIL → folded: F1 HIGH factually-wrong wayfind re-key (sweep list over-broad — spec defect; user chose revert+amend, goal hash re-recorded 43f3e9cd3f56), F2 conformance block hardened (+C6, C5 optional-backticks — orchestrator caught reviewer's own fix incomplete via mutation test), F3 gotcha reword | 141983c |
| feature goalforge-prototype-native | completed → **archived** (`plans/_archived/goalforge-prototype-native/`) | plans/ untracked |
| brief-contract skill-defect fixes (both logged defects) | merged: full-slug brief filenames canonical (template + validator + parser aligned), bare References cells, brief/SKILL.md ## Gotchas added; validator warnings 19→13 | 2a3fec1 |
| mutation-testing house pattern | merged: `packages/goalforge/references/mutation-testing.md` + harden/SKILL.md pointer | 39905bb |
| ideas | goalforge-prototype-native archived (promoted); brief-tenancy captured; prototype-spec-soft-reference unlocked | plans/ideas/ |

**Human decisions this session (binding):** F1 fix = "Revert row, amend goal"
(wayfind:152 back to direct engine mention; wayfind:142 leg dropped from goal
check; sweep 20→19). F2+F3 both fixed. Follow-ups chosen: mutation-harness
reference doc (done) + idea triage (pre-ranked here, run interactively next).

## State of play (clean)

- main @ 39905bb; working tree clean; session branches deleted (5 merged).
  Remaining branches (`goalforge-installer`, `harden-findings-backstop`, …)
  predate this thread — not swept, ownership unknown.
- Feature at `plans/_archived/goalforge-prototype-native/` (status archived;
  cross-refs repointed: brief-tenancy idea + memory pointer). Post-archive
  sweep clean. Recap/improvement-report live inside the archived dir.
- Harnesses: package 42/0, harden 31/0, brief-stage 7/7, staleness self-test
  PASS, generate --check clean, validator 0 errors / 13 warnings (all
  pre-brief-stage WPs + tmp-evidence — expected).
- Memory: `.memory/project/handoff_goalforge-prototype-native.md` closed
  (points at archived paths).

## Idea backlog (pre-ranked for /idea-review)

1. `brief-tenancy` — decision-kind, user gate, cheap to close, unblocks parent
   SKILL.md contract completeness. Rank first.
2. `prototype-spec-soft-reference` — unlocked (wp-06 merged); needs refine
   before promote; medium.
3. `shared-hard-vs-incidental-ref-classifier` — untouched this thread; assess
   staleness at review.

## DO / DON'T

- DO run `bash scripts/goalforge-generate.sh` + stage mirror counterparts in
  the SAME commit for every packages/goalforge change; plugins/ is GENERATED.
- DO use full-slug brief filenames (`brief-task-NN-<slug>.md`) + bare
  References cells — now the documented contract (brief/SKILL.md ## Gotchas),
  validator accepts it since 2a3fec1.
- DO mutation-test any new eval check AND any reviewer-proposed check —
  `packages/goalforge/references/mutation-testing.md` (this session's F2
  proved reviewer-proposed checks need it too).
- DON'T commit on main (pre-git-commit-enforce hook blocks; `git checkout -b`
  as its OWN call before any commit).
- DON'T hand-edit WP/feature `status:` — goalforge-transition.sh is single
  writer; archive terminal moves via goalforge-archive.sh only.
- DON'T run `gh pr create`/`close` autonomously — user-gated.
- DON'T re-litigate: skill-kind 18× preference verdicts, wayfind:152 revert,
  co-tenancy note wording — all ledgered in the archived wp-07 findings.md.

## Gotchas (bit or confirmed this session)

- **goalforge-archive-sweep.py needs explicit `--plans-root/--docs-root/
  --memory-root`** in this repo — defaults resolve to the wrong root (dotfiles)
  under lean-ctx's cwd handling.
- **Workflow tool `run_in_background` param does not exist** — omit it;
  workflows always background.
- **Task-file verify blocks exist TWICE** (frontmatter `verify:` + body
  `## Verification` fence) — amend both or the next reader sees a ghost leg.
- **validator's brief-skip check reads `brief-task-NN.md`** only up to 2a3fec1;
  if warnings 19→13 regressed, check that commit survived.
- **ctx_shell blocks `python3 -c`/heredocs** — write scratchpad script files;
  unique per-task prefixes (wp07t03-*) avoid the shared-scratchpad collision.
- **Scratchpad files are write-only for the session's own Edit tool** (Read
  deny rule) — Write a NEW file instead of editing a scratchpad script.
- **529 Overloaded** did NOT occur this session (4× last session) — retier
  ladder untested today, directive unchanged: retier implement workers only,
  never the opus@high gate.

## Learnings

- The opus@high adversarial gate caught a panel-hardened, user-approved,
  red-baselined sweep-list entry as semantically wrong — deterministic rigor
  at authoring time does not substitute for semantic review at fold time.
  (Second occurrence of the class; wp-04 was the first.)
- Judge-proposed fixes are hypotheses: mutation-test them with the same bar as
  the artifact (F2's C6 missed the unbackticked-row bypass). Now codified in
  references/mutation-testing.md.
- Fable-brief + opus@medium workers: 4/4 clean first-pass tasks; the brief
  remains the quality lever (bare-cell References + fresh line numbers +
  allowlists + self-check blocks pasted verbatim).

## Improvement Report

Feature archived; retrospective (final, incl. this session's spec-gap +
skill-defect issue events) at
`plans/_archived/goalforge-prototype-native/improvement-report.md`.

## Suggested skills next session

`/handoff-pickup goalforge-package-maintenance` → `/idea-review` (ranked list
above) → AskUserQuestion on brief-tenancy → if plans/ substrate is to be
decided, the `interview` plugin skill on the three options.
```
