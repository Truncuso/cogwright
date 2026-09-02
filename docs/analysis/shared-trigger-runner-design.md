---
title: Shared trigger-eval runner — survey, home, extraction plan
type: analysis
date: 2026-09-02
status: proposal
scope: dotfiles/claude + cogwright/packages/goalforge
replaces: goalforge-design-doctrine.md §3 Items 8-9
---

# Shared trigger-eval runner

Human ruling being designed against: doctrine Item 8 is **not** built as a second
runner inside cogwright. Dotfiles' existing trigger-eval tooling becomes shared
tooling both corpora consume, with one knowledge home.

Everything asserted about the live trees below was read or executed on 2026-09-02
against `/home/cunger/dotfiles/claude`, `/home/cunger/10_projects/cogwright`, and
three live `claude -p` probes whose costs are quoted verbatim.

---

## 1. What exists today, and what each piece actually executes

### 1.1 Dotfiles side

| Artifact | What it actually executes | Drives prompts? |
|---|---|---|
| `scripts/skill-hygiene.sh` | Python/jq parse of `SKILL.md` frontmatter + `evals/evals.json`. Emits `trigger_pos`/`trigger_neg` from `(.evals? // empty) \| select(type=="array")`. Always exit 0. | **No** |
| `hooks/skill-hygiene-hook.sh` | PostToolUse wrapper. Surfaces exactly two of hygiene's facts (`over_budget`, gotcha-dedup verdict). Never invokes a model — stated as a HARD CONSTRAINT in its own header. | **No** |
| `plans/…/wp-25-…/scripts/check-canonical.sh` | Four static gates: calls hygiene for counts; greps `evals.json` for deprecated markers; jq-extracts negatives and requires a backticked *other* skill name from a `find -L` harvest of the whole installed corpus; runs `evals/run.sh` and checks exit code. | **No** |
| `plans/…/wp-25-…/scripts/self-test.sh` | 10 fixture assertions proving `check-canonical.sh` can fail per gate. Fully fixture-based (H11-compliant). | **No** |
| `plans/…/wp-25-…/conversion-contract.md` | Prose. The canonical shape + named-owner standard. | n/a |
| `plans/…/wp-27-…/scripts/ratchet-census.sh` | Recomputes `meets_bar` from two independent parsers (hygiene `--all`, and the task-07 verify-block jq), exits 1 on oracle disagreement or on fixture-exclusion rot. Writes a RECORD, never reads it as an oracle. | **No** |
| `skills/skill-meta/skill-stocktake/evals/run.sh` | Runs `critic.sh` against 5 fixtures + counts `should_trigger` cases in `trigger-evals.json`. | **No** |

