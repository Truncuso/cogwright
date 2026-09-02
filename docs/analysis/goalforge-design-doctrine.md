---
title: Design Doctrine — Skills, Skill Systems, Commands, Evals
type: analysis
date: 2026-09-01
status: draft
scope: cogwright/packages/goalforge, with corpus-general doctrine
supersedes: none
---

# Design Doctrine — Skills, Skill Systems, Commands, and Their Evaluations

This document states how we want skills, skill systems, commands, and evaluations to be
designed, and gives the ordered change set that brings the goalforge package to that
standard. It is written to survive with every external URL dead: sources are cited as
provenance (who observed what, when, and where the observation is recorded in this repo),
never as a dependency the reader must fetch to understand a rule.

Four inputs stand behind it: the corpus-resident rules and their measured enforcement
surfaces; a structural map of goalforge as built; a per-skill quality measurement taken on
2026-09-01 by executing every eval harness in the package; and an adjudication of the
cogwright planning corpus against live state. Where those inputs disagree with each other,
this document records which one won and why — that adjudication is the point of writing it
down, and re-deriving it next lap is waste.

---

## 0. How to read this

### 0.1 Enforcement markers

Every rule carries exactly one marker describing what happens today, not what should
happen. The gap between the marker and the rule's importance is the design signal: a
load-bearing rule marked WRITTEN is a promotion candidate, and promotion beats adding
another written rule.

| Marker | Meaning |
|---|---|
| **ENFORCED** | A script or hook can fail the action. The mechanism is named inline. |
| **WARN** | A script emits a finding and always exits 0. Nothing is blocked. |
| **MEASURED** | A script reports the fact. Nothing reads the report as a gate. |
| **WRITTEN** | Prose only. No code path anywhere. |
| **STRUCTURAL** | A property of the runtime, not a check. Cannot be violated. |

### 0.2 The enforcement map as it stands

Across the whole skill surface there are exactly four hard gates:

1. `scripts/validate-skill.py`, run from `hooks/skill-precommit.sh` via the installed
   `.git/hooks/pre-commit` in dotfiles, ratcheted against
   `data/skill-learning/validate-baseline.txt`. This is the only hard gate on skill
   authoring. `metadata.version` failures always block and never ratchet.
2. `hooks/agent-dispatch-model-guard.sh`, registered in both `settings.json` and
   `hooks/hooks.json`, blocking implicit-model dispatch and fable-as-worker at every
   dispatch depth including headless `claude -p`.
3. `skill-autoresearch`'s reward constraint: a variant with `over_budget == true` is never
   promoted regardless of pass-rate gain. Reward-only; blocks nothing a human does.
4. `skills/goalforge/scripts/goalforge-validate.sh`, which errors on a missing or invalid
   `goal.verification.strategy`.

Everything else on the skill surface is WARN, MEASURED, or WRITTEN. `skill-hygiene.sh`
computes roughly six facts per skill; the PostToolUse edit-time hook surfaces two of them
(`over_budget` and the gotcha-dedup verdict). The required-marker and trigger-bar warnings
exist and are invisible at the moment an author could act on them. Any plan that assumes
the prose is enforced will be wrong in the direction of thinking the corpus is healthier
than it is.

### 0.3 The one-line design test

Before adding any rule to this document, ask: *can this be a script?* If yes, write the
script instead. A written rule is a request that a future reader be careful; an enforced
rule is a property of the repository. We have measured, repeatedly, that written rules in
this corpus drift out of agreement with the corpus within weeks.

---

## 1. The doctrine

### 1.1 What a skill is

**S1. A skill is a body of procedural expertise that a model loads on a trigger.** If the
procedure is invariant — the same command sequence every time with no branch — it is a
script wearing skill clothes; ship the script. If the procedure has no branch *and* no
constraint to state, it is nothing; delete it. — **WRITTEN**

*Rationale: the branch is what a model is for. A skill with no branch pays context rent
for a decision it never makes.*

**S2. Level of freedom runs in two directions.** Downward: a fixed workflow is a script.
Upward, the autonomy register: a skill that runs unattended states **constraints and
reference material, not step lists**, because a step list is a promise the environment
will match the author's machine, and unattended runs are where that promise breaks. —
**WRITTEN**

**S3. Fragility is a second, independent axis.** A *loose* step (many valid paths, cheap to
be wrong) gets prose. A *fragile* step (must be exactly right) gets a deterministic script
**even when its path varies**. Tests cannot buy trust for a fragile step; the cure is
removing the guess from the loop, not adding assertions around it. — **WRITTEN**

**S4. Capability skills decay; preference skills persist.** A capability skill teaches the
model something it will eventually know natively, and its value trends to zero as base
models improve. A preference skill encodes *our* choices, and survives every model upgrade.
Mark which one you are writing. — **MEASURED** (`skill-hygiene.sh` emits `skill_kind`;
`validate-skill.py` does not check it)

**S5. Retirement is ablation-gated and human-gated.** Run the eval suite with and without
the skill. If *without* holds the bar, it is a retirement candidate — never an automatic
retirement — and its eval suite is kept as a regression sentinel after the skill goes.
Ablation evidence beats tenure. — **WRITTEN** (`skill-autoresearch` ablate mode is the
tool; nothing schedules it)

**S6. Stateless by default.** A stateful skill keeps state under
`~/.claude/data/<skill>/`, documents the path in its body, detects resume, and is
idempotent on re-entry. — **WRITTEN**

**S7. Context is a skill, not a constant.** Brand voice, formatting conventions, design
tokens, ICP descriptions live in their own file and are *pulled* at runtime, so one edit
changes every consumer. — **WRITTEN**

### 1.2 Identity and frontmatter

**S8. The frontmatter satisfies the agentskills.io spec:** `name` at most 64 characters
from `[a-z0-9-]` with no leading, trailing, or consecutive hyphens; `description` at most
1024 characters; `compatibility` at most 500. — **ENFORCED** (`validate-skill.py`,
ratcheted at pre-commit)

**S9. `metadata.version` is a quoted semver string.** Unquoted `1.10` is a YAML float and
fails. Version failures never ratchet. — **ENFORCED** (`skill-precommit.sh`)

**S10. Adjudicate every frontmatter field; do not copy a template.** An omitted field is
free. A wrong one is a standing defect that misroutes every future invocation. Walk the
whole lever table at authoring time: `description`, `disable-model-invocation`,
`user-invocable`, `argument-hint`, `allowed-tools`, `disallowed-tools`, `model`/`effort`,
`context: fork` plus `agent`, `paths`, `shell`, `hooks`, and dynamic backtick-command
injection. — **WRITTEN**

**S11. The declared `name` is the skill's identity; the directory basename is its
location.** They are permitted to differ, and in a nested package they usually must —
`skills/goalforge/capture` declares `goalforge-capture` so the name is unique in a flat
namespace while the path stays readable. Anything that resolves a skill by name must
resolve against declared names, not basenames. — **ENFORCED for top-level skills**
(`validate-skill.py` errors when `name` differs from the basename) **and WRITTEN for
nested ones**, which is a known, undocumented divergence; see §4.

*Rationale, and this is not theoretical: the corpus trigger-eval gate excludes a skill from
citing itself using the **basename** while matching owners against **declared names**.
Wherever the two differ, a nested skill satisfies the named-owner rule by citing itself.
Measured radius across the corpus: 25 of 178 reachable skills. Within goalforge alone the
two differ on 16 of 19 skills.*

**S12. The name denotes the artifact produced and is vendor-neutral.** `spec`, not `prd`;
`tickets`, not `issues`. A rename is a breaking change: MAJOR bump plus a migration note
carried in the commit message as the release note. — **WRITTEN** for the policy;
the semver *format* is ENFORCED by S9.

### 1.3 Invocation, and the anti-bloat law

**S13. Invocation is binary, not a spectrum.** A skill is either model-invoked — the
default, which taxes every turn's context with its description — or user-invoked
(`disable-model-invocation: true`), which costs nothing standing. There is no
"agent-triggered" middle tier; anything that reads like one is a model-invoked skill with
a description that hides its cost. — **WRITTEN**

**S14. One model-invoked front door per skill family.** N specialists behind a router cost
one description, not N. Model-invoke a skill only if **both** hold: another agent or skill
must reach it unassisted mid-task, **and** auto-firing is usually the right outcome. A
standalone specialist that only ever fires by hand takes
`disable-model-invocation: true`; a cross-family standalone that keeps model-invocation
records `metadata.invocation-rationale` in the skill itself, so the next reader can
adjudicate the cost rather than inherit it. — **WRITTEN**

*Rationale: description text is the only skill cost paid unconditionally, on every turn,
whether or not the skill is used. It is the one budget where the corpus can degrade without
anyone noticing.*

**S15. Compose by front door, never by making a child model-invoked.** A parent composes a
child by exposing it in the router table and loading it by path. Making the child
model-invoked to "make composition easier" reintroduces the N-descriptions cost and
duplicates the routing decision in two places. — **WRITTEN**

