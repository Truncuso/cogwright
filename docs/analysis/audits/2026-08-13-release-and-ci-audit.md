# Release & CI audit — the three-repo publish path (2026-08-13)

**Scope:** every CI workflow, git hook, gate and release step across `elicitforge`
(engine source), `cogwright` (distribution hub) and `dotfiles` (consumer).
**Method:** read-only inspection; every claim carries a file:line pointer. The
four headline claims were independently re-verified by the orchestrator before
this was filed.

**Trigger:** a live defect — six files in the `~/.claude` tree route to
`preset: brainstorm`, which does not exist in the installed plugin. Used
throughout as a worked probe.

---

## The one-sentence finding

**Every gate in this system is intra-repo.** Each proves a property of one tree
against itself; the publish path spans three repos, so defects that live in the
*seams* pass every gate that exists.

---

## Inventory

| Repo | CI workflows | Git hooks installed | Gates present |
|---|---|---|---|
| **elicitforge** (publishes publicly) | **none** — no `.github/` | **none** — `.git/hooks/` is samples only | `publish-gate.sh` (413 lines), core + adapter eval suites — **all hand-run** |
| **cogwright** | `validate-plugins.yml` (107 lines) | `pre-commit` only | `ci-lints.sh` (9 sections), generate `--check`, hook self-tests, smoke, doctor |
| **dotfiles** | **none** | `pre-commit`, `pre-push`, `commit-msg`, `post-commit` — all active | 29 hook regression tests, **none automated** |

`elicitforge/.claude/git-guardrails.yaml` configures blocked branches,
conventional commits, force-push blocking and a 100KB cap — but no hook in that
repo reads it. **The config is inert.**

---

## Two gates that report success without running

### 1. `claude plugin validate --strict` is green-by-construction

`.github/workflows/validate-plugins.yml:79-85`:

```yaml
if command -v claude >/dev/null 2>&1; then
  claude plugin validate --strict plugins/goalforge
else
  echo "::warning::claude CLI not found — skipped ..."
fi
```

`runs-on: ubuntu-latest` has no Claude install, so the `else` branch is taken on
**100 % of runs**.

This is the exact anti-pattern the repo refuses elsewhere and in writing.
`scripts/interview-contract-sync.sh:20-24` declines to enter CI precisely
because "a WARN-skip is taken on 100% of CI runs, making the check
green-by-construction". wp-13 spent a full review lap resolving that same
tension (D8-wp13) and chose to vendor a fixture rather than commit it. The
workflow commits it at line 84.

### 2. The marketplace pin is an unvalidated string

`validate-plugins.yml:49-55` — for any object (`git-subdir`) source:

```python
for key in ("source", "url", "path"):
    assert source.get(key), ...
continue
```

`ref` and `sha` are **not in the required-key list and are never
dereferenced**. The `continue` also skips the name-equality assertion at
lines 62-64. Nothing checks that `ref` names a real tag, that `sha` is that
tag's commit, or that the two agree.

---

## The publish path — 11 steps, 1 automated

| # | Step | Mode | Gate |
|---|---|---|---|
| 1 | Edit `core/` | manual | **ungated** |
| 2 | Hand-vendor into `adapters/claude-code/` | manual | **ungated at commit**; drift eval is hand-run |
| 3 | Bump adapter `plugin.json` version | manual | **ungated** |
| 4 | Run `publish-gate.sh` | manual | **ungated — no invoker exists** |
| 5 | Commit | manual | **ungated** — no hooks in elicitforge |
| 6 | Tag `v<x>` + `interview--v<x>` | manual | **ungated** |
| 7 | Push tags | manual | **ungated** |
| 8 | Bump `marketplace.json` `ref`/`sha` | manual | **ungated** (see above) |
| 9 | cogwright CI fires | **automated** | gated — but **entirely about goalforge**, nothing about interview |
| 10 | Host fetches `path` at `ref`/`sha` | automated | host trusts the pin |
| 11 | Install lands in the plugin cache | automated | **ungated** — nothing asserts `requires: interview ^1.0.0` is satisfied |

---

## Version coherence

| Source | Value |
|---|---|
| elicitforge adapter manifest @ HEAD | `1.1.0` |
| marketplace pin | `ref: v1.1.0`, `sha: 35f634f` |
| tag `v1.1.0` / `interview--v1.1.0` | both → `35f634f` ✓ |
| installed cache | `1.0.2`, `1.0.3`, `1.1.0` — **three coexisting** |
| goalforge plugin | `3.0.0`, **zero tags in cogwright** |

Mismatches worth acting on:

1. **HEAD ships a feature at an unbumped version.** `356c85a` adds three files
   and 53 engine lines with `plugin.json` still at `1.1.0`. Nothing correlates a
   `feat` commit with a version bump.
