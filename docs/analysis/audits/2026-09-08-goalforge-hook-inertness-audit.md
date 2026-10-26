# goalforge hook inertness audit — the guardrail layer that never ran (2026-09-08)

**Scope:** the four `packages/goalforge/hooks/*.sh` PreToolUse/PostToolUse guards,
their PLANS_ROOT resolution, their self-tests, and the wiring that is supposed to
load them.
**Method:** execution against real repository data. Every claim below was produced
by running the code, not by reading it. Each carries the command that reproduces it.

**Trigger:** the `wayfind-validator-parity` postmortem recorded that
`goalforge-open-questions-gate.sh` was inert because its bullet regex missed
numbered questions, and made fixing that regex the top next-session item. The
regex was real but third in line: two independent defects above it meant the gate
could not have fired regardless of its pattern.

---

## The one-sentence finding

**Every goalforge hook was structurally incapable of firing in this repository,
while all 62 of their self-tests reported green** — because the tests build a
fixture shape that the real tree never takes.

---

## R1 — PLANS_ROOT resolution fails when `plans/` is its own git repo

**Severity: CRITICAL.** One shared resolver; all four hooks fast-path through it.

`hooks/goalforge-plans-root.sh`, `goalforge_plans_roots`, leg 2 emitted:

```bash
gitroot="$(git -C "$(dirname -- "$file")" rev-parse --show-toplevel 2>/dev/null)"
[ -n "$gitroot" ] && printf '%s\n' "$gitroot/plans"
```

This repository keeps `plans/` as its **own standalone git repo**, nested in and
gitignored by the public parent (`.gitignore:12`) — the arrangement the project's
local rules require, so planning artifacts never reach public history. For any file
below it, `rev-parse --show-toplevel` returns the *plans directory itself*, so the
candidate root became `<repo>/plans/plans`, which does not exist.

`goalforge_under_plans_root` therefore returned false for **every** plan file in
the repo, and every hook exited 0 at its fast path.

Reproduction (against the pre-fix resolver):

```bash
. packages/goalforge/hooks/goalforge-plans-root.sh
goalforge_plans_roots "$PWD/plans/<feature>/<wp>/overview.md"
# -> <repo>/plans/plans
# -> $HOME/.claude/plans
goalforge_under_plans_root "$PWD/plans/<feature>/<wp>/overview.md" && echo yes || echo NO
# -> NO
```

**Fix:** leg 2b — when the resolved git root is itself named `plans`, the git root
*is* the plans root.

```bash
case "${gitroot##*/}" in plans) printf '%s\n' "$gitroot" ;; esac
```

**Observable effect of the fix.** `goalforge-single-writer.sh` is the one guard
that was independently wired, so its behaviour change is directly measurable on a
real work package:

| | exit | output |
|---|---|---|
| before | 0 | *(silent)* |
| after | 2 | `direct mutation of 'status:' … is blocked — use the sanctioned writers` |

That guardrail had never fired in this repository.

### Why the self-tests did not catch it

Every fixture built `plans/` as a plain subdirectory of a synthetic git root:

```bash
git init -q "$d/leg2repo"
mkdir -p "$d/leg2repo/plans/f"
```

That shape does not occur in the real tree. The suites were green and blind — the
same signature as the regex defect they were supposed to have caught.

**Closed by:** a `leg 2b` case in all four hook self-tests, building the real
shape (an outer repo whose `plans/` is *also* a repo). Each was **red-baselined**:
with the leg-2b line removed from the resolver, exactly one case per suite goes red
and every pre-existing case stays green.

```
FAIL: leg 2b: plans/ is its OWN git repo -> exit 2 (rc=0, out='')          # single-writer
FAIL: leg 2b: plans/ is its OWN git repo -> hook engaged (rc=0, out='')    # transition-guard
FAIL: leg 2b: plans/ is its OWN git repo -> hook engaged (rc=0, out='')    # open-questions-gate
FAIL: leg 2b: plans/ is its OWN git repo -> updated: bumped (rc=0, out='') # frontmatter-touch
```