**S16. Every description states when NOT to use the skill.** Over-triggering is a
description defect on the same rung as under-triggering, and it is the more expensive one,
because a skill that fires wrongly displaces the skill that should have fired. — **WARN**
(`skill-hygiene.sh` runs a lexical probe for `SKIP`, `when NOT`, `not for`, `do not use` —
presence only, no semantics — and the warning is not surfaced by the edit-time hook)

### 1.4 The body

**S17. `## Gotchas` (or `## Known Failure Modes`) is mandatory** for router parents, chain
parents, and standalone leaves. A `metadata.skill-role: delta-child` is exempt, and that
exemption is claimed explicitly by the marker, never inferred from a path. — **WARN**
(hygiene counts list items under the header; a bare header with no items does not count)

*Rationale: gotchas are the highest-signal content in any skill because they are the only
part that cannot be re-derived from the model's priors.*

**S18. Bodies come from traces, never from a prompt describing the task.** Walk the task by
hand and record what actually worked, or synthesize from artifacts that already exist. The
detection heuristic is **generic mush**: a sentence like "handle errors appropriately" came
from no trace and belongs to no skill. — **WRITTEN**

**S19. Read drafts for their silences.** Every omission delegates that decision to model
priors. Each unspecified behavior is either filled with an instruction or left as an
explicitly named branch — never left implicit and unnamed. — **WRITTEN**

**S20. Budget: 500 body lines, 12 gotcha entries, 1024 description characters.** This is a
budget, not a gate: a `progressive-disclosure-exception: <reason>` or
`composition-seam: <reason>` marker with a non-empty reason suppresses the over-budget
finding. — **WARN** for lines and gotchas (`skill-hygiene.sh`, surfaced at edit time);
**ENFORCED** for the description cap via S8.

**S21. The disclosure ladder is a ladder: in-skill step, then in-skill `references/*.md`,
then an external pointer.** Branching is the disclosure test — content the agent needs on
*every* path stays inline; content it needs on *one* branch moves down a rung. A pointer's
**wording**, not its target, decides whether the agent follows it, so when a must-have
reference is under-reached, sharpen the pointer before inlining. Inlining is the load
regression the ladder exists to prevent. Co-locate one concept's definition, rules, and
caveats under one heading. — **WRITTEN**

**S22. Bodies reference their bundled subdirectories, and for each bundled script state
the intent explicitly: RUN it, or READ it.** Use `${CLAUDE_SKILL_DIR}`; never a hardcoded
absolute path. — **WRITTEN**

*Rationale, measured in this package: two eval harnesses reach outside the package by
absolute path — `verify/evals/run.sh` targets `$SKILL_DIR/../../implement/SKILL.md`, which
resolves to `packages/implement/SKILL.md` and does not exist, and
`archive/evals/run.sh:126` targets `$HOME/.claude/skills/goalforge/scripts/...`. The first
has been reporting a red skill since the package was extracted. The second silently skips
its entire behavioral block when the path is absent, which is worse.*

**S23. Front-load the leading word and reuse it verbatim.** Define each key term once and
use the same word in the body, the references, and any code the skill emits. Collapse
synonyms: one trigger phrase per branch. Trigger phrases in the description and leading
words in the body do different jobs and must not be confused. — **WRITTEN**

