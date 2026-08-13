# Should goalforge move to its own repo? — extraction assessment (2026-08-13)

**Question:** move `goalforge` out of `cogwright` into its own public repo,
leaving cogwright a pure distributor (a marketplace hub pinning other repos'
plugins, containing no plugin source of its own).

**Precedent:** `interview` already works this way — authored in `elicitforge`,
pinned by `git-subdir` in `.claude-plugin/marketplace.json:12-18`. The model is
recorded in `~/.claude/plans/base-system-map/wayfind/findings/ticket-06.md` as
"own-repo, cogwright = connection hub via relations.yaml".

**Status:** assessment only. The decision belongs in a `base-system-map/wayfind`
ticket alongside ticket-06, not in a work package.

---

## A. What extraction would cost

**7 of 9 lint sections move as a block. 2 split. 0 stay.**

| Section | Verdict | Why |
|---|---|---|
| `manifest`, `package-refs`, `privacy-marker`, `retired-vocab`, `prose-eval-ratchet`, `interview-contract` | **move** | every path they read is a goalforge tree |
| `author-paths` | **split** | bans `$COGWRIGHT_ROOT` and the `Truncuso/cogwright` slug — half is distributor-generic |
| `version` | **split** | three-way check binds the package SKILL.md ↔ plugin.json ↔ **cogwright's** README catalog row |
| `relation-claims` | **split** | scans *every* tracked `.md` repo-wide; after extraction neither repo's copy covers the other |

**8 of 10 CI steps move.** Only `checkout` and the marketplace/manifest
validator are distributor-generic — and that validator already handles
`git-subdir` sources.

Everything else moves whole: `packages/goalforge/` (326 files),
`goalforge-generate.sh`, `goalforge_refs.py`, all six lint baselines,
`install.sh` (except its consumer-mode half, which splits back),
`interview-contract-sync.sh`, and the `~/.claude/skills/goalforge` symlink
(one `ln -s` retarget; `install.sh` derives its repo from its own location).

**Two dead scripts surfaced in passing:** `discovery-probe.sh` has no invoker
anywhere — not `.github/`, not `scripts/`, not the docs. Dead as shipped.

### 2026-08-07 audit remediation — mostly landed

101 path leaks → `author-paths` PASS (3 residual, all carved out and
self-referential). 4 missing entry commands → shipped. Undeclared deps →
`INSTALL.md:17-78` + doctor arm 1. `plugin.json` version was a SHA → now
`3.0.0`. All 9 sections PASS today. Still open: `evals/` not shipped;
child-privacy suppression still soft.

---

## B. The precedent inherits the wrong way

An extracted goalforge shaped like elicitforge would inherit elicitforge's gaps:

1. **No CI at all** — no `.github/` directory exists there.
2. **No release automation** — `scripts/` holds only the publish gate.
3. **No INSTALL/CONTRIBUTING/SECURITY**; README is 24 lines.
4. **Asymmetric tags** — only `interview--v1.1.0` exists; `v1.0.0`–`v1.0.3`
   have no twin, so goalforge's `^1.0.0` range resolves over a one-element set.

**Goalforge today has strictly more assurance than elicitforge** — 10 CI steps,
9 lint sections, hook self-tests, a state-machine smoke, a doctor self-test.
Extraction must carry that CI with it and **back-fill elicitforge**, not copy
elicitforge's shape.

What elicitforge does have worth copying: the `core/` vs `adapters/` split with
a **purity fitness function** (a base64-encoded denylist, encoded so the
denylist is not itself the only occurrence, failing if the scan matched zero
files), and a publish gate with per-finding exemptions pinned to a
`blob:`/`commit:` where an unmatched exemption fails the gate.

---

## C. Relations and staleness

### The tag mechanism is real — implemented upstream, not here

Verified in the Claude Code CLI binary: constant `--v`, `refs/tags/` parsing
with `^{}` peeled-tag preference, semver `maxSatisfying` against the declared
range, and the failure strings `"Installing plugin dependencies: "`,
`" has no tag satisfying "`, `"not found in any known marketplace; not
auto-installing"`, `"Dependency cycle: "`. The resolved `{ref, sha}` overrides
the marketplace pin.

So `relations.yaml:3-8`, `README.md:14`, `INSTALL.md:138-145` and
`ARCHITECTURE.md:74-80` describe a **working mechanism**. Resolution happens at
install time, on the consumer's machine.

**Cogwright's own contribution is one projection.** `goalforge-generate.sh:407-441`
parses only `requires:` → `name` + `version` into `plugin.json` `dependencies`.
Nothing reads `used-by:`, `degrade:`, `source:`, or `recommends:`. A repo-wide
grep for `provides-slot|fills-slot|emits-to|vendors:` returns nothing — **three
of the five relation kinds `README.md:146` advertises are inert vocabulary**,
and "the marketplace renders the resulting map" has no renderer.

### Staleness modes: 5 of 7 detected by nothing

| Mode | Detected by |
|---|---|
| Dependency releases outside the declared range | Claude Code at install time, on the **user's** machine — hard fail. Nothing in CI |
| Release ships with **no** `{name}--v` tag | **nothing** — tags are hand-made; resolution silently keeps returning the last tagged version |
| `used-by:` names a consumer that no longer exists | **nothing** |
| `degrade:` describes a removed fallback | **partial** — the interview row's degrade *string* is pinned; the two `recommends` degrades have no check |
| Marketplace pin drifts from the resolved tag | **nothing** — the validator never reads `ref`/`sha` |
| `recommends` naming a non-marketplace entity | **nothing** (already noted at `INSTALL.md:472-478`) |
| `ARCHITECTURE.md` "verbatim from relations.yaml" table drifting | **nothing** — the 2026-08-07 finding was fixed, its recommended CI diff never implemented |