**Confirmed for these seven: none drives a prompt against a skill-selection
surface.** They are shape, count, citation, and fixture checks. The doctrine's
E4 verdict ("a case corpus that nothing executes reads as coverage and provides
zero signal") is accurate for all of them.

**REFUTED, partially — an eighth artifact does drive prompts.**
`skills/skill-meta/skill-creator/scripts/run_eval.py` runs
`claude -p --output-format stream-json --verbose --include-partial-messages`
per query in a `ProcessPoolExecutor`, watches the stream for a `tool_use` block
named `Skill` or `Read`, and scores a hit by substring-matching the skill id.
It already carries `should_trigger` per case, `--runs-per-query` (default 3),
and `--trigger-threshold`. It is a real, working prompt driver.

Four defects make it the wrong thing to point at the corpus as-is, and all four
shape the extraction:

1. **It tests a clone, not the installed skill.** It writes a synthetic command
   file `<project>/.claude/commands/<name>-skill-<uuid8>.md` carrying only the
   `description:`, then measures whether *that* fires. The real skill is still
   installed, so the clone competes with its own original. It is a
   description-tuning instrument, not a corpus-contention instrument.
2. **Threshold, not pass^k.** `trigger_rate >= 0.5` → pass. H7 requires pass^k.
3. **Its case dialect is not T1.** Top-level array of `{query, should_trigger}`,
   not `{evals: [{prompt, should_trigger, expected_output}]}`.
4. **No self-test, no sabotage leg.** Nothing proves it can fail.

It is also **vendored Apache-2.0 upstream** (`skill-creator/LICENSE.txt`), which
is the decisive argument against extending it in place.

`skills/skill-meta/skill-autoresearch/` names `run_eval.py` in its `META.md`
tool table but `autoresearch_loop.py` does not import or shell to it; it takes a
`pass_rate` from its caller and appends it via `scripts/skill-eval-emit.sh`
(a tracked eval-summary stream — the natural reporting sink for a shared runner).

### 1.2 Cogwright side

- 13 `evals.json` files under `packages/goalforge/` (12 children + the router's
  own `evals/`). `grep -rl should_trigger --include=*.json` over the package
  **exits 1** — zero canonical cases, as the doctrine states.
- `scripts/install.sh:394` writes `printf '{}\n' > "$pkg/evals/evals.json"` — and
  it is inside `install.sh`'s own **self-test fixture builder**, not the install
  path. The doctrine's "only repository-wide reference … writes an empty `{}`
  scaffold" is right, and weaker than it sounds.
- `scripts/goalforge-generate.sh:135,144` **excludes every `evals/` directory**
  from `plugins/goalforge/`. Verified: `find plugins/goalforge -name evals.json`
  returns nothing. **No eval material ships.** Eval tooling is dev-time-only.
- `scripts/ci-lints.sh` has 9 sections; `lint_author_paths` blocks
  `(~|$HOME|${HOME})/.claude/skills/goalforge`, `../skills/goalforge`,
  `$HOME/dotfiles`, `${COGWRIGHT_ROOT}` — but scans only `plugins/` and
  `scripts/install.sh`.
- Nothing in `packages/goalforge/scripts/` reads a case file.
  (`goalforge-hygiene.sh` is unrelated — it reconciles plan status tables.)

### 1.3 The bridge already exists

`~/.claude` is a symlink to `/home/cunger/dotfiles/claude`;
`skills/goalforge`, `skills/prototype`, `skills/wayfind` are per-machine
untracked symlinks into `packages/goalforge/` (gitignored at
`.gitignore:236-239`, recreated by cogwright's `install.sh`).

**Measured today, unmodified:**

```
$ bash plans/skill-corpus-refactor/wp-25-.../scripts/check-canonical.sh \
      skills/goalforge/capture skills/goalforge/harden
FAIL skills/goalforge/capture: below the bar — trigger_pos=0 …
FAIL skills/goalforge/harden: below the bar — trigger_pos=0 …
```

The dotfiles gate **already reaches into cogwright and already reports the
honest zero.** No new plumbing is needed for the static half. Two asymmetries:

- `check-canonical.sh` resolves `$ROOT/<rel>` and `find -L`s the harvest → sees
  goalforge.
- `skill-hygiene.sh --all` uses `find` **without** `-L` (line 567) → does not.
  `ratchet-census.sh` already records this: *"skills/goalforge/ — the whole
  13-dir subtree; gitignored symlink, and invisible to the hygiene census,
  which finds without -L"*.

### 1.4 A measured hole worth one commit

`skills/skill-meta/skill-stocktake` keeps 3 positive / 3 negative canonical cases
in `evals/**trigger-evals.json**`. Hygiene reads only `evals/evals.json`:

```
$ bash scripts/skill-hygiene.sh skills/skill-meta/skill-stocktake
{"trigger_pos": 0, "trigger_neg": 0, "has_evals": true,
 "warnings": ["missing '## Gotchas' section"]}
```

`trigger_pos=0` **and no trigger-bar WARN**, because that WARN is gated on
`[[ -f "$evals_file" ]]`. A skill that meets the bar reads as not meeting it and
is told nothing. Filename divergence defeats both the census and the warning.

---

## 2. Where the single home goes

### 2.1 The three candidates

**(a) cogwright `packages/goalforge/` root** — where doctrine Item 8 put it.
Rejected. The runner's natural input is the whole installed corpus
(`$CLAUDE_ROOT/skills/**/evals/evals.json`); four of the five existing pieces and
the only working prompt driver live in dotfiles; and a dotfiles-side caller would
have to reach *into* cogwright, which is the machine-local dependency
self-containment forbids. It also inverts the ratio: cogwright would own a tool
whose cases are 13 of ~370.

**(b) a new cogwright package** — rejected. Cogwright ships one plugin artifact;
adding a package for dev tooling neither corpus installs is scope for no gain,
and it does not fix (a)'s direction-of-dependency problem.

**(c) dotfiles** — accepted. Precisely: **`~/.claude/scripts/skill-trigger-runner/`**
(tracked at `/home/cunger/dotfiles/claude/scripts/skill-trigger-runner/`), with a
thin `scripts/skill-trigger-run.sh` entry point sitting next to
`skill-hygiene.sh` (H3: thin shell entry, real logic in Python).

Not under `skills/skill-meta/`: the corpus convention is that deterministic
corpus tools live in `scripts/` (`skill-hygiene.sh`, `skill-learning-dedup.sh`,
`validate-skill.py`) while the skills that *use* them live in `skills/`. Not
inside `skill-creator/`: that tree is vendored Apache-2.0 upstream, and every
re-sync would fight the change.

### 2.2 The install path both sides use

The runner never knows goalforge exists. It takes the tree to scan:

```
skill-trigger-run.sh --tree <dir> [--cases <file>] [--trials k] [--report json]
```

- dotfiles / corpus-wide: `--tree "${CLAUDE_ROOT:-$HOME/.claude}/skills"`
- cogwright / per-package: `--tree "$(cd "$(dirname "$0")/.." && pwd)"`

Resolution order on the cogwright side, in `packages/goalforge/evals/trigger-run.sh`:

1. `$SKILL_TRIGGER_RUNNER` if set and executable
2. `${CLAUDE_CONFIG_DIR:-$HOME/.claude}/scripts/skill-trigger-run.sh`
3. absent → print one skip line, **exit 0** (zero-breakage)

**Self-containment holds** because of a fact the generator already guarantees:
`evals/` is excluded from `plugins/goalforge/`, so none of this is a shipped
artifact. The only anchors used are `$SKILL_TRIGGER_RUNNER`,
`$CLAUDE_CONFIG_DIR`/`$HOME` (the install anchor, not the author's checkout), and
a `dirname "$0"` relative climb. No `$HOME/dotfiles`, no `${COGWRIGHT_ROOT}`, no
`~/.claude/skills/goalforge` — the three shapes `lint_author_paths` names.

**Knowledge home:** `scripts/skill-trigger-runner/README.md` in dotfiles is the
single normative statement of the case shape, the oracle, and the pass^k
contract. `conversion-contract.md` and doctrine §2.5-2.6 become pointers to it
rather than parallel sources.

---

## 3. The extraction plan — ordered commits

Two repos. Dotfiles: trunk `master`, commit directly. Cogwright: branch
`fix/goalforge-change-set`, never `main`. Conventional Commits with a body, no AI
`Co-authored-by`, explicit paths staged. Every new assertion demonstrated RED
against the broken state before GREEN (H9). `bash scripts/ci-lints.sh` run and
its counts reported after every cogwright commit.

### D1 — `feat(scripts): add skill-trigger-runner with a shape gate` *(dotfiles)*

Adds `scripts/skill-trigger-runner/{runner.py,README.md}` and the thin entry
`scripts/skill-trigger-run.sh`. Discovers `evals/evals.json` under `--tree`
(`find -L`), validates T1 with the T2 jq expression, and on a mis-shaped file
emits a **shape error naming the file** rather than a `0 0` count. `--dry-run`
does no model work.

*Verify (RED-first):* ship `scripts/tests/skill-trigger-runner.test.sh` over a
fixture tree containing one canonical file, one top-level-array file, and one
`cases:`-keyed file. Demonstrate red by stubbing the shape validator to a
constant `true` — assertions 2 and 3 must fail — then restore. Assert
`--dry-run --tree <fixture>` exits non-zero and prints both offending paths.

### D2 — `feat(scripts): drive trigger cases against the live selection surface` *(dotfiles)*

Adds the driver. Per trial:

```
CLAUDECODE= claude -p "<prompt>" --model <m> --output-format stream-json --verbose \
  --no-session-persistence --tools "Skill" --strict-mcp-config \
  --max-budget-usd <cap>
```

read the stream, and **exit at the first `tool_use` whose `name == "Skill"`**,
recording `input.skill`. Oracle = string equality against the expected owner —
determinism-ladder rung 1, no model grader anywhere. Positive case passes when the
selection equals the skill under test; negative passes when it does not (and the
declared owner is reported for diagnosis). `--trials k` (default 3), reported as
**pass^k**, positives and negatives tabulated separately (H7). JSON in, JSON out,
each red case recording the failing assertion *and* the observed selection (H4).
Per-trial `--max-budget-usd` plus a suite-level `--max-cost-usd` hard stop.

*Verify (RED-first):* an `--offline` replay mode over recorded `stream-json`
fixtures. Land the fixtures first — one whose first Skill call is the skill under
test, one whose first Skill call is a sibling, one with no Skill call at all —
and show all three red before the pass^k reducer exists. Assert the sibling
fixture scores exactly 0/k and the mixed fixture scores 2/3 under pass^3=false.

### D3 — `test(scripts): sabotage-sensitivity self-test for the trigger runner` *(dotfiles)*

The keystone assertion, and the one the corpus currently fails. A fixture pair —
one intact `SKILL.md`, one with the description gutted — must produce a
**measurably worse** score for the sabotaged copy. Default CI leg runs the replay
fixtures; the live-model leg is gated on `SKILL_TRIGGER_LIVE=1`.

*Verify (RED-first):* the assertion is red against a runner that returns a
constant score, and red against a runner that reads only `SKILL.md` text (the
"exercise the system under test" trap — a check that only greps the prompt scores
a sabotaged system green).

### D4 — `fix(skill-stocktake): rename trigger-evals.json to the canonical evals.json` *(dotfiles)*

`git mv skills/skill-meta/skill-stocktake/evals/trigger-evals.json …/evals.json`
and update `TRIG` in that skill's `evals/run.sh` in the **same commit** (T14
harness parity — a green `run.sh` on a stale path is a false pass).

*Verify (RED-first):* `bash scripts/skill-hygiene.sh skills/skill-meta/skill-stocktake
| jq .trigger_pos` is `0` before and `3` after; `bash …/evals/run.sh` exits 0 on
both sides of the rename.

### D5 — `feat(skill-hygiene): add --follow so --all can see symlinked trees` *(dotfiles)*

`find` → `find -L` behind an opt-in `--follow` flag, default off. Opt-in because
the wp-27 ratchet floor of 48 was set against the unfollowed census, and flipping
the default silently moves `meets_bar` for every consumer.

*Verify (RED-first):*
`bash scripts/skill-hygiene.sh --all --follow | jq '[.[]|select(.skill=="goalforge")]|length'`
is 0 before, ≥1 after; plain `--all` is byte-identical before and after; then
`bash plans/…/wp-27-…/scripts/ratchet-census.sh` still exits 0 with both oracles
agreeing and both fixture-exclusion sides > 0.

### C1 — `feat(goalforge): add evals/trigger-run.sh, a caller for the shared runner` *(cogwright)*

`packages/goalforge/evals/trigger-run.sh` per §2.2. Resolution order, skip-and-
exit-0 degrade, `--tree` computed by relative climb, no author path anywhere.

*Verify:* `bash scripts/ci-lints.sh` → report all 9 section lines and the exit
code. `SKILL_TRIGGER_RUNNER=/nonexistent bash packages/goalforge/evals/trigger-run.sh`
exits 0 with one skip line. With the real runner, `--dry-run` prints **13 files,
0 canonical** — the honest zero, which is the RED baseline Item 9 then moves.

### C2 — `docs(analysis): replace doctrine Items 8-9 with the shared-runner ruling` *(cogwright)*

Item 8 becomes *"Wire the shared trigger runner"* — consume, do not build. Item 9
keeps case authoring but is **re-scoped by reachability** (see §5 risk 2):

- **SELECTION cases** only for the publicly reachable entries — `goalforge`, the
  `/spec`, `/plan`, `/implement`, `/verify` commands, and `goalforge-run` if item
  7 pins it. Six, not nineteen.
- **ROUTING cases** for the 16 private children: seed the parent, assert the
  routed child name. A different oracle, on a different surface, in a separate
  report column.

**§4.12 must be amended in this same commit** — it currently reads *"We are not
building a general skill-system harness owner … A corpus-general runner is a
separate decision with a separate cost"*, which forbids exactly this work. Record
the human ruling as the override, with the cost now measured (§4), or the next
lap refutes this using the document's own §4.

*Verify:* `bash scripts/ci-lints.sh` counts reported; Item 8's rewritten verify
block is executable as literally written against the tree.

### D6 — `docs(plans): reconcile wp-23 with the shared trigger runner` *(dotfiles)*

wp-23 gains a dependency on the runner and drops any implied second engine. See
§6.

*Verify:* `grep -n "runner" plans/skill-corpus-refactor/wp-23-skill-index/overview.md`
shows the dependency; no second engine is proposed anywhere in the WP.

### C3 — `feat(goalforge): convert 13 evals.json to the canonical should_trigger shape` *(cogwright)*

Item 9's conversion half, unblocked by C1. Successor work, not part of the
extraction. T13: rename not rewrite — `prompt` and `expected_output`
byte-identical, re-run produces a zero diff.

*Verify:* the T2 jq one-liner prints two integers for all 13; re-running the
conversion leaves `git status --porcelain` empty; `bash packages/goalforge/evals/trigger-run.sh --dry-run`
reports 13 canonical, 0 shape errors; `bash scripts/ci-lints.sh` counts reported.

---

## 4. Is a real runner buildable now? Yes — measured, not argued

Three live `claude -p` probes were run on 2026-09-02 with the doctrine's own
worked example as the prompt (*"wp-04 is at status: spec — run the hardening
panels and get it to ready"*, whose expected owner is `goalforge-harden`).

### 4.1 The mechanism

`claude -p --output-format stream-json --verbose` emits, per assistant turn, a
`tool_use` content block. Reading `.name == "Skill"` and `.input.skill` gives the
selected skill as a **string** — a deterministic oracle at rung 1 of the
determinism ladder. **No model grader is needed anywhere in the loop.** This is
the same mechanism `run_eval.py` already uses, minus the synthetic-clone confound.

`--tools "Skill"` restricts the built-in tool set; `--strict-mcp-config` drops MCP
tools and their instruction blocks; `--no-session-persistence` keeps the
evaluator's state unreachable (H5); stripping `CLAUDECODE` from the environment
allows nesting inside a live session (the `run_eval.py` pattern).

### 4.2 Measured results

| Probe | Config | First Skill call | Cost | Wall |
|---|---|---|---|---|
| 1 | `--allowedTools Skill`, full run | `plan` | $0.1077 | 44 s |
| 2 | `--tools Skill --strict-mcp-config`, full run | `lean-ctx` | $0.0862 | 31 s |
| 3 | same, **killed on first Skill tool_use** | `lean-ctx` | ~$0.0026 (25,785 cache-read + 4 output tokens, haiku) | ~10 s |

Two things fall out.

**Kill-on-first-Skill is the whole cost story.** A full run does 12 turns and
pays ~$0.09-0.11; the selection decision itself is one turn at ~26k cached input
and 4 output tokens. That is a ~35× difference, so the early exit is
load-bearing, not an optimization.

**Budget at k=3 trials:**

| Scope | Trials | Est. cost | Wall @ 8-way |
|---|---|---|---|
| goalforge, 19 skills × 6 cases | 342 | **~$0.90** | ~7 min |
| goalforge, reachability-scoped (6 selection surfaces × 6 cases) | 108 | ~$0.30 | ~2 min |
| corpus-wide (wp-23), ~370 skills × 6 cases | 6,660 | ~$17 | ~2.5 h |

Affordable enough to run on a model-upgrade gate (T15) and, for the scoped
goalforge suite, on demand.

### 4.3 What the probes also proved about the corpus

Three trials, three misses, two distinct wrong answers. `goalforge-harden` never
fired; neither did the public `goalforge` front door. The doctrine's own worked
example scores **0/3** on the live surface. That is the runner working — it
reports the corpus honestly — but it means the first real report will be almost
entirely red, and that must be framed as the baseline, not as a broken tool.

### 4.4 Sabotage sensitivity

Buildable and cheap: run the intact fixture skill and a description-gutted copy
through the same `--tree`, assert the sabotaged score is strictly lower. Because
the oracle is a string comparison on a tool call the model actually made, a
sabotaged system **cannot** score green by having good prose — which is the exact
failure mode of every check in §1.1.

---

## 5. Risks

1. **Cost regression via the early exit.** $0.0026 vs $0.086-0.108 per trial is a
   ~35× cliff. If the kill-on-first-`Skill` path regresses (a stream-format
   change, a swallowed SIGPIPE), a routine suite run silently costs $30 instead
   of $1. Mitigate with a suite-level `--max-cost-usd` hard stop and a self-test
   assertion on mean per-trial cost.
2. **The private children are structurally unreachable.** Skill discovery walks
   one level (S27), so 16 of goalforge's 19 skills are not in the selection
   surface at all — verifiable directly in this session's own skill listing,
   which carries `goalforge` and `goalforge-run` and no `goalforge-<child>`.
   Positive *selection* cases for them can never pass. Pointing the runner at all
   19 produces 16 permanent zeros that read as a broken runner. The
   SELECTION/ROUTING split in C2 is not a refinement; without it the metric is a
   lie.
3. **The measured surface is the author's machine, not the package.** Probes 2
   and 3 both selected `lean-ctx`, which is what the resident CLAUDE.md lean-ctx
   replace-mode block and the MCP instruction blocks steer toward. pass^k is
   therefore not comparable across machines, nor across dotfiles commits that
   touch CLAUDE.md. Add a pinned `--config-dir` snapshot leg for reproducibility
   alongside the live leg, and never compare numbers taken under different
   resident context.
4. **Ratchet coupling.** Following symlinks adds 19 skills to the census;
   `ratchet-census.sh` cross-checks two oracles and guards fixture exclusion on
   both sides, and the wp-27 floor of 48 was set on the unfollowed count. D5 ships
   the follow opt-in for exactly this reason; flipping the default without
   re-baselining turns wp-27's gate red for an unrelated cause.
5. **Vendored-upstream drift, and the duplication it forces.** `skill-creator/`
   is Apache-2.0 upstream, so `run_eval.py` must not be extended in place — but
   leaving it means the corpus carries two prompt drivers, which is the S34
   pattern the doctrine keeps re-finding. Record retiring `run_eval.py` as owed
   once the shared runner covers description-tuning, and do not let the debt go
   unrecorded.
6. **Do not port `run_eval.py`'s clone mechanism.** It measures a synthetic
   command file carrying only the description while the real skill is also
   installed — the clone competes with its own original. Any number inherited
   from it is confounded. The shared runner must exercise the installed skill.
7. **Cross-repo gate inertness.** C1's verification needs D1-D2 present; on a
   cogwright checkout without dotfiles the caller correctly skips and exits 0,
   which keeps CI green while measuring nothing. Emit an explicit `gap` marker in
   the report so coverage is measured rather than asserted, and never read a
   skipped run as a pass.
8. **§4.12 is a live veto.** The doctrine explicitly forbids a corpus-general
   runner. If C2's amendment is skipped, the next lap will refute this work using
   the document's own §4 — which is precisely what §4 exists to prevent.

---

## 6. Conflict with wp-23

**Real, partial, and resolvable — one engine, two case corpora.**

wp-23 (`plans/skill-corpus-refactor/wp-23-skill-index/`, status `spec`, no task
files authored yet) carries ticket-54 decision 4: *"the selection-accuracy eval
IS the contention measurement — no separate surface is created."* Its planned
task 3 is *"Build query→skill eval from usage.jsonl samples; record status-quo
baseline incl. abandonment rate"*, and its external review already demands
dev/holdout split, **pass^k**, chance-corrected baselines, and deterministic
ground-truth-ID scoring with LLM judging banned.

That is the same measurement object as doctrine Item 8. The overlap is the
**execution engine**; the divergence is everything around it:

| | wp-23 | Items 8-9 successor |
|---|---|---|
| Case source | sampled real `usage.jsonl` traces (never invented) | authored `evals/evals.json` (3/3 bar, named-owner) |
| Question | what is the status-quo selection accuracy | does this skill's boundary contract still hold |
| Class | capability eval, baseline + holdout | regression suite, model-upgrade-gated (T15) |
| Extras | BoR / chance correction, abandonment proxy, child→parent credit policy | shape gate, sabotage leg |

Resolution: **this extraction delivers the engine; wp-23 keeps the science.**
The runner exposes `--tree`, `--cases`, `--trials`, and pass^k reporting. wp-23
supplies a second `--cases` file built from traces, plus its sampling protocol,
ground-truth policy, chance correction, and the baseline record — and gains a
`depends_on` edge instead of re-scoping an engine it has not yet specified
(commit D6).

One caveat that must not be blurred: wp-23's other leg is a **QMD retrieval**
eval over the existing `skills` collection (430 files, `**/evals/**` ignored).
Retrieval accuracy and live-model selection accuracy are different measurements
on different candidate spaces. The shared runner covers the second only; wp-23
keeps the first, and reporting them under one number would be the error.