**S24. Every step ends on a completion criterion that is checkable and exhaustive.** Not a
vibe. A step-less reference body carries the equivalent exhaustive bound ("every rule in
this table applied"). A criterion that can be sharpened is never grounds for a new skill —
sharpen it. — **WRITTEN**

**S25. Five failure modes, five distinct cures. Do not treat them interchangeably.**
Premature completion is cured by sharpening the exit criterion; duplication by one trigger
per branch; sediment by deduplicating before appending; sprawl by the disclosure ladder and
then a split; a no-op by deleting the whole sentence — never by trimming a no-op into a
shorter no-op. — **WRITTEN**

**S26. Splitting has exactly two axes: by branch, or the sequence cut.** Reach for the
sequence cut only when a completion criterion resists sharpening **and** a rush past it has
been *observed, not hypothesized* — and then only across a real context boundary (a fork or
a dispatch). An inline call across a "split" buys none of the rush-prevention that
motivated it. — **WRITTEN**

### 1.5 Skill systems

**S27. Discovery walks exactly one level.** `skills/<name>/SKILL.md` is trigger-able;
`skills/<name>/<sub>/SKILL.md` is not. **Physical nesting is therefore the privacy
mechanism** — there is no flag and no naming convention involved. — **STRUCTURAL**

*This single property is the load-bearing fact of the whole skill-system design. Every
visibility rule below is a consequence of it.*

**S28. Three visibility classes.**
- **PUBLIC** — top-level, trigger-able by bare name. Justified when the capability is
  reused across two or more systems, or is a user-facing front door.
- **PUBLIC-PINNED** — physically nested (therefore not discoverable) but reachable as
  `/name` through a thin file in `commands/` that loads the nested `SKILL.md` by path.
- **PRIVATE** — nested, reached only by path, from its parent or a command.
— **WRITTEN**

**S29. Two composition modes; do not force the wrong shape.** A **chain** is a fixed
ordered pipeline declared in a co-located `chain.yaml`. A **router** is parent base
expertise plus a `## Capabilities` table with no fixed order, where the parent loads the
matched child by path. A router with an implicit fixed order is a chain that has hidden its
contract; a chain with genuinely optional unordered steps is a router wearing a schedule. —
**WRITTEN**

**S30. A parent never duplicates child logic; it delegates.** — **WRITTEN**

**S31. Nest only what is parent-specific.** A sub-skill reused across systems stays PUBLIC
and is referenced by bare name. Duplicating it into a parent creates two bodies that will
diverge. — **WRITTEN**

**S32. The parent description is the union of its own trigger surface and every PRIVATE
child's.** Adding or removing a private child **requires** updating the parent description
in the same change. This is a description-and-trigger event — the top rung of the
improvement ladder — and must never be folded into `## Gotchas`. — **WRITTEN** as a rule;
the nominal enforcement is a per-skill eval case asserting each child's key trigger phrase
appears in the parent description, which exists only where an author wrote one. No
corpus-wide check.

**S33. No skill autonomously rewrites another skill mid-run.** Determinism at runtime;
learning out of band. Improvements go through the propose-only improvement path, are diff
reviewed, and are git-committed. Global skills are propose-only; repository-local skills may
auto-amend. — **WRITTEN**

**S34. Check the disk before acting on a layout.** A working system is a migration, not a
greenfield build. Read the real on-disk state and rewire every bare-name reference in the
same change. — **WRITTEN**

*Rationale, and this is the most repeatedly vindicated rule in the corpus: three separate
work packages found that the document's claim about the corpus was false when checked. The
default assumption should be that the map is stale.*

**S35. Modular beats mega.** Improve a shared child once and every system that chains it
improves. — **WRITTEN**

**S36. Chain context efficiently.** For three or more steps, prefer chain-level
`context_fork: true` with per-step `fork: true`, file handoffs via `input`/`output`, and
bang-command injection so the model never spends tokens reading the handoff file. Note that
`context` is a **scalar**: `context-fork` and `context: {fork: true}` are not fields and
no-op silently. — **WRITTEN**

**S37. The spine: skill (capability), skill system (chain or router), workflow
(composition), agent (actor). Pick the lowest tier that solves the problem.** Most needs
are a skill, not an agent. Reach for a standalone agent only when the task needs a distinct
*perspective* plus token isolation — when the agent **is** the lens. — **WRITTEN**

**S38. Lifecycle is part of the contract at every spine level.** Whatever a component
registers — hooks, telemetry rows, index entries, symlinks, minted capabilities — it must
be able to unregister. The admission test: *if removing it leaves residue you cannot
enumerate, it is not a plugin, it is a migration.* Idempotent re-install is not
revertibility. The removal drill is an eval, run for real and asserted deterministically,
never assumed. — **WRITTEN**

*Rationale: residual **authority** is the highest-cost residue. A capability that survives
its component re-arms the private-data / untrusted-input / egress trifecta with nothing left
to explain why the capability exists.*

**S39. Declared dependencies are half a contract; a notification path is the other half.**
Pull-only auditing is a recorded debt, not a default. A sweep finds drift late; a
notification prevents it. — **WRITTEN**

**S40. Append-only history.** Once state has been consumed downstream, append a correction
event rather than editing in place. Scope: logs, ledgers, decision records, traces. Curated
fact stores and generated indexes are regenerate-by-fold surfaces and are not violations. —
**WRITTEN**

**S41. Never rewrite a failure into an empty success at a shared read layer.** An error that
becomes an empty result with exit 0 is the inverse of a notification: it removes the signal
at exactly the layer most consumers trust. — **WRITTEN**

*Measured instance: a hygiene reader reporting `0 0` on a wrong-shaped eval file. The error
message that results ("below the bar, trigger_pos=0") points the reader at the cases, which
are correct, rather than at the shape, which is wrong. Three of seven workers independently
"fixed" the harness in response, producing false passes.*

**S42. Underscore-prefixed directories under `skills/` are not skills** (`_shared/`,
`_proposals/`). No `SKILL.md`, never in the namespace, documented with a plain `README.md`.
— **WRITTEN**

**S43. Installing a third-party skill is a supply-chain decision, not an authoring one.**
Vet it as you would any dependency. — **WRITTEN**

### 1.6 Commands

**S44. Commands and skills are merged: every top-level skill directory already *is*
`/name`.** No wrapper file is needed or wanted. — **STRUCTURAL**

**S45. A file in `commands/` exists for exactly one purpose — to pin a *nested* member as
`/name`.** A wrapper that duplicates a same-name top-level skill is redundancy, not reach,
and is a deduplication candidate. — **WRITTEN**

**S46. A command is a dispatch contract, and it states how it dispatches.** Where the child
is nested and therefore not resolvable by the Skill tool, the command says so explicitly and
instructs reading the child `SKILL.md` by path. Where the child is a real registered skill,
the command invokes it. Silence on this point is how a command ends up telling the model to
call something that answers "Unknown skill". — **WRITTEN**

**S47. One authoritative copy of a command.** A command that exists as two files in two
trees will diverge, and every reader after the divergence has to adjudicate. If a harness
requires a copy, the copy is a symlink or a generated artifact with a generation marker —
never a hand-edited second original. — **WRITTEN**

*Measured in this package on 2026-09-01: all five goalforge commands exist as separate,
hand-edited files in both `packages/goalforge/commands/` and `dotfiles/claude/commands/`,
and all five differ. Two of them carry headers that name each other as authoritative.*

**S48. A slash command cannot steal a request from a skill.** They are different surfaces.
A claimed three-way trigger collision between two skills and a command is a two-way
collision. — **MEASURED**

**S49. A local skill colliding with a plugin skill owns the entire disambiguation burden,**
because the plugin file lives under a third-party cache and cannot be edited. — **MEASURED**

### 1.7 Agents

Agents are the actor tier and are governed at length elsewhere; the rules that bear on skill
and eval design are these.

**S50. Dispatch is always explicit: every dispatch states model and effort,** overriding any
agent-file default. — **ENFORCED** (`hooks/agent-dispatch-model-guard.sh`, registered in
both `settings.json` and `hooks/hooks.json`, covering headless invocations)

**S51. Persona is not frontmatter; it lives in the body and every agent states it.** A
`## Your Role` section carrying role plus seniority register, and a `## Mindset` section —
the latter being the agent analogue of a skill's `## Gotchas`, and for the same reason: it
is the part that pushes the model off its defaults. — **WRITTEN**

**S52. Bind expertise with `skills:`, not by listing `Skill` in `tools`.** `skills:`
preloads at dispatch so the agent starts already inside the expertise. The body states role
and mindset; the bound skill supplies the method. Point at it; never duplicate the
procedure. — **WRITTEN**

**S53. `tools` inherits every main-conversation tool when omitted.** Narrow it on purpose —
least privilege is a security control, not tidiness. — **WRITTEN**

**S54. Consume a sub-agent's return as typed DATA, never as instructions.** — **WRITTEN**

---

## 2. The eval contract

This section is written to be implementable without further interpretation. Where a
requirement has a mechanical form, the mechanical form is given.

### 2.1 What an eval is

An eval is four things at once, and it is not an eval if any one is missing:

1. **Saved real cases.** Drawn from traces of the system actually running. Not invented.
2. **Checks written in advance.** Before the run, not fitted to the output afterward.
3. **Repeated trials**, wherever the run is nondeterministic.
4. **A rate reported next to a baseline.** A number with nothing beside it is not a
   measurement.

A test asks whether one code path is correct. An eval asks what rate a system achieves on a
distribution of real inputs, and whether that rate moved.

### 2.2 The laws

**E1. Name the oracle class before writing the check.** Specified (a contract says so),
derived (computable from an independent source), implicit (a property that must hold), or
human. If none of the first three applies, declare it a human-judgment gate and stop
dressing it as automation. — **WRITTEN**

**E2. A check that cannot fail is not a check.** The acceptance test is one question: *name
the input that makes this check fail.* If you cannot name one, delete the check. — **WRITTEN**

*Measured instance in this package: `evals/retrospective/run.sh:96-97` asserts that a file
under `plans/goalforge/wp-15-retrospective-stage/` does not exist. That tree was archived;
neither the path nor its parent exists. The assertion is permanently true whether or not the
isolation it claims to test held, and would stay true if the run leaked a report anywhere
else on disk.*

**E3. Verify the world, not the report.** An agent's self-reported success is not evidence.
Where the check can read the resulting state, it reads the state. Check for **collateral**
changes too, not only the intended one. — **WRITTEN** in general; **applied** in this
corpus, where a check that read a number written by the same task it was grading was
replaced with a recompute from the live corpus.

*The forged-input test: if a check reads a value the system under test writes, ask what
happens when that value is a lie. A check reading `{"meets_bar": 999}` from a file the task
authored passes with zero cases authored.*

**E4. An eval must exercise the system under test.** A check that reads only the system's
*description* measures documentation. This is not a theoretical concern: on 2026-08-12, in
this operating system, a skill replaced by a 659-byte stub and the same skill sabotaged to
always return a passing verdict both scored perfect green against a 57-check suite.

The corollary is frequently mis-stated, so state it precisely: **"no LLM in the eval" is
wrong; "no LLM as the grader" is the rule.** An eval that never invokes the system is not
rigorous, it is inert. — **WRITTEN**, and violated across most of this corpus.

**E5. Take the strongest — lowest-numbered — rung of the determinism ladder that decides the
question.**

| Rung | Check | Notes |
|---|---|---|
| 1 | Exact match | Cheapest and strongest where the output is exact |
| 2 | Regex / grep over unstructured text | Never over a structured log; see E15 |
| 3 | Schema validation | |
| 4 | Tool-call assertion | Which tool was called, with what arguments |
| 5 | State read-back | The world, after the run |
| 6 | Metamorphic relation | Output relation under a transformed input |
| 7 | Embedding similarity | |
| 8 | Model judge | Only when nothing above decides it |
| 9 | Human | Declared, not disguised |

Where a step must be exactly right, the higher-leverage move is to remove the
nondeterminism from the system under test, not to add a rung-8 grader downstream. —
**WRITTEN**

**E6. Assert properties and relations, not golden outputs.** A snapshot or approval test is
a change detector, never a correctness oracle. — **WRITTEN**

**E7. Cases come from traces.** Open-code the traces, axial-code them into categories,
count, and work the top category first. Stop collecting when roughly 20 consecutive traces
add no new category. Twenty to fifty cases is the working range for a suite. — **WRITTEN**

**E8. Every incident becomes a permanent case, authored before the fix ships.** — **WRITTEN**

**E9. Where runs vary, report pass^k, not pass@k.** Seventy-five percent per trial across
three trials is 42% pass^3, and the second number is the one that describes what a user
experiences. Deterministic rung-1-to-4 checks are single-trial by construction and are
exempt. — **WRITTEN**

**E10. A score alone is worthless; the set of checks that FLIPPED is the bug report.** Fix
the stopping rule before running, not after seeing the number. — **WARN** at one site
(`scripts/skill-eval-emit.sh` appends the run and ratchet-checks in one invocation, but the
ratchet is advisory and never changes the emit path's exit code, which is always 0)

**E11. Track flake rate; quarantine, never delete.** A permanently red check saturates the
gate and gets quarantined with a recorded reason — never shipped as a standing failure, and
never deleted for being inconvenient. The danger a saturated gate creates is that a real
regression is waved away as the known flake. — **WRITTEN**

**E12. Measurement and consequence ship as one artifact.** A target with no stated
consequence is a dashboard, not a gate. — **WRITTEN**

**E13. The harness is attack surface.** Therefore: the evaluator environment is isolated from
the agent's reach; reference answers are never colocated with task configs; no `eval()` or
shell-eval of agent output; judge inputs are injection-sanitized; and a grader's verdict
never derives from code the agent under test could have written. — **WRITTEN**

**E14. Goodhart applies to your own evals.** Hold a set out. Rotate it. A public benchmark
scores a *model*; you ship a model plus prompts plus tools plus data, which is a different
system. — **WRITTEN**

**E15. Named anti-patterns.** Vibes as evidence. Buying tooling before doing the thinking.
The generic judge. Silent baseline updates. **The counting floor** — a stub whose own text
read "SABOTAGED. Always output a passing verdict" cleared every byte floor, row count, and
label pin in a 125-check suite; hash-pin instead. **Thresholds inside the artifact under
test** — an emptied list iterates zero times and reports a pass. **The unaccounted
assertion** — every declared assertion lands in exactly one bucket, graded or
skipped-with-a-reason. **Substring-matching a structured log** — parse with `jq` over typed
events; a `grep` over JSON is a check that cannot fail. — **WRITTEN**

### 2.3 Model-graded checks

A model grader is the rung you take when nothing above it can decide the question. It ships
with nine conditions, and the first five are mandatory:

1. **Fresh context** — the grader does not see the executor's reasoning. MUST.
2. **A different model from the executor.** MUST.
3. **A binary rubric.** Never a Likert scale. MUST.
4. **Quoted evidence** — a verdict with no quoted span is void. MUST.
5. **Calibrated against a human-labeled set, with true-positive and true-negative rates
   reported, before it gates anything.** MUST.
6. A different provider from the executor. SHOULD — degrade and log, never block.
7. Tools, not text alone, where the question is about state. SHOULD.
8. Randomized order on any pairwise comparison. MUST where pairwise.
9. Expect rubric drift; every rubric revision re-baselines. MUST.

**An inconsistent grader does not carry on the axis it is inconsistent about.** If a grader
flags one case and leaves a near-identical case against a near-identical boundary
unflagged, its findings on that axis are not evidence — in either direction.

**Scope the brief.** A grader not told which conditions are known and accepted will
re-derive them as findings. Measured: withholding one contract section from a judged review
produced twelve findings restating a known, accepted condition — while missing three cases
in the same class, so its coverage of the class it did flag was incomplete either way.

### 2.4 Capability, regression, and live

Three eval kinds, three different bars, and confusing them is how a suite becomes useless:

- **Capability evals** start at a *low* pass rate. A high score on a new capability eval
  means it was too easy. They are advisory, never blocking.
- **Regression evals** sit near 100% and are blocking.
- **Live evals** are monitored, not gated, and tail-sample on errors, latency, and negative
  signal — never a uniform 1%.

A capability eval **graduates** into the regression suite when its rate reaches the bar.
That graduation is the mechanic that keeps the suite honest over time.

### 2.5 The trigger-case standard

This is the concrete, implementable part. A trigger case tests whether the skill fires on a
request that it owns, and does not fire on a request that a *named other skill* owns.

**T1. One canonical shape. No variants.** The eval file is a JSON **object** carrying a flat
`evals` array. Each case is an entry on that array. Polarity is carried by a
`should_trigger` boolean and by nothing else.

```json
{
  "skill_name": "goalforge-harden",
  "evals": [
    {
      "id": "pos-obvious-harden-request",
      "should_trigger": true,
      "prompt": "wp-04 is at status: spec — run the hardening panels and get it to ready",
      "expected_output": "goalforge-harden runs the pre-harden lint, routes the review by complexity, and proposes the hardened -> ready transition"
    },
    {
      "id": "neg-sibling-decompose",
      "should_trigger": false,
      "prompt": "the spec is signed off — break it into work packages",
      "expected_output": "`goalforge-decompose` owns spec -> WP decomposition; harden operates on an existing WP"
    }
  ]
}
```

**T2. Self-check the shape before trusting any count.** This one-liner prints two integers.
Printing nothing means the file is the wrong shape — most commonly a top-level array rather
than an object:

```
jq -r '(.evals? // empty) | select(type=="array")
       | [(map(select(.should_trigger?==true))|length),
          (map(select(.should_trigger?==false))|length)] | @tsv' evals/evals.json
```

*Ship this command inline in any conversion contract. A wrong-shaped file yields `0 0` and
an error message that points at the cases rather than the shape; the natural response to
that message is to "fix" the harness, which produces false passes. Three of seven workers
did exactly this before the self-check was added.*

**T3. Minimum coverage: at least 3 positive and at least 3 negative trigger cases,** plus
two functional cases (one valid input, one error or edge condition). — **WARN** today
(`skill-hygiene.sh` emits `below trigger bar 3/3`, gated on `skill_kind` being set, and the
warning does not reach the model at edit time)

**T4. Positives take three shapes, and all three should appear:**
1. The obvious task, phrased as a user would phrase it.
2. **A paraphrase using none of the description's own trigger words.** This is the shape
   that catches a description that only matches itself, and it is the one authors skip.
3. Cross-skill reach — another skill or agent needing this one mid-task.

**T5. THE NEGATIVE STANDARD. A negative is a near-miss that a NAMED other skill legitimately
owns, and its `expected_output` names that skill by its exact declared skill name, in
backticks.** An "unrelated topic" negative — *"what is the weather in Berlin"* — is
**inadmissible** and does not count toward the bar. It proves only that the skill is not
omnivorous, which was never in doubt. It tests no boundary.

*Rationale, and this is why the standard exists: in a router corpus the real failure modes
are a child firing where the parent should have routed, a sibling stealing the request, and
a parent firing on another cluster's work. Every one of those is a negative case. Positives
only prove reachability; negatives encode the routing boundary contract.*

**T6. Backticks are mandatory and are not cosmetic.** A bare substring match makes the gate
inert, because ordinary skill names occur in ordinary prose: `idea`, `memory`, `update`,
`write`, `handoff`, and `diagnose` all appear in the natural phrasing of case descriptions.
Measured: every negative in one package passed the named-owner gate whether or not it named
an owner, because the word "idea" appeared in the surrounding prose.

**T7. Cite the DECLARED name, which is not always the directory basename.** The gate matches
against the union of directory basenames and frontmatter `name:` values, and must follow
symlinks (`find -L`) to see linked trees. In goalforge, 16 of 19 skills declare a name that
differs from their basename.

**T8. Negative sourcing, in priority order:**
1. **A declared sibling under the same router.** Highest value — this is literally the
   boundary the package draws.
2. **The skill's own SKIP or when-NOT clause, naming the skill it points at.** The author's
   own recorded boundary.
3. **A measured near neighbour in description space**, named explicitly.

*Empirical support: a foreign-provider adversarial review returned **zero** findings against
the four packages whose negatives came entirely from priority 1. That silence is the review's
most useful positive signal.*

**T9. Admissibility — five conditions, three mechanical and two judgment.**
Mechanical (scriptable, and should be a gate): `should_trigger` is `false`; the prompt is a
plausible user request, not a synthetic non-sequitur; `expected_output` cites at least one
**other existing** skill in backticks by a resolvable name.
Judgment (this is what an adversarial review is for): the named skill genuinely would own
the request; and the case is **discriminating** — a reasonable model could plausibly have
fired the skill under test.

**T10. The discrimination test INVERTS for a router parent.** The general rule — "a prompt
naming the owner's operation so explicitly that no confusion is possible is not
discriminating" — is backwards for a router, because a router's description enumerates its
children's trigger phrases verbatim. The more explicitly a prompt names a child's operation,
the *more* likely the parent is to fire on it. The parent's SKIP clause is prose, not a
mechanism; nothing bypasses the router by construction. **A prompt that is a verbatim
substring of the router's own trigger list is the most discriminating case in the file.**

**T11. The id is documentation; `should_trigger` is what the parser reads.** Never encode
polarity in the id alone. Eight deprecated encodings are known in this corpus:
`trigger_cases[]` with `expect_invokes`; `"type": "trigger"`; `trigger-*` and
`trigger-*-no-fire` id polarity; mixed forms; `"type": "trigger_negative"`; `no-trigger-*`
with a `polarity:` field; a `no-fire-*` id prefix; `triggering: {positive, negative}`; and
`kind: "trigger"` with `expect: "TRIGGER"|"SKIP"`. Three families additionally key their
cases under `cases` rather than `evals`, which yields a permanent `0/0`.

**T12. Positive counts may legitimately DROP on conversion, and that is not a regression.**
The older counters scored `trigger-*-should-not-fire` ids as positives. A skill audited at
"5 positive" that lands on "3 positive / 5 negative" has deleted nothing; it has stopped
miscounting. Report before and after honestly rather than padding positives back up.

**T13. Conversion is a rename, not a rewrite.** `prompt` and `expected_output` stay
byte-identical; only the polarity encoding moves. Re-running the conversion must produce a
zero diff. The one exception: a legacy negative with no named owner gets its
`expected_output` amended with one — and the owed *new* negatives are authored anyway, so
the bar is met by purpose-built sibling cases and the amended legacy case is surplus, never
load-bearing.

**T14. Harness parity: if a skill's `run.sh` parses the old shape, fix it in the same
commit.** A green `run.sh` on a stale parser is a false pass. Writing a sibling `evals` array
alongside the legacy key is forbidden for harness-reading files; assert the legacy key is
absent.

**T15. The trigger regression sweep is model-upgrade-gated, not calendar-gated.** A base
model change is the actual drift trigger. The sweep re-runs the cases that exist; it does not
author the missing ones. — **WRITTEN** (nothing schedules it)

### 2.6 Harness requirements

**H1. Layout.** `evals/evals.json` holds the cases. `evals/run.sh` is a thin entry point and
the stable contract — exit 0 means pass. `evals/expected/` holds goldens. `evals/results/`
and `evals/workspace/` are both gitignored. **Eval scratch lives inside the skill**, never in
a sibling workspace directory.

**H2. Deterministic, with a binary or numeric signal.** A function from output to boolean
must exist. A model judge is admissible only for genuinely subjective properties, only
through a human-in-the-loop path, and **never** as an unattended reward signal.

**H3. Scripted when scriptable.** `run.sh` stays a thin entry point; real logic goes in
`run.py` or `run.ts`. Agent-driving uses the official SDK — never hand-rolled scraping of CLI
output.

**H4. JSON in, JSON out.** Each **red** case records both the failing assertion and the
observed output. A red case that records only "failed" costs a full re-run to diagnose.

**H5. Isolated workspace, reset per run.** The evaluator's state is not reachable by the
system under test.

**H6. Outcome, not path.** Assert what the system produced, not how it got there. Path
assertions are permitted only for `should_trigger` cases, where the path *is* the thing
under test.

**H7. Multi-trial is mandatory for agent-driven cases** — trigger cases above all. Two to
six trials, reported as pass^k. Deterministic script-in / script-out harnesses are exempt.

**H8. Every new system declares three sentences before it ships:** which rung of the
determinism ladder its primary check sits on; where its cases come from; and what stops when
the score drops. Harnesses are built **per system**, not once globally.

**H9. RED-FIRST for any gate change.** A new fixture must be demonstrated red against the
*unmodified* script. A `verify:` block that was already green before the task started proves
the pre-existing state, not the change.

**H10. `set -euo pipefail` at the top of every multi-line verification block.** Without it
there is no `set -e`, the block's exit status is the last command's, and a failing first line
is masked — which is precisely the shape that hides a real defect.

**H11. A gate's own self-test must not depend on the corpus state the gate exists to
change.** Build it from fixtures. A self-test using two live skills as known-good and
known-bad goes red the moment the gate does its job.

**H12. When a gate excludes data a sibling work package is still moving, pin the skill, not
the path spelling.** A literal path exclusion goes red when a sibling performs a legal
`git mv`.

**H13. Parallel fan-out workers share one scratchpad directory.** Mandate a per-task
subdirectory in every fan-out brief. Measured: two workers wrote `scratchpad/convert.py`;
one executed the other's, which ignored argv and ran against its own hardcoded targets.

**H14. A contract written by one agent and executed by seven is a measurement instrument, and
it will be wrong on first draft.** Five defects in one such contract were all found by
workers during execution and none by review. Ship the self-check command inline; expect to
broadcast corrections mid-flight; treat mid-flight correction as part of the protocol rather
than as a failure of it.

---

## 3. The goalforge change set

Ordered. Each item is scoped to one commit and carries its own verification. Items are
labeled **DEFECT** (something is wrong now) or **UNFINISHED** (something was never
completed). Unblocking relationships are stated explicitly.

All measurements below were taken on 2026-09-01 by reading and executing the live tree at
`/home/cunger/10_projects/cogwright/packages/goalforge`.

### Item 0 — Decouple wp-03's goal verification from the goalforge tree — DEFECT, BLOCKS 1-19

`plans/cross-repo-release-gates/wp-03-cogwright-pin-and-ci-gate/overview.md:17` ends its
`goal.verification.check` with `&& bash "$CW/scripts/ci-lints.sh"`. That script is 9/9 green
today (`author-paths 137 · manifest 109 · package-refs 83 · version 3 · privacy-marker 18 ·
retired-vocab 250 · prose-eval-ratchet 183 · relation-claims 259 · interview-contract 7`),
but three of its sections — `package-refs`, `author-paths`, `retired-vocab` — scan
`packages/goalforge/**`, which wp-03 declares off-limits and which every item below
legitimately edits. A sibling's legal commit turns wp-03's *goal verification* red for
reasons unrelated to wp-03.

**Change:** narrow the conjunct to the sections wp-03 can affect (`manifest`,
`retired-vocab`), or drop it from `goal.verification.check` entirely and rely on the CI step
where `ci-lints.sh` already runs.

**Verify:** edit a comment in `packages/goalforge/SKILL.md`; the narrowed conjunct stays
green while the full `ci-lints.sh` may legitimately change section counts.

**Unblocks:** every item from 1 onward. Until this lands, each commit below must re-run
`ci-lints.sh` and hold 9/9, which couples unrelated work.

### Item 1 — Fix the family's only red eval — DEFECT

`verify/evals/run.sh` exits 1: *Results: 38 passed, 1 failed*, on
`wp-02: implement declares it never advances task status`. Line 12 sets
`IMPLEMENT_MD="$SKILL_DIR/../../implement/SKILL.md"`, and `SKILL_DIR` resolves through
`cd "$(dirname "$0")/.."` to `packages/goalforge/verify`, so the target is
`packages/implement/SKILL.md`, which does not exist. The string it greps for exists exactly
once on this machine, in `~/.claude/skills/implement/SKILL.md` — the install tree the package
was extracted out of. Because `$SKILL_DIR` resolves the dotfiles symlink back into cogwright,
the check cannot resolve from either side. It is a violation of S22 that broke silently on
the move and has been reporting a red skill since.

**Change:** delete the check. `implement` is not a goalforge package member. If the contract
sentence matters, relocate it into `execute/SKILL.md` and grep that file.

**Verify:** `bash verify/evals/run.sh` exits 0 with 38 passed, 0 failed; and the deleted
check is confirmed red against the unmodified script first (H9).

### Item 2 — Replace the unfalsifiable isolation check — DEFECT

`evals/retrospective/run.sh:96-97` asserts
`[ ! -e "$HERE/../../../../plans/goalforge/wp-15-retrospective-stage/improvement-report.md" ]`.
`plans/goalforge/` was archived to `plans/_archived/goalforge/`; neither the file nor its
parent exists. The assertion is permanently true whether or not isolation held, and stays
true if the run leaks a report anywhere else. This is E2 exactly.

**Change:** snapshot `git -C <plans-root> status --porcelain` before and after the run and
require it unchanged. This works: `cogwright/plans/` is its own nested git repository with
881 tracked files and a clean working tree (see §4 for why the "plans has no history" claim
should not propagate).

**Verify:** demonstrate the new check red by making the run write a file into the plans root,
then green with the write removed.

### Item 3 — Remove the machine-local path from the archive harness — DEFECT

`archive/evals/run.sh:126` sets
`SCRIPT="$HOME/.claude/skills/goalforge/scripts/goalforge-archive.sh"` and guards the entire
behavioral block with `if [ -x "$SCRIPT" ] || [ -f "$SCRIPT" ]` and **no else branch**. On any
machine without that symlink, seven real behavioral assertions silently vanish and the
harness still reports green. Same self-containment class as item 1, with the worse failure
mode: silent skip rather than loud red.

**Change:** point at `$SKILL_DIR/../scripts/goalforge-archive.sh`, and make absence a FAIL
rather than a skip.

**Verify:** `env -u HOME bash archive/evals/run.sh` still runs the seven behavioral
assertions; deleting the script makes the harness exit 1 rather than exit 0.

### Item 4 — Repair the PUBLIC front door's own metadata — DEFECT

Three problems in one file, `packages/goalforge/SKILL.md`:
- It is the **only** SKILL.md of the 19 in the package with **no `## Gotchas` section**
  (S17), and it is the one file a model reads before choosing a child.
- Line 32 declares *"This is a **v2 package**"* while `metadata.version` is `3.0.0`.
- `metadata.skill-kind` is present on all 16 private children and **absent** on the three
  discoverable skills — `goalforge`, `prototype`, `wayfind` — which is exactly inverted from
  where the field carries information (S4).

**Change:** add `## Gotchas` sourced from the package's own findings (the three-way route
vocabulary, the unreachable orchestrator, the nested-child Skill-tool failure); correct the
v2 sentence; add `skill-kind` to the three discoverable skills.

**Verify:** `grep -c '^## Gotchas' SKILL.md` returns 1; no occurrence of "v2 package";
`skill-kind` present in all three top-level frontmatters.

### Item 5 — Make the command layer single-source — DEFECT

All five commands (`spec`, `plan`, `implement`, `verify`, `wayfind`) exist as separate,
hand-edited files in both `packages/goalforge/commands/` and `dotfiles/claude/commands/`, and
**all five differ** (verified by `diff -q` on 2026-09-01). The package copies use
`${CLAUDE_PLUGIN_ROOT}`; the dotfiles copies use `~/.claude/skills/goalforge/`. The dotfiles
copies still say "SDD chain" and "SDD pipeline". `dotfiles/commands/implement.md` instructs
advancing a field named `stage:`, which does not exist — the schema uses `status:`.
`dotfiles/commands/verify.md` says the stage "runs the WP's eval harness" where the package
copy says "runs the WP's verification". Both `wayfind.md` copies carry headers naming a
*different* file as authoritative. This is S47.

**Change:** declare the package copies authoritative; replace the dotfiles copies with
symlinks or a generated artifact carrying a generation marker; fix `stage:` to `status:`;
remove the contradicting header.

**Verify:** for each of the five, `readlink -f dotfiles/claude/commands/<x>.md` resolves into
the package; `grep -rn 'stage:' commands/` returns nothing; exactly one authoritative-header
sentence exists across both trees.

### Item 6 — Collapse the route vocabulary to one enum — DEFECT, BLOCKS 7

Three route vocabularies coexist. `goalforge-route.sh` — the classifier that actually emits
the value — produces `fast | standard | wave`. `run/chain.yaml`'s prose and
`commands/spec.md` say `full`. `run/SKILL.md` declares the enum as `one-go | fast | standard
| wave`. `chain.yaml`'s own step guards use `when_route: standard`. Neither `full` nor
`one-go` is ever emitted by anything.

**Change:** adopt `fast | standard | wave` — the classifier's output — everywhere. Delete
`full` and `one-go`.

**Verify:** `grep -rn 'one-go\|route.*full' run/ commands/` returns nothing; the classifier's
`--self-test` stays green; `run/evals/run.sh` asserts the enum matches
`goalforge-route.sh`'s emitted set rather than a hardcoded list.

**Unblocks:** item 7, which cannot state a coherent orchestrator contract while three enums
are live.

### Item 7 — Resolve `goalforge-run`: reachable or unnamed — DEFECT

`goalforge/run` is named as the end-to-end alternative in all five commands **and** in the
parent `SKILL.md`, and it is unreachable: a private nested child with no `commands/` wrapper
and no discovery entry. The only way in is reading `run/SKILL.md` by hand. This is a
description that promises a path the runtime does not have — the S46 failure.

**Change:** decide one of two, and only one. Either pin it PUBLIC-PINNED with
`commands/goalforge-run.md` loading `run/SKILL.md` by path (S28), or delete every reference
that presents it as an available route.

**Verify:** if pinned, the wrapper resolves and `run/scripts/goalforge-router.sh --dry-run`
resolves all seven chain steps. If deleted, `grep -rn 'goalforge/run\|goalforge-run'
commands/ SKILL.md` returns only historical notes explicitly marked as such.

### Item 8 — Wire the shared trigger runner — DEFECT, BLOCKS 9

> **AMENDED 2026-09-02 by human ruling.** This item said *build one runner, at
> package root*. It now says **consume, do not build**. The engine is shared
> tooling owned by the dotfiles corpus at `scripts/skill-trigger-runner/`
> (knowledge home: its `README.md` there, the single normative statement of the
> case shape, the oracle, and the pass^k contract). This package contributes a
> caller, not an engine. Full survey, home selection, and extraction plan:
> [`shared-trigger-runner-design.md`](shared-trigger-runner-design.md).
> §4.12 is amended in the same lap to record the override.
>
> **Why the original was wrong.** The runner's natural input is the whole
> installed corpus; four of the five existing static pieces and the only working
> prompt driver already live in dotfiles; and a dotfiles-side caller reaching
> *into* cogwright is the machine-local dependency self-containment forbids. A
> package-root runner would also invert the ratio — cogwright owning a tool whose
> cases are 13 of ~370.

**Change:** ship `packages/goalforge/evals/trigger-run.sh` — resolve the shared
runner (`$SKILL_TRIGGER_RUNNER`, then
`${CLAUDE_CONFIG_DIR:-$HOME/.claude}/scripts/skill-trigger-run.sh`), point it at
this package by a relative climb, pass its exit code through, and on absence
print one `gap:` marker and exit 0 with `coverage: skipped` in the report — a
skipped run is measured, never read as a pass. No author path anywhere. Nothing
here ships: `scripts/goalforge-generate.sh` excludes every `evals/` directory
from `plugins/goalforge/`, so this is dev-time-only tooling.

**Verify** (run from the repo root; each line is executable as written):

```sh
bash packages/goalforge/evals/trigger-run.sh --dry-run
# → files_found 13, files_canonical 0, coverage "skipped", 13 shape errors, exit 2.
#   The honest zero: this is the RED baseline item 9 then moves, not a broken tool.

SKILL_TRIGGER_RUNNER=/nonexistent bash packages/goalforge/evals/trigger-run.sh --dry-run
# → exactly one line on stderr beginning `gap: `, exit 0.

bash scripts/ci-lints.sh
# → 9 `section <name>: PASS` lines, exit 0 (author-paths included).
```

**Unblocks:** item 9. Do not author cases before the caller resolves a runner.

<details>
<summary>Superseded text (kept for the record)</summary>

### Item 8 — Build the trigger runner — DEFECT, BLOCKS 9

This is the keystone item. **Zero canonical trigger cases exist across all 19 skills**:
`grep -rn "should_trigger" --include=*.json` over the whole package exits 1 with no hits.
Thirteen `evals.json` files carry 75 narrative cases with `prompt` and `expected_output`,
including explicit negative triggers written in prose ("should NOT trigger"). **Nothing in
the package or in `cogwright/scripts` reads any of them.** The only repository-wide reference
to `evals.json` is `scripts/install.sh:394`, which writes an empty `{}` scaffold. Every
`expectations[]` entry is phrased "SKILL.md declares / states / describes …", so the
assertions are documentation greps by construction, and the harnesses that would check them
re-implement the same greps in bash.

A case corpus that nothing executes is worse than none: it reads as coverage and provides
zero signal, and every case added to it deepens the illusion (E4).

**Change:** build one runner, at package root, that reads every `evals.json` in the package,
validates the canonical shape (T1, using the T2 jq expression), drives the case prompts
against the real skill-selection surface, and reports pass^k per skill with positive and
negative rates separately. Multi-trial per H7. Deterministic where it can be; the routing
decision itself is the nondeterministic part and is what the trials are for.

**Verify:** the runner reports a nonzero case count for every `evals.json` in the package
(no silent `0 0`); a deliberately mis-shaped fixture file produces a *shape* error naming the
file, not a `0 0` count; a sabotaged skill body scores measurably worse than the intact one.
That last assertion is the whole point — it is the sabotage test the corpus currently fails.

**Unblocks:** item 9. Do not author cases before the runner exists.

</details>

### Item 9 — Convert and author the trigger cases — DEFECT

> **RE-SCOPED 2026-09-02 by human ruling, on reachability.** Skill discovery
> walks **one level deep**, so 16 of this package's 19 skills are not in the
> model's selection surface at all — verifiable in any session's own skill
> listing, which carries `goalforge` and `goalforge-run` and no
> `goalforge-<child>`. Positive *selection* cases for a private child can never
> pass. Authoring all 19 as selection cases produces 16 permanent zeros that read
> as a broken runner; the split below is not a refinement, without it the metric
> is a lie.
>
> **SELECTION cases — now, and the only gated half.** Six reachable entries: the
> `goalforge` front door, the `/spec`, `/plan`, `/implement`, `/verify` commands,
> and `goalforge-run` if item 7 pins it. Oracle: the first `Skill` `tool_use`,
> string-equal to the skill under test. 3 positives / 3 negatives each.
>
> **ROUTING cases — DEFERRED behind `--observe all`.** Seeding the parent and
> asserting the routed child name is a different oracle on a different surface,
> and it contradicts the default early exit: the parent's call is observed first,
> so a first-call oracle can never see the child. The runner ships `--observe
> all` (collect every `Skill` call until turn end) and exercises it against
> replay fixtures, but **no routing oracle ships in this lap** — under `--observe
> all` the oracle still reads the first call and the full list is reported in
> `all_observed` for diagnosis only. Routing cases are authored once that oracle
> exists, in a separate report column, and are not counted toward this item.
>
> The conversion half below is unchanged and still applies to all 13 files.

Thirteen `evals.json` files convert to the canonical `should_trigger` shape (T13: rename, not
rewrite — `prompt` and `expected_output` byte-identical, re-running produces zero diff).
`onboard` is on the deprecated `trigger-*` id format (3 of its 5 case ids). Six skills ship
no `evals.json` at all: `brief` and `interview` have no `evals/` directory; `plan-index`,
`prototype`, `redecompose` have a `run.sh` and no cases; `wayfind` has `e2e.sh` and no cases.

Then author to the bar: at least 3 positives and at least 3 negatives per skill, with every
negative naming a sibling owner in backticks by its **declared** name (T5, T6, T7). This
package is the ideal case for T8 priority 1 — sixteen declared siblings under one router
means every negative can be a real boundary case. And T10 applies with full force: the
parent's description enumerates its children's trigger phrases verbatim, so the most
discriminating negative for `goalforge` is a prompt that is a verbatim substring of its own
trigger list.

**Change:** convert all 13 to the canonical shape (T13, rename not rewrite), then
author SELECTION cases to 3/3 for the **six reachable entries** named in the
re-scope above. The remaining 16 private children are ROUTING material, deferred;
their `evals.json` files still convert, but their cases are not authored as
selection cases and their pass^k is not gated in this lap.

**Verify:** the T2 jq one-liner prints two integers for all 13 converted files, both
at least 3 for each of the six reachable entries; every negative's `expected_output`
contains at least one backticked name resolving against the union of declared names
and basenames under `find -L`; `bash packages/goalforge/evals/trigger-run.sh --dry-run`
reports 13 canonical and 0 shape errors; the shared runner executes the six selection
suites and reports pass^k with positives and negatives tabulated separately, and an
`abstain` (no `Skill` call at all) counting as a failure for **both** polarities;
conversion re-run produces zero diff.

### Item 10 — Promote the five inert harnesses to execute something — DEFECT

**Corrected count, and this correction matters.** The adjudication reported nine
static-contract harnesses. Executing the package's own harnesses shows five: `arbiter`,
`spec`, `watchdog`, `verify`, and `run` contain no invocation of any script or interpreter.
The other four named — `capture`, `harden`, `archive`, `decompose` — already drive real
scripts against fixtures, as do `execute`, `recap`, `redecompose`, `plan-index`, `onboard`,
and `prototype`. See §4 for what this means for the adjudication's proposed fix.

Of the five, `run` is a middle case: it parses the real `chain.yaml` with grep and awk, which
is an artifact under test rather than prose. The pure-prose four are `arbiter`, `spec`,
`watchdog`, `verify`.

**Change, cheapest first:**
- `run`: invoke `run/scripts/goalforge-router.sh --dry-run <fixture-feature>` with
  `CLAUDE_SKILLS_ROOT` pointed at a fixture skills tree. The script already supports that
  environment override, so this is hermetic and is roughly a five-line addition. It converts
  the largest inert harness into a real resolution test of all seven chain steps.
- `verify`, `arbiter`, `spec`, `watchdog`: drive `goalforge-validate.sh`,
  `goalforge-frontier.sh`, and `goalforge-goal-eval.py` against fixtures asserting exit
  codes, following the pattern `harden/evals/run.sh:106-131` already establishes.

**Verify:** each harness's assertion count rises and each new assertion is demonstrated red
against a deliberately broken fixture before it is committed (H9).

### Item 11 — Wire or remove the three unregistered hooks — DEFECT

`packages/goalforge/hooks/hooks.json` registers four hooks through `${CLAUDE_PLUGIN_ROOT}`,
which only a plugin loader reads — and the goalforge plugin is **not installed** (absent from
`~/.claude/plugins/installed_plugins.json`). In the live dotfiles harness, all four are
symlinked into `~/.claude/hooks/`, and `dotfiles/claude/settings.json:358` registers exactly
**one** of them (`goalforge-single-writer.sh`). `goalforge-transition-guard.sh`,
`goalforge-open-questions-gate.sh`, and `goalforge-frontmatter-touch.sh` are on disk,
symlinked, and unwired — present enough to look like enforcement, absent enough to do
nothing. Three further stragglers sit in `~/.claude/hooks/` with no package counterpart:
`goalforge-cache-post.sh`, `goalforge-cache-pre.sh`, `goalforge-checkpoint.sh` (dated
2026-07-12 and 2026-07-18).

This is the S38 residue test failing in both directions: authority declared but not granted,
and authority granted but no longer owned by any component.

**Change:** register the three intended hooks in `settings.json`, or delete the symlinks and
say in the package that they are plugin-mode only. Delete the three stragglers.

**Verify:** every symlink under `~/.claude/hooks/goalforge-*` corresponds to a registration in
`settings.json` **and** to a file in the package; the count of goalforge hooks on disk equals
the count registered.

### Item 12 — Hook regression tests for the four untested hooks — UNFINISHED

Tests exist for 2 of 6 package hooks (`goalforge-pre-commit.test.sh`,
`goalforge-single-writer.test.sh`). Missing: `goalforge-transition-guard.sh`,
`goalforge-open-questions-gate.sh`, `goalforge-frontmatter-touch.sh`,
`goalforge-plans-root.sh`. A hook without a block-case and an allow-case test is an
unverified claim about a blocking surface.

**Change:** one test file per hook, each asserting both a blocked case (exit 2) and an
allowed case (exit 0).

**Verify:** `hooks/tests/` holds six files; each is demonstrated red against a hook mutation
before commit.

**Depends on** item 11: test the hooks that are actually wired.

### Item 13 — Enforce the presence rules that are currently WARN — PROMOTION

Per §0.3, prefer promotion over new prose. Add a `ci-lints.sh` section, scoped to
`packages/goalforge/**`, asserting per SKILL.md: a `## Gotchas` section with at least one
list item (S17); a SKIP or when-NOT boundary marker (S16); and `metadata.skill-kind` present
(S4). Today 18 of 19 carry gotchas, 14 of 19 carry a boundary marker (missing on
`plan-index`, `prototype`, `recap`, `redecompose`, `watchdog`), and `skill-kind` is inverted
per item 4.

**Change:** the lint section, plus the five missing boundary markers.

**Verify:** the section is red on the tree as it stands *before* items 4 and this one land,
and green after (H9). Fixture-based self-test per H11 — do not use live skills as
known-good and known-bad.

**Depends on** items 0 and 4.

### Item 14 — Enforce the trigger bar — PROMOTION

Add a `ci-lints.sh` section asserting the canonical shape and the 3/3 bar across the package,
using the T2 expression. Gate on shape first with a distinct error message, so a wrong-shaped
file never reports `0 0` (S41).

**Verify:** red against a fixture with a top-level array (shape error, not a count of zero);
red against a fixture with 2 positives; green on the converted corpus.

**Depends on** item 9. Do not enable the gate before the corpus can pass it.

### Item 15 — Delete the checked-in build residue — DEFECT

`.pytest_cache/`, `scripts/__pycache__/` (including malformed names such as
`goalforge-trace-emitcpython-311.pyc` and `goalforge-trace-readcpython-{311,313,314}.pyc`),
`scripts/tests/__pycache__/`, and `workflow-authoring/scripts/__pycache__/` are tracked in
the package tree.

**Change:** `git rm -r --cached` the four trees, extend `.gitignore`.

**Verify:** `git status --porcelain` clean after a full test run; `git ls-files | grep -c
'__pycache__\|pytest_cache'` returns 0.

### Item 16 — Give the six extensionless Python scripts their extension — UNFINISHED

`goalforge-issue`, `goalforge-retrospect`, `goalforge-trace-emit`, `goalforge-trace-read`,
`goalforge-trace-derive`, and `goalforge-plan-index-json` carry no extension while
`goalforge-plan-index.py` and `goalforge-pick-agent.py` do — so the convention already exists
in-tree and is applied inconsistently. This recurred twice and a documentation-only fix
(`45f7732`) failed to hold.

**Change:** six `git mv` plus a caller grep, in one commit.

**Verify:** `ci-lints.sh` re-run in the same commit (the `package-refs` section scans these
paths); every caller resolves; the recurring idea is closed rather than re-recorded.

**Depends on** item 0 if wp-03's conjunct has not yet been narrowed.

### Item 17 — Add `--self-test` to the six scripts that lack it — UNFINISHED

Present on roughly 14 scripts; absent on `goalforge-rollup.sh`, `goalforge-feature-hash.sh`,
`goalforge-hygiene.sh`, `goalforge-stamp-tables.sh`, `goalforge-status.sh`, and
`goalforge-ensure-committed.sh`. The convention is what lets a harness assert behavior in one
line, and it is the cheapest available conversion of a prose assertion into an executed one.

**Verify:** each new `--self-test` is red against a deliberately broken internal fixture
before commit.

### Item 18 — Converge the CLI argument conventions — UNFINISHED

Five ways to name a scope exist across the script surface: positional feature path
(`goalforge-frontier.sh`), `--feature <slug>` plus a positional plans root
(`goalforge-validate.sh`), positional feature directory (`goalforge-hygiene.sh`), positional
slug plus `--plans-root` (`goalforge-archive.sh`), and both forms in one script
(`goalforge-status.sh`). Three ways to name the plans root: `--plans-root`, a trailing
positional, and `--all <plans-root>`. Four dry-run spellings: `--show`/`--apply`, `--check`,
`--dry-run`, `--detect-only`. Separately, `goalforge-validate.sh` accepts `--feature <slug>`
at line 61, which is **undocumented in its own usage header** and is the flag two other
scripts depend on (`goalforge-hygiene.sh:85,88` and `goalforge-archive.sh:238`).

This is a real cost — `harden/evals/run.sh` calls two scripts with two different scope
conventions in one harness — but it is a broad, low-urgency refactor. Do the cheap half now:
document `--feature` in `goalforge-validate.sh`'s usage header. Defer the convergence until a
work package owns it.

**Verify:** `goalforge-validate.sh --help` lists every flag the script accepts.

### Item 19 — Fix the wp-03 fixture rule disagreement — DEFECT, low urgency

`wp-03/task-01`'s `$d/ifuses` fixture asserts exit 0 for an `if:` on a `uses:` step, matching
the contract at `spec.md:493` which refuses `if:` only on a step carrying `run:`.
`wp-03/task-05`'s verify asserts no step carries `if:` **at all**. Both are green today
because the workflow has no `if:` anywhere — but the first legitimate `if: matrix…` on
`actions/checkout` passes one and fails the other.

**Change:** `if 'if' in s and s.get('run')` in task-05's verify.

**Verify:** a fixture with `if:` on a `uses:` step passes both; a fixture with `if:` on a
`run:` step fails both.

---

## 4. What we are deliberately NOT doing

This section exists so the next lap does not re-propose these. Each entry states why.

**4.1 We are not "fixing" the capture and harden harnesses to execute a script.** The
adjudication's H4 proposed replacing string-greps with executions in `harden/evals/run.sh`
and `capture/evals/run.sh`, calling it a one-line change each. **Both already execute.**
`harden/evals/run.sh:106-131` runs `goalforge-validate.sh` against an `incomplete-goal`
fixture asserting non-zero exit, and runs `goalforge-frontier.sh --self-test`.
`capture/evals/run.sh:126` runs `goalforge-route.sh --self-test`. The adjudication's count of
nine static-contract harnesses is wrong; the correct count is five, and `archive`,
`decompose`, and `execute` — also on its list — each drive real scripts against fixtures.
Item 10 carries the corrected scope. *This is exactly the S34 failure the corpus keeps
reproducing: the document's claim about the tree was checked and did not hold.*

**4.2 We are not acting on "`plans/` is entirely gitignored, none of this work has version
history".** False. `cogwright/plans/` is gitignored **by the outer repository** because it is
**its own nested git repository**: `/home/cunger/10_projects/cogwright/plans/.git`, 881
tracked files, clean working tree, history through 2026-08-31. Every plan file is
recoverable and "what changed when" is answerable with `git log`. Verifying plans against
code remains correct; the stated reason for doing so was wrong, and the "no history" framing
must not propagate into a handoff. Item 2's fix depends on this being true.

**4.3 We are not investigating "`~/.claude/plans/goalforge-viz` claims verified WPs whose
code does not exist".** False. `dotfiles/claude/tools/goalforge-viz` holds 305 tracked files
— `app/`, `bin/`, `mcp/`, and six `panels/` matching the WPs in question — across five named
commits. There is no second false-record instance.

**4.4 We are not making the 16 private children discoverable, and we are not giving them
commands.** Discovery walks one level (S27); nesting is the privacy mechanism. Sixteen
model-invoked descriptions would be paid on every turn to save a path lookup on the rare turn
that needs one — the S14 anti-bloat law in its clearest form. The single exception under
consideration is `goalforge-run` (item 7), because the package's own documentation currently
promises it as a route.

**4.5 We are not renaming the children to match their directory basenames.** Sixteen of
nineteen declare `goalforge-<dir>` for a `<dir>` directory, which is correct: the declared
name must be unique in a flat namespace while the path stays readable (S11). Renaming would
break `chain.yaml`'s step resolution and every cross-reference. The real defect is upstream —
the corpus trigger gate excludes self-citation by *basename* while matching owners by
*declared name*, so a nested skill can satisfy the named-owner rule by citing itself. Fix the
gate, not the names. Note that widening that gate's owner harvest without also fixing the
self-exclusion strictly **weakens** it; the two changes must ship in one commit.

**4.6 We are not unifying `wayfind/scripts/` with `goalforge-*` scripts.** `wayfind` carries
its own `wayfind-frontier.sh`, `wayfind-status.sh`, and three validators — a parallel
implementation of frontier and validation. They operate on a different object (decision
tickets, not work packages) with a different graph shape. That is a seam, not duplication.
Abstract on the second concrete need; this is the first.

**4.7 We are not giving `goalforge-router.sh` a non-dry-run mode.** Its header states the
design deliberately: the agent-driven router stays the runtime mechanism, and this script is
the deterministic binary gate a `goal.verification` can call. The two are complementary. Item
10 uses it exactly as designed.

**4.8 We are not adding a per-skill telemetry hook.** Measurement is global — three streams
(`data/skill-usage/usage.jsonl`, `data/skill-learning/ledger.jsonl`,
`data/skill-learning/events.jsonl`), with usage capture already hard-wired at
`settings.json:205` and `:286`. A per-skill telemetry hook is a defect, not a feature.

**4.9 We are not adding per-skill changelog files.** Git history is the change trace. The
change trace is a version bump plus an eval delta plus the commit, in one atomic commit, with
the eval delta stated in the commit message.

**4.10 We are not adopting the "unrelated topic" negative shape**, even though two resident
corpus documents still name it as one of three valid negative shapes. The named-owner
standard (T5) is the later, measured, user-approved position and it supersedes them. **The
corpus rules need updating and until they are, a new author reading only the resident rule
will write inadmissible negatives.** That is a live conflict, and closing it is a corpus-level
change outside this package's scope — recorded here so it is not silently re-opened.

**4.11 We are not auto-retiring any skill.** Ablation produces a candidate; a human decides
(S5). Nothing in this change set retires anything, and the `interview` and `brief` children —
which ship no evals — are candidates for *cases*, not for deletion.

**4.12 We are not building a general skill-system harness owner — AMENDED
2026-09-02 (human ruling; override recorded).** The original text read: *"The
ownership table records honestly that a skill system (router plus children) has no
harness owner in the general case. Item 8 builds one runner for this package, per
H8's per-system rule. A corpus-general runner is a separate decision with a
separate cost."*

That separate decision has now been taken, and the cost has been **measured, not
argued**: `shared-trigger-runner-design.md` §4 records three live `claude -p`
probes on 2026-09-02 — ~$0.0026 per trial with a kill-on-first-`Skill` early exit
against ~$0.086-0.108 for a full run, a ~35× cliff — putting the
reachability-scoped goalforge suite (6 surfaces × 6 cases × k=3) at ~$0.30 and
~2 minutes. The ruling: **one shared engine, home in dotfiles at
`scripts/skill-trigger-runner/`, two case corpora.** Cogwright consumes it
through `packages/goalforge/evals/trigger-run.sh` (item 8) and owns none of it.

This clause therefore no longer forbids the work item 8 now describes. What it
still forbids is unchanged and load-bearing: **cogwright does not become the
owner** of a corpus-general harness. H8's per-system rule is satisfied by the
per-system *caller*, not by a second engine. Anyone reading §4 to refute item 8
should read this paragraph first — the veto was lifted deliberately, on measured
cost, and not by omission.

**4.13 We are not deleting the 75 narrative eval cases.** The choice is wire them or delete
them, and item 9 wires them — they carry real authored intent including explicit negatives.
Deleting them would discard the only case material the package has.

**4.14 We are not resolving the `interview` dependency or the two unshipped recommendations.**
`relations.yaml` hard-requires `interview ^1.0.0` with a documented degrade, and recommends
`research-analyst` and `adr-write`, both flagged in `wayfind/SKILL.md:401-403` as not shipped
with the plugin. The degrade path is documented and working. This becomes a real question at
plugin-install time, not now.

**4.15 We are not touching the goalforge extraction, `cross-repo-release-gates` beyond item
0, or the `goalforge-improvement` ticket loop.** Those are separate lanes with their own
sequencing constraints — in particular, a stop-rule ticket that bounds every subsequent lap
and an irreversible baseline-measurement ticket that must be taken before anything rewires a
gate. This change set is deliberately independent of them; item 0 exists precisely to keep it
that way.

---

## 5. Provenance

Everything asserted about the live tree was read or executed on 2026-09-01 against
`/home/cunger/10_projects/cogwright/packages/goalforge`, `/home/cunger/dotfiles/claude`, and
`/home/cunger/.claude`. Specifically:

- The 19 SKILL.md inventory, gotcha and boundary-marker presence, eval file presence, and
  every `run.sh` exit code come from executing each harness.
- The zero-trigger-case finding comes from
  `grep -rn "should_trigger" --include=*.json` over the package, which exits 1.
- The five inert harnesses come from grepping each `run.sh` for `python3` and `bash "$`,
  then reading the hits — which is how the adjudication's count of nine was corrected to
  five.
- The command divergence comes from `diff -q` on all five pairs.
- The hook wiring comes from `ls -la ~/.claude/hooks/` and
  `grep -n goalforge dotfiles/claude/settings.json`.
- `run/scripts/goalforge-router.sh`'s `CLAUDE_SKILLS_ROOT` override is read from its own
  source at lines 20-23.

Doctrine that is not re-derivable from this tree — the sabotage measurement of 2026-08-12,
the 75.8% self-report figure, the Berkeley harness-attack result, the counting-floor and
backtick findings, the foreign-provider review's zero findings against priority-1 negatives —
is stated inline with its measured content rather than by reference, so this document remains
usable with every external source unavailable. Where a finding originated in a work package's
findings file, the finding is reproduced here in full rather than pointed at, because those
files are disposable by design.

One caveat worth carrying forward: one work package's `findings.md` is internally stale,
carrying an "Open — task-09 not complete" header directly above a completed task-09 section.
Anyone quoting it must read past the header.