**Effect of extraction on staleness: essentially neutral.** Every relations
check already reads only goalforge-side files, so all of it moves intact. One
regression (`relation-claims` stops spanning both repos' docs from one job); one
improvement (goalforge can carry a `goalforge--v*` tag and be depended on by
name, which it cannot today). Neither is large next to five modes detected by
nothing at all.

---

## D. Multi-harness readiness

**The file-level number is misleading; the line-level number is real.**

| Granularity | Count |
|---|---|
| `SKILL.md` files harness-bound | 19 / 19 |
| Harness-token **lines** in those files | **186 / 4744 — 3.9 %** |
| — `.claude/` path tokens (generator already rewrites these) | 146 |
| — `AskUserQuestion` | 20 |
| — `CLAUDE_SKILL_DIR` | 19 |
| Scripts harness-bound | 15 / 34 |
| `CLAUDE_PLUGIN_ROOT` files | 12 |

At 3.9 % of prose lines — dominated by path tokens the generator's rewrite
table already handles — **goalforge is not Claude-Code-shaped throughout**. The
genuinely harness-*semantic* surface is small and enumerable: 5 slash commands,
8 `PreToolUse` hooks, ~20 `AskUserQuestion` call sites across 10 files, and 12
`${CLAUDE_PLUGIN_ROOT}` root-climbs. `workflow-authoring/` is already fully
harness-free.

An elicitforge-style split is **feasible**; the generator's rewrite table is
most of the adapter already. What is missing is the purity *gate* — nothing
today stops a new harness token entering the would-be core.

### What the codex mirror teaches

`sync-codex-from-claude.sh:120` only **logs** "extra: exists in codex mirror but
not claude source" — there is no prune path, and every tracked mirror dir is
re-linked each run. Measured 2026-08-11: **157 mirror dirs vs 106 live skills**;
5 deleted skills still live-invocable under Codex; 10 stale content copies.
Visible in the listing: `sdd-arbiter`, `sdd-capture`, `sdd-decompose`,
`sdd-execute`, `sdd-harden`, `sdd-verify` — **the entire retired `sdd-*`
vocabulary that `ci-lints.sh --only retired-vocab` bans inside cogwright is
still live under Codex.**

The lesson: copy-based mirroring without a prune leg and a count-mismatch gate
produces a second, divergent, silently-invocable product. A multi-harness
installer needs deletion propagation and a per-harness drift gate, not just an
add path.

`install.sh` today assumes Claude Code exclusively — no harness parameter, no
Codex path. `~/.codex/skills` is populated by a *dotfiles* script that has never
heard of this installer.

---

## E. Recommendation: extract, but the evidence does not fully settle it

**Strongest case against (extract later, after the harness split):** the move
produces nothing a user can observe, costs a full re-verification of 9 lint
sections and 10 CI steps in a fresh repo, and spends goalforge's most valuable
asset — a CI job proven 9/9 green today — on a change that yields no
capability. Doing the harness split first would tell you what shape the repo
should be, so you extract **once** into the right layout instead of moving a
`packages/`+`plugins/`+generator structure and rewriting it into
`core/`+`adapters/` later.

**Case for extracting now:**

1. **The acceptance test already exists and is binary** — 7/9 sections and 8/10
   steps move unrewritten; success is `ci-lints.sh` 9/9 PASS plus a green
   workflow in the new repo. A deterministic oracle, available on day one.
2. **The harness split is not blocked by repo location** and is a many-lap
   refactor; every lap of it inside cogwright churns the distributor's history
   for changes belonging to one plugin.
3. **cogwright already carries exactly one asymmetry** — `interview` pinned,
   `goalforge` in-tree — and ticket-06 already decided own-repo for memory,
   dispatch and learning. Leaving goalforge in-tree means the hub permanently
   carries two CI contracts plus a `version` catalog check and a
   `relation-claims` ratchet that generalize to none of the three systems still
   to come.

**The unmeasured deciding variable:** whether an extracted goalforge keeps the
`packages/`→`plugins/` generator or converges on elicitforge's
`core/`+`adapters/` shape. If they converge, extract **once** into the
elicitforge shape and the "pure move" framing is wrong.

**The one measurement that settles it:** run elicitforge's purity denylist
against a candidate `core/` — `packages/goalforge/` minus `commands/`, `hooks/`
and `scripts/` — and classify the residue into (a) path tokens the generator
already rewrites versus (b) genuinely harness-semantic constructs. Prediction
from the line counts: **~146 in (a), ~40 in (b)**. If (b) lands under ~50 lines
the shapes converge and extraction should be a one-time elicitforge-shaped move.
If (b) is materially larger, the generator shape is load-bearing and extraction
is a pure move that can happen now.

---

## Independent of the decision

Both cheap, neither blocked by it:

- **Nothing creates or verifies `{name}--v<version>` tags on any release**, in
  either repo. The resolver is real and enforced upstream at install time —
  which means the first person to discover a missing tag is a user with a failed
  install.
- **`scripts/discovery-probe.sh` has no invoker** anywhere. Dead as shipped.

## Provenance

Assessed 2026-08-13 by a dispatched reviewer; the central claim (tag resolution
implemented in the Claude Code CLI) independently re-verified against the
installed binary before filing. Companion release/CI audit:
`2026-08-13-release-and-ci-audit.md`.