`rc=0, out=''` is the exact signature of the silent fast path: the hook never
engaged at all.

---

## R2 — the plugin that declares three of the four hooks is not installed

**Severity: HIGH.** Independent of R1: even with R1 fixed, three hooks are not
registered with any runtime.

- `.claude-plugin/marketplace.json` declares `goalforge` → `./plugins/goalforge`.
- `plugins/goalforge/hooks/hooks.json` wires `goalforge-transition-guard.sh`,
  `goalforge-open-questions-gate.sh` (PreToolUse, matcher `Edit`) and
  `goalforge-frontmatter-touch.sh` (PostToolUse) via `${CLAUDE_PLUGIN_ROOT}`.
- `~/.claude/settings.json` `enabledPlugins` lists `interview@cogwright` but has
  **no `goalforge@cogwright` key at all** — absent, not `false`.
- `~/.claude/plugins/installed_plugins.json` has no goalforge entry.

A plugin that is not installed contributes no hooks, so that `hooks.json` has never
been read. Only two goalforge hooks run at all, and both bypass the plugin:

| hook | how it runs |
|---|---|
| `goalforge-single-writer.sh` | absolute path in `~/.claude/settings.json` |
| `goalforge-pre-commit.sh` | dotfiles `.git/hooks/pre-commit` |

Reproduction — a PostToolUse Edit of a real `plans/**/overview.md` with
`updated: 2020-01-01` leaves the field unchanged, while running the same hook by
hand on the same payload bumps it.

**Status: NOT FIXED.** The one-line change is
`"goalforge@cogwright": true` in `enabledPlugins`. It was not applied here because
writes to that file are outside this session's permitted scope.

---

## R3 — the open-questions gate miscounts in both directions

**Severity: HIGH** (latent behind R1 and R2; live once either is fixed).

`hooks/goalforge-open-questions-gate.sh` matched question items with:

```python
b = re.match(r"^\s*[-*]\s+(.*\S)\s*$", ln)
```

Two distinct defects in one pattern:

**(a) `[-*]` — ordered lists are invisible.** Work packages write open questions
as `1. **Question?**`. Those counted as zero, so the gate reported *no open
questions* for a WP holding several.

**(b) `^\s*` — indented sub-lists are counted as questions.** A question body
routinely carries an indented list (consumers, options). Each of those items was
counted as a question of its own.

Defect (b) is the more interesting one, because it means the gate was wrong even
where it appeared to work. On `wp-03` the pre-fix gate returned `4`, matching the
true count of four questions — but those four were the four *indented consumer
bullets* inside question 2's body. The four numbered questions contributed nothing.
A correct-looking number produced by an entirely wrong mechanism.

**Fix:** a top-level-anchored pattern accepting both list forms.

```python
b = re.match(r"^(?:[-*+]|\d+[.)])\s+(.*\S)\s*$", ln)
```

Gate output against the four real work packages, before and after:

| WP | before | after | actual |
|---|---|---|---|
| wp-01 | 0 | 2 | 2 |
| wp-02 | 0 | 3 | 3 |
| wp-03 | 4 *(wrong mechanism)* | 4 | 4 |
| wp-04 | 0 | 3 | 3 |

**Closed by:** four new self-test cases — ordered list with wrapped continuation
lines, ordered list with resolution markers, mixed `-`/`1.`/`+` markers, and an
indented sub-list that must **not** count. Red-baselined:

```
FAIL: numbered OQ -> count 0 (want 2)          # under the old [-*] pattern
FAIL: mixed markers -> count 1 (want 3)        # under the old [-*] pattern
FAIL: nested sub-list counted -> count 3 (want 0)   # under the old ^\s* anchor
```

One of the four new cases (ordered list with resolution markers → count 0) passes
under the old pattern as well, for the wrong reason — the old pattern counts zero
items there regardless. It is retained because it guards a real property of the new
pattern, but it is **not independently red-baselineable** and should not be counted
as evidence.