2. **The tag scheme is half-implemented.** `relations.yaml:4-5` documents
   install-time resolution from `{name}--v<version>` tags. Exactly **one** such
   tag exists. A `^1.0.0` resolver following that scheme can only ever resolve
   1.1.0 — the entire 1.0.x line is invisible to it.
3. **Mixed tag object types.** `v1.0.0/2/3` are lightweight; `v1.0.1`, `v1.1.0`,
   `interview--v1.1.0` are annotated. A resolver comparing `%(objectname)`
   naively gets the *tag object* sha for the annotated ones —
   `interview--v1.1.0` is `cede5ed`, not `35f634f`.
4. **goalforge v3.0.0 has no tag and no release** — it ships as whatever is on
   main, while the manifest and README assert a version.

---

## Gaps, ranked by what can reach a user

| # | Gap | Evidence | Owner |
|---|---|---|---|
| 1 | **No gate anywhere on the interview plugin's content** — cogwright never fetches the pinned subtree; elicitforge has no CI | `validate-plugins.yml:50-55`; no `.github/` in elicitforge | elicitforge |
| 2 | `ref`/`sha` unvalidated | `validate-plugins.yml:53-55` | cogwright |
| 3 | `publish-gate.sh` has no invoker — a leak scrub guarding a *public* repo, never run | 413 lines, no caller | elicitforge |
| 4 | `claude plugin validate --strict` green-by-construction | `validate-plugins.yml:80-84` | cogwright |
| 5 | No release job, no tag trigger | `validate-plugins.yml:3-5` | cogwright |
| 6 | `requires: interview ^1.0.0` enforced nowhere | `relations.yaml:11-16`; doctor probes 7 binaries, no dependency arm | cogwright |
| 7 | elicitforge has no git hooks while its guardrails config sits inert | `.git/hooks/` samples only | elicitforge |
| 8 | Core↔adapter vendoring enforced only by a hand-run eval | `vendored-presets-sync.sh` | elicitforge |
| 9 | 29 hook regression tests, zero automation — the *hard* enforcement layer, unwatched | `claude/hooks/tests/` | dotfiles |
| 10 | No leak scrub on cogwright at all | `author-paths` is a fixed path regex, not a leak detector | cogwright |

### What `ci-lints.sh` cannot see

All 9 sections are syntactic/structural ratchets over cogwright's own tree.
Uncovered classes: **every byte of the interview plugin**; the marketplace pin;
semantic defects in shipped prose; fresh paraphrases of the banned relation
claims (`ci-lints.sh:846-849` says so outright — "bans four specific literals,
NOT the claim class"); retired vocab in another spelling; **deletion** of eval
assertions (cap-only by design); secrets or personal data; and whether a version
number corresponds to anything published.

---

## The brainstorm probe — which gate should have caught it

None could, and the reasons are structural, not oversights:

- `preset-resolution.sh` resolves presets **within the source tree**, where
  `brainstorm.md` is present and resolves perfectly. No notion of "installed".
- `vendored-presets-sync.sh` is **green** — both sides gained the file in the
  same commit. It measures internal consistency of a tree that was never
  published.
- cogwright's `interview-contract` section is scoped by deliberate decision to
  repo-relative paths (`ci-lints.sh:906-912`) and pins an enum, not the preset
  roster.
- `interview-contract-sync.sh` is the only instrument crossing the
  repo/install boundary, but compares one enum, against cogwright's fixture, and
  is forbidden from CI by its own header.
- `validate-plugins.yml` never fetches the interview subtree at all.

**Where the missing gate belongs: dotfiles.** It is the only repo that both
knows which plugin capabilities its prose names *and* always runs on a machine
with a populated plugin cache — so the CI-runner obstacle that forced
`interview-contract-sync.sh` out of cogwright's CI does not apply. The shape:
scan `claude/**` for `preset: <x>` and command references, assert each resolves
under the installed `cogwright/interview/*/{presets,commands}/`, and wire it into
the already-active `pre-commit` hook.

**Secondary owner: elicitforge.** A release-discipline gate — a `feat` touching
`core/presets/` must bump the adapter version, and a tag must point at a tree
that passes `publish-gate.sh` and both eval suites. Without it the version
number carries no information: a consumer-side `^1.0.0` check would have been
satisfied by 1.1.0 anyway, because the version says nothing about whether
`brainstorm` exists. **Fixing the consumer check without fixing version
truthfulness yields a gate that can only ever check filenames, never
contracts.**

---

## Provenance

Audited 2026-08-13 by a dispatched reviewer; headline claims (green-by-
construction validate step, unvalidated `ref`/`sha`, absent elicitforge hooks,
uninvoked publish gate) independently re-verified before filing. Companion
assessment of the goalforge-extraction question is filed separately.