---

## The class, and what it costs

All three defects are one class: **a check that reports green while being
structurally incapable of firing.** A false sensor is worse than no sensor, because
it manufactures confidence.

Two second-order instances of the same class were found in the checking apparatus
itself:

1. **`~/.claude/hooks/tests/goalforge-open-questions-gate.test.sh` has been red
   since it was written.** Its only block case, C1, asserts exit 2 and gets exit 0,
   because it builds its fixture in a bare `mktemp -d` — under no plans root, so
   the hook fast-paths before the gate logic is reached.

2. **Nothing runs those suites.** `~/.claude/hooks/tests/` holds 41 suites; there is
   no run-all script and no CI workflow in the dotfiles repo. Running all 41 by hand
   (`timeout 20 bash <t> </dev/null`) yields two non-zero results:

   ```
   1    goalforge-open-questions-gate
   124  graphify-guarded-update
   ```

   Only the first is a defect. `graphify-guarded-update.test.sh` is **green** — it
   takes 62.6 s, and the 124 was produced by the 20 s budget of the ad-hoc runner,
   not by the suite. Recorded because it is instructive: the first runner anyone
   writes for these suites will mis-report a passing suite as broken unless its
   timeout is set from measurement.

   A red suite that nothing executes is indistinguishable from a green one.

3. **Four of the six cases in that red suite cannot fail either.** Mutating the hook
   to block unconditionally leaves C2–C5 green. Only C1 and its message assertion
   respond to the hook's behaviour at all — and C1 is the one that is broken.

### The cost, measured

The postmortem that preceded this audit recorded ~2.25M subagent tokens across five
rounds of adversarial review over the same work packages, producing zero lines of
code. That review never ran a hook against a real file. One call —

```bash
goalforge_under_plans_root "$PWD/plans/<feature>/<wp>/overview.md"
```

— would have exposed the entire stack.

The operative rule is already written in the project's own policy: *verify the
world, not the agent's report.* What was missing is that **running a script's
`--self-test` is not verifying the world.** It is verifying the fixture. Where the
fixture and the world disagree about shape, a green suite is evidence of nothing.

---

## Sweep — how widespread the class is

R1–R3 were found by hand. A five-dimension sweep then hunted the same class across
the whole harness, with every candidate handed to an independent agent instructed to
**refute it by default** and to accept it only after personally reproducing it.
24 agents, 0 errors. **13 confirmed, 1 confirmed-without-impact, 5 refuted.**

The refutations matter as much as the confirmations — one of them corrected a claim
made earlier in this same audit (the `graphify` timeout above).

### Confirmed — HIGH

| Where | Defect |
|---|---|
| `packages/goalforge/hooks/goalforge-pre-commit.sh:69` | **R1's cause, second instance.** Its predicate needs a literal `plans/<feature>/` segment in the staged path. Inside the plans repo, staged paths are rooted at the feature (`wayfind-validator-parity/overview.md`), so it extracts **0 features from all 936 real WP paths**. The outer repo is the mirror image: `plans/` is gitignored, so nothing can be staged there either. `goalforge-doctor` nevertheless names the outer repo as the install target — the one repo where the gate is provably unreachable. No hook of any kind is installed in the plans repo. |
| `~/.claude/hooks/tests/hook-wiring.test.sh:28` | The entire git-guardrail layer (commit-msg, pre-push, pre-commit, post-commit, AI-artifacts upstream guard) is installed in **dotfiles only**. `cogwright` and `cogwright/plans` have none. The wiring test **passes the gap by allowlist**. |
| `packages/goalforge/scripts/goalforge-validate.sh:1565` | The `verify-path` ERROR branch is unreachable under the global plans root: its gitignore escape hatch is constant-True, because `claude/.gitignore` line 2 is `*`. |
| `packages/goalforge/scripts/goalforge-validate.sh:1928` | `--feature <slug>` prints `OK — <slug> clean` and exits 0 for a slug **that does not exist**. |

### Confirmed — MEDIUM

| Where | Defect |
|---|---|
| `~/.claude/hooks/hooks.json:10` | **30 hook declarations on a surface no runtime reads** — including the autopilot `AskUserQuestion` safety tripwire. R2's class, at 30× the scale. |
| `~/.claude/hooks/idea-ledger-warn.sh:67` | Stop hook, fires every session. Reports **0 warnings against 63 non-terminal ideas** in the global portfolio: its resolver lacks the `claude/plans` nesting leg, and its `$HOME` fallback names a directory that does not exist. Silent even when the cwd *is* the directory holding the 42 KB ledger. The canonical shared resolver (`skills/idea/scripts/idea-paths.sh:39-49`) has both legs; this hook was never given them. |
| `~/.claude/hooks/skill-precommit.sh:95` | The skill-validation ratchet cannot see **any** of the 19 `SKILL.md` files of the goalforge/wayfind/prototype system — its `skills/.../SKILL.md` predicate matches no real source path in either repo. |
| `~/.claude/skills/idea/scripts/idea-paths.sh:44` | `idea-review-reminder` reports the **global** portfolio as if it were the project's whenever the session cwd is inside `plans/`. |
| `~/.claude/hooks/stub-body-drift.sh:167` | Limb 2 globs only `run.sh`, `check.sh`, `*.test.sh` — the corpus's real eval harnesses `e2e.sh` and `mutate.sh` are never scanned. |
| `~/.claude/hooks/tests/goalforge-open-questions-gate.test.sh:19` | C2–C5 stay green against a hook sabotaged to block unconditionally. |
| `~/.claude/hooks/tests/goalforge-open-questions-gate.test.sh:39` | C1's fixture sits outside every plans root. **R1 does not contribute** — this is an independent defect in the test. |
| `.github/workflows/validate-plugins.yml:90` | No surface anywhere reports a red hook suite: CI runs only `--self-test`, dotfiles has no CI, nothing executes `hooks/tests/*.test.sh`. |

### Confirmed, no impact

`~/.claude/hooks/goalforge-checkpoint.sh` — a SubagentStop hook declared on zero
surfaces whose trigger variable `SDD_EXECUTE_TASK` is exported by nothing. Dead in
two independent ways, so fixing either changes nothing observable.

### Refuted (5)

Recorded so they are not re-found: skill-hygiene/agent-hygiene hooks reading
`.tool_input.file_path`; `goalforge-doctor` arm 5's probe argument; the CI
self-test step's skip behaviour; `hook-wiring.test.sh` vs R2; and the `graphify`
timeout. Each was reproduced and then rejected on interpretation, not on
reproduction — the finder saw something real in every case and drew the wrong
conclusion from it.

### What the sweep says about the class

Nine of the thirteen confirmed defects are **scope resolvers or wiring surfaces** —
code deciding *whether to look*, not code deciding *whether something is wrong*.
That is where inertness concentrates, because a resolver that answers "not mine"
produces exactly the same observable output as a check that ran and found nothing.

---

## State after this audit

| | |
|---|---|
| R1 | fixed, red-baselined in 4 suites |
| R2 | **open** — one line in `enabledPlugins`, outside this session's write scope |
| R3 | fixed, red-baselined in 3 of 4 new cases |
| self-tests | 70 passing across the four hooks (was 62) |
| `plugins/goalforge/` | regenerated; `goalforge-generate.sh --check` clean |
| `~/.claude/hooks/tests/goalforge-open-questions-gate.test.sh` | **still red** — mis-rooted C1 fixture, not yet repaired; C2–C5 also inert |
| `graphify-guarded-update.test.sh` | green (62.6 s) — no defect |
| test runner | **does not exist** |
| sweep findings | **13 confirmed, none fixed** — see the Sweep section |

The four HIGH sweep findings are untouched. Two of them
(`goalforge-pre-commit.sh:69`, and the git-guardrail layer missing from two of three
repos) mean the commit-time gates are as inert as the tool-time ones were.
