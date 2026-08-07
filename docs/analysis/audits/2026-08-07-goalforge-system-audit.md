---
type: analysis
date: 2026-08-07
scope: goalforge system — repo organization, local integration, link/naming correctness, install story, chain design, multi-provider path, related plans/ideas
method: 10-agent fan-out workflow (survey + audit + adversarial verify of link findings), session 7d664636
---

# Goalforge System Audit — 2026-08-07

Consolidated from a multi-agent audit. Link/naming findings below survived an adversarial verify pass (26/28 confirmed, 2 corrected).



---

# 1. Repository organization (cogwright)

Now composing the final report.

# Repository Map — `cogwright`

`/home/cunger/10_projects/cogwright` — a marketplace of Claude Code plugin systems (currently `goalforge`, plus a vendored `interview` plugin sourced from an external repo via `git-subdir`).

## 1. Top-Level Layout

| Path | Role |
|---|---|
| `.claude-plugin/marketplace.json` | Marketplace manifest — declares 2 plugins: `goalforge` (local, `./plugins/goalforge`) and `interview` (external, pinned git-subdir from `Truncuso/elicitforge@v1.0.1`). Consumers install via `/plugin marketplace add` + `/plugin install`. |
| `packages/goalforge/` | **Source of truth** — authored nested v2 skill package (public parent `SKILL.md` + private child skills). Edit here. |
| `plugins/goalforge/` | **Generated artifact** — flat, plugin-discoverable shape Claude Code actually loads. Do not hand-edit (except a small hand-authored PRESERVE set). |
| `scripts/install.sh` | Contributor/consumer installer. |
| `scripts/goalforge-generate.sh` | The package→plugin generator (pure file transform, no LLM/network, idempotent). |
| `scripts/discovery-probe.sh` | (not inspected in depth — supporting script) |
| `docs/ARCHITECTURE.md` | Explains the build pipeline, relations map, day-to-day usage. |
| `docs/handoffs/`, `docs/examples/` | Session handoffs and worked examples (goal-object anatomy, session-handoff sample). |
| `plans/` | goalforge's own SDD-chain planning state (see §4). |
| `README.md`, `CONTRIBUTING.md`, `SECURITY.md`, `ACKNOWLEDGEMENTS.md`, `LICENSE` | Standard repo docs; README carries the plugin catalog + quickstart; CONTRIBUTING defines plugin shape + vendoring/attribution rules. |
| `.memory/` | Project-scoped memory store (daily logs, project facts, trace/dispatch logs, loop artifacts) — this repo dogfoods its own memory system. |

## 2. Plugin ↔ Package Relationship — **Generated, not symlinked/duplicated**

This is definitively answered by `scripts/goalforge-generate.sh` and `docs/ARCHITECTURE.md`:

- `packages/goalforge/` is **authored** — the canonical nested v2 package.
- `plugins/goalforge/` is **mechanically generated** from it by `scripts/goalforge-generate.sh`, a pure file transformation (no LLM calls, no network). Re-running it on a clean tree is a no-op (`git status --porcelain plugins/goalforge` empty).
- Mapping rules:
  - `packages/goalforge/SKILL.md`, `README.md` → same at plugin root
  - `packages/goalforge/<child>/` (has `SKILL.md`) → `plugins/goalforge/skills/<child>/`
  - `packages/goalforge/references/`, `scripts/` → same, root-level in plugin
  - `packages/goalforge/workflow-authoring/` (no `SKILL.md`) → same, verbatim
  - `evals/`, `__pycache__/`, `*.pyc` → **excluded** from the generated artifact
- A **pinned path-rewrite rule table** (classes i–vii, documented in the generator's header comment) handles the depth change from flattening `<child>/` into `skills/<child>/` — e.g. rewriting `${CLAUDE_SKILL_DIR}/<sub>` prose to `${CLAUDE_PLUGIN_ROOT}/skills/<child>/<sub>`, rewriting child→root script climbs, and stripping local-only telemetry hook declarations from generated frontmatter.
- `plugins/goalforge/hooks/`, `commands/`, `relations.yaml`, `.vendored-allowlist.txt` are **hand-authored and preserved** — the generator never touches them.
- **Drift gate:** `scripts/goalforge-generate.sh --check` regenerates and exits 2 on divergence; wired into pre-commit, so a package edit that wasn't regenerated cannot land — `plugins/` can never silently drift from `packages/`.
- Separately, `scripts/install.sh` (contributor mode) symlinks `~/dotfiles/claude/skills/goalforge` → `<repo>/packages/goalforge` (the source package, not the generated plugin) for local dogfooding; this symlink is per-machine and gitignored, never tracked. It also links sibling top-level skills `prototype` and `wayfind` the same way, but **deliberately does not link `interview`** — it stays private, package-internal only.

## 3. User-Facing Commands / Skills the Plugin Exposes

`plugins/goalforge/skills/` (18 child skills, mirroring `packages/goalforge/*/SKILL.md` 1:1):

`arbiter`, `archive`, `brief`, `capture`, `decompose`, `execute`, `harden`, `interview` (PRIVATE — `goalforge-interview`, invoked only by `harden`, not a front door), `onboard`, `plan-index`, `prototype`, `recap`, `redecompose`, `run`, `spec`, `verify`, `watchdog`, `wayfind`.

Front door: `goalforge` itself (`plugins/goalforge/SKILL.md`), public, routing the capture → spec → decompose → harden → execute → verify chain.

Slash command: `plugins/goalforge/commands/wayfind.md` → `/wayfind <effort-slug> [chart]` — charts a foggy multi-session effort into a decision map, then drives a frontier-computed work loop, graduating into `goalforge-capture` on convergence. Note its header flags a **mirror-sync obligation**: the dotfiles copy `~/.claude/commands/wayfind.md` is a downstream mirror that must be updated in the same lap for any contract change — a manual-sync liability worth knowing about.

Hooks exposed: `goalforge-pre-commit.sh` (the drift gate above) and `goalforge-single-writer.sh`, wired via `hooks/hooks.json`.

## 4. `plans/` Layout

Standard flat SDD layout (`plans/<feature>/{spec.md, todo.md, overview.md, wp-NN-<name>/}` + transition/trace JSONL logs), holding **multiple concurrent SDD tracks**, not just goalforge's own:

- `plans/goalforge/` — 21 WPs (wp-01 schema-v5 through wp-21 sdd-deletion), tracking the package/plugin build system itself.
- `plans/interview/` — 12 WPs, a separate SDD-chain interview-engine effort (distinct from the vendored `interview` plugin in the marketplace — worth disambiguating if it comes up).
- `plans/wayfind-learning-and-fanout/`, `plans/wayfind-work-loop-parity/`, `plans/mailforge/` (wayfind-only, no full WP tree yet) — smaller/parallel tracks.
- `plans/ideas/` — idea backlog with a ledger (`_ledger.jsonl`) and `_archived/`.
- `plans/_archived/` — retired tracks (`goalforge-prototype-native`, `goalforge-spike-spec`).
- `plans/docs/handoffs/` — appears to duplicate `docs/handoffs/` at a different root (see §5).

## 5. Structural Oddities / Notes

1. **No committed `__pycache__`/`.pytest_cache`** — checked directly; `packages/goalforge/scripts/__pycache__`, `.../workflow-authoring/scripts/__pycache__`, `packages/goalforge/.pytest_cache` all show as gitignored (`!!`), not tracked. Clean on this front, despite being present on disk.
2. **`plans/docs/handoffs/` vs `docs/handoffs/`** — two handoff directories at different roots exist in the tree; likely one is stale or the plans-root default (`~/.claude/plans/` vs repo `plans/`) leaked a nested `docs/` — worth a follow-up look since I did not fully diff their contents.
3. **`interview` name collision** — `plans/interview/` (an internal SDD track building an interview *engine*) is a different thing from the marketplace's vendored `interview` plugin (external, from `elicitforge`) and from `packages/goalforge/interview/` (a private goalforge child skill that delegates to a global interview-loop engine). Three same-named-but-distinct concepts in one repo — a naming collision CONTRIBUTING.md's own "one name per thing" rule would normally flag.
4. **`.claude-plugin/plugin.json` version is a git short-hash** (`"33b31eab96c9"`) rather than semver — presumably a generator-stamped build identifier, not a hand-set version; unusual but consistent with byte-stable/deterministic-generation design intent.
5. **Manual mirror-sync liability**: `/wayfind`'s command file explicitly documents that a second, out-of-repo copy (`~/.claude/commands/wayfind.md` in the maintainer's dotfiles) must be hand-kept in sync — a structural duplication the repo can't self-enforce.
6. No other stray files, dead symlinks, or unexpected duplication found between `plugins/` and `packages/` beyond the intentional, gate-enforced generation relationship described in §2.


---

# 2. Local integration (dotfiles)

No artifact publish needed for this — returning the report directly.

# Goalforge Integration Map — `/home/cunger/dotfiles/claude` (~/.claude)

## 1. Integration map — dotfiles vs symlinked from cogwright

Three per-machine, **untracked** symlinks under `skills/` point into `/home/cunger/10_projects/cogwright/packages/goalforge/` (contributor mode of `cogwright/scripts/install.sh`):

```
skills/goalforge  -> /home/cunger/10_projects/cogwright/packages/goalforge
skills/prototype  -> /home/cunger/10_projects/cogwright/packages/goalforge/prototype
skills/wayfind    -> /home/cunger/10_projects/cogwright/packages/goalforge/wayfind
```

All three resolve (not dangling). `skills/goalforge/` contains the real package: `capture/ spec/ decompose/ harden/ execute/ verify/ run/ interview/ recap/ redecompose/ onboard/ prototype/ wayfind/ watchdog/ workflow-authoring/ arbiter/ archive/ plan-index/ brief/ hooks/ references/ scripts/ evals/ SKILL.md README.md`. `interview/` is deliberately **not** linked at the top level (private, per the installer's own comment).

Everything else that touches goalforge is **native to dotfiles** (tracked, not symlinked):
- **Commands** (`commands/*.md`) — thin routers into the symlinked package.
- **Rules** (`references/rules/goalforge-chain.md`, `CLAUDE.md` §Workflows).
- **Hooks** (`hooks/goalforge-*.sh`) — local, tracked, invoke or check state of the symlinked package.
- **Consumer skills** that mention the chain in passing (`autopilot`, `sprint`, `handoff`, `idea`, `implement-and-verify`, `repo-governance`, `project-onboard`, `diagnose`, `interactive-debug`, `triage`, `project-track-sweep`, `okf-wiki`, `runbook`, `deprecation-and-migration`, `source-driven-development`, `skill-meta/skill-systems/interview`, `skill-meta/skill-cluster`).

**Naming-collision false lead:** `hooks/SDD-CACHE.md` is a citation cache for the **`source-driven-development`** skill — "SDD" here is a homonym for "Spec-Driven Development," unrelated to the goalforge chain. Its hook is wired only into that skill's own frontmatter `hooks:` block, explicitly *not* added to global `settings.json` (the doc warns against that).

## 2. Chain wiring: `/spec → /plan → /implement → /verify`

| Command (dotfiles, tracked) | Routes to (symlinked package) | Does |
|---|---|---|
| `commands/spec.md` | `goalforge-capture` → `goalforge-spec` (full route) or capture-only fast path | Scaffolds `plans/<feature>/overview.md`, stamps `route:`, drafts `spec.md`; human-gated draft→ready |
| `commands/plan.md` | `goalforge-decompose` → `goalforge-harden` (SKILL.md read directly — private children, no separate Skill-tool name; `Skill(skill:"goalforge-decompose")` explicitly fails) | WP folders under `plans/<feature>/<wp>/`; drives open questions to zero; human-gated hardened→ready |
| `commands/implement.md` | `goalforge-execute` | Executes one WP: dispatch → verify-and-simplify loop → advance to `verified` |
| `commands/verify.md` | `goalforge-verify` | Checks preconditions (tasks verified, findings.md present), runs eval harness, advances `status: verified` on PASS |

Orchestrator: `goalforge-run` (`skills/goalforge/run/`) can drive the full chain end-to-end via `chain.yaml`, route-aware (`fast | standard | wave`). Every command's Routing section names `goalforge-run` as the alternative to manual step-by-step.

Front-door skill: `skills/goalforge` itself is `PUBLIC` — explains the chain and routes names to `PRIVATE` children; explicitly not meant to run the chain (that's `/spec /plan /implement /verify` or `goalforge-run`).

Pre-capture on-ramp: `commands/wayfind.md` → symlinked `skills/wayfind`, optional before `goalforge-capture`, graduates into it.

Canonical rule doc: `references/rules/goalforge-chain.md` (tracked, extracted from `CLAUDE.md` §Workflows) states plainly: *"The `skills/goalforge/` package … installed as a per-machine symlink to the cogwright `packages/goalforge/` source (wp-18 contributor mode), is authoritative."*

**Hooks actually wired into `settings.json`** (global `PreToolUse`, matcher `Edit|Write|MultiEdit`, ~line 276):
```
hooks/goalforge-single-writer.sh   (timeout 5)
```
This is the *only* goalforge hook globally registered. The other five (`goalforge-checkpoint.sh`, `goalforge-transition-guard.sh`, `goalforge-open-questions-gate.sh`, `goalforge-frontmatter-touch.sh`, `goalforge-cache-pre.sh`, `goalforge-cache-post.sh`) are **not** in `settings.json` — they're invoked directly by name inside the package's own skill procedures (e.g. `goalforge-open-questions-gate.sh --check` called from `skills/goalforge/{capture,harden,run}/SKILL.md`), same on-demand pattern as the source-driven-development cache hook.

## 3. Stale references

**Confirmed stale — a retired `sdd-*` alias is still present as a live, independently-discoverable skill:**
```
skills/skill-meta/skill-systems/sdd-run/SKILL.md
skills/skill-meta/skill-systems/sdd-run/chain.yaml
skills/skill-meta/skill-systems/sdd-run/scripts/sdd-router.sh
```
`references/rules/goalforge-chain.md` states in-repo: *"The legacy `sdd-*` skill/script aliases were RETIRED 2026-07-21 (wp-21 deletion commit; historic mentions in archives/records stay untouched)."* `sdd-run/SKILL.md` still carries its own `description` frontmatter, which would make it independently discoverable by name — directly contradicting the same rule's "canonical and ONLY name" claim. Either the wp-21 deletion commit didn't cover this directory, or it was re-added afterward. This is ordinary tracked drift, not a broken symlink.

Other `sdd-` hits checked and found **not** stale:
- `skills/testing/evals/sdd-conditional-invocation/` — eval fixture name.
- `hooks/SDD-CACHE.md`, `hooks/goalforge-cache-pre.sh` — source-driven-development cache, unrelated "SDD" (see §1).
- `.pyc`/`.jsonl` trace/cache artifacts mentioning `sdd-` — generated, not authored.
- Everywhere else (`skills/repo-governance/*`, `skills/autopilot/*`, `skills/implement-and-verify/*`, `references/rules/{provenance,decision-capture}.md`) — generic prose "SDD chain" (Spec-Driven Development), current naming, not a `sdd-*` alias.

**Broken symlinks:** none. `find . -xtype l` over the whole tree returned nothing. All symlinks resolve, including the three goalforge links and the unrelated `tools/goalforge-viz/` build-artifact links (a Tauri app, not part of chain integration — coincidental name collision only).

**Paths that don't exist:** none found among goalforge-referenced paths.

## 4. Match against a fresh-user install (`cogwright/scripts/install.sh`)

The installer's contributor-mode target state is exactly what's on disk:
- `$HOME/dotfiles/claude/skills/goalforge` → symlink to `<cogwright-repo>/packages/goalforge` — **matches** (this machine's dotfiles root is `/home/cunger/dotfiles/claude` = `$HOME/dotfiles/claude`).
- Sibling `prototype`/`wayfind` top-level links into the same package subpaths — **matches** exactly, `interview/` correctly left unlinked.
- `classify_target()` would report `symlinked-correct-target` for all three (resolves via `readlink -f` to the expected target, `SKILL.md` present) — a re-run of the installer is a no-op, confirming installer-idempotent-clean state.
- Pre-checks the installer runs at install time (not independently re-verified here, since they need live git state in the cogwright checkout): `origin` remote contains `github.com/Truncuso/cogwright`, `packages/goalforge` has no uncommitted tracked changes.

**Diff from a hypothetical fresh install:** none in the symlink/package structure itself — the installer only manages the three symlinks, nothing in `commands/`, `hooks/`, or `skills/skill-meta/`. The one substantive drift is orthogonal to its scope: the **leftover `skills/skill-meta/skill-systems/sdd-run/`** (§3) is dotfiles-side legacy content the installer never touches and would persist unchanged across any number of fresh (re-)installs. A genuinely fresh setup would still need someone to separately delete it per the rule file's own "RETIRED 2026-07-21" claim — the installer has no mechanism or mandate to clean up retired dotfiles-side aliases.

## Files referenced

- `/home/cunger/dotfiles/claude/commands/{spec,plan,implement,verify,wayfind}.md`
- `/home/cunger/dotfiles/claude/references/rules/goalforge-chain.md`
- `/home/cunger/dotfiles/claude/settings.json` (hooks block, ~line 273-280)
- `/home/cunger/dotfiles/claude/hooks/goalforge-single-writer.sh` (+ 6 sibling `goalforge-*.sh` hooks, package-invoked not globally wired)
- `/home/cunger/dotfiles/claude/hooks/SDD-CACHE.md` (naming-collision false lead, unrelated to goalforge)
- `/home/cunger/dotfiles/claude/skills/{goalforge,prototype,wayfind}` (symlinks)
- `/home/cunger/dotfiles/claude/skills/skill-meta/skill-systems/sdd-run/` (stale — recommend deletion)
- `/home/cunger/10_projects/cogwright/scripts/install.sh`


---

# 3. Verified link / naming / command findings

- **CRITICAL** `.github/workflows/validate-plugins.yml`:36 — CONFIRMED as stated. The manifest validator does `os.path.join(source, ".claude-plugin", "plugin.json")` assuming `source` is a string. The `interview` entry in .claude-plugin/marketplace.json has an object source (`{source: git-subdir, url, path, ref, sha}`). Reproduced locally: running the validator's loop against the live marketplace.json raises `TypeError: expected str, bytes or os.PathLike object, not dict` on the `interview` entry.
  - Fix: Skip or branch on non-string sources: `if not isinstance(source, str): continue` (or validate the git-subdir shape separately: assert url/path/ref present) before building plugin_json_path.
- **CRITICAL** `packages/goalforge/harden/SKILL.md`:384 — CONFIRMED. `bash ~/.claude/hooks/goalforge-open-questions-gate.sh --check <wp>/overview.md` is documented as a runnable HARD backstop gate, but a repo-wide search finds goalforge-open-questions-gate.sh nowhere in the repo (no packages/, plugins/, or hooks/ copy). It is cited as a deterministic gate at capture/SKILL.md:180 (packages) / SKILL.md:173 (plugins), harden/SKILL.md:384 and :509 (packages) / :377 and :502 (plugins), references/schema.md:271 (both), run/SKILL.md:46 (packages) / :39 (plugins) and run/chain.yaml:19 (both) — the last two make it part of the `fast` route's gate set. docs/handoffs (2026-08-05, 2026-08-05 44b17b8b) already record the runtime error `No such file or directory` for this exact path.
  - Fix: Either ship the script under packages/goalforge/hooks/ (and register it) or delete all references and remove it from the fast-route gate list in run/chain.yaml:19 and run/SKILL.md. Do not leave a non-existent binary named as a hard gate.
- **HIGH** `plugins/goalforge/skills/run/scripts/goalforge-router.sh`:22 — CONFIRMED path-resolution defect, REFUTED exit-code claim. `SKILLS_ROOT="${CLAUDE_SKILLS_ROOT:-$HOME/.claude/skills}"` combined with chain.yaml step ids (`goalforge/capture`, ...) resolves to `~/.claude/skills/goalforge/<child>/SKILL.md` — the maintainer's dotfiles layout — with no attempt at `${CLAUDE_PLUGIN_ROOT}/skills/<child>/`, which is where children actually live in an installed plugin. Reproduced: running with `CLAUDE_SKILLS_ROOT=/tmp/nonexistent-skills-root` (simulating a consumer install) prints all 7 steps UNRESOLVED. However, the claim that the script 'still exited 0' is refuted — reproduced exit code is 1 in both a nonexistent-HOME run and a nonexistent-CLAUDE_SKILLS_ROOT run, matching the script's own `[ "$unresolved" -eq 0 ] || exit 1` logic and the header's stated contract. The exit-code sub-claim does not hold; only the path-resolution defect is real.
  - Fix: Resolve plugin-first: try `${CLAUDE_PLUGIN_ROOT:-$SCRIPT_DIR/../../..}/skills/<child>/SKILL.md` (stripping the `goalforge/` prefix from the chain.yaml step id), fall back to $SKILLS_ROOT.
- **HIGH** `plugins/goalforge/SKILL.md`:55 — CONFIRMED. All four Shared-assets rows (lines 55-58) point at `~/.claude/skills/goalforge/references/...` and `~/.claude/skills/goalforge/scripts/goalforge-*.sh` — the maintainer's dotfiles path, absent for a marketplace consumer. Systemic: 101 occurrences of `~/.claude/skills/goalforge/` confirmed across 19 files under plugins/. docs/ARCHITECTURE.md's rewrite-class table (comment header of scripts/goalforge-generate.sh, lines ~57-62) covers `$SCRIPT_DIR` climbs and `${CLAUDE_SKILL_DIR}` prose only — bare `~/.claude/skills/goalforge/` prose is not a listed class.
  - Fix: Add a rewrite class to scripts/goalforge-generate.sh: `~/.claude/skills/goalforge/references/` -> `${CLAUDE_PLUGIN_ROOT}/references/`, `~/.claude/skills/goalforge/scripts/` -> `${CLAUDE_PLUGIN_ROOT}/scripts/`, `~/.claude/skills/goalforge/<child>/` -> `${CLAUDE_PLUGIN_ROOT}/skills/<child>/`. Add a generator eval asserting zero `~/.claude/skills/goalforge` occurrences in plugins/.
- **HIGH** `plugins/goalforge/commands/wayfind.md`:26 — CONFIRMED, with a line-number correction: the dotfiles reference is at line 26 (not 24, which is unrelated prose about explicit chart mode). Content otherwise as stated: 'Resolve `<PLANS_ROOT>` per `~/.claude/skills/goalforge/references/schema.md` §PLANS_ROOT resolution' is a dotfiles path absent on a consumer install. `commands/` is on the generator's PRESERVE list (scripts/goalforge-generate.sh line 71), so this file is hand-authored and never rewritten. The rest of the file correctly uses `${CLAUDE_PLUGIN_ROOT}` (e.g. line 35), making this one an oversight.
  - Fix: Change to `${CLAUDE_PLUGIN_ROOT}/references/schema.md`.
- **HIGH** `docs/ARCHITECTURE.md`:138 — CONFIRMED. "The `/spec`, `/plan`, `/implement`, `/verify` commands are the human entry points" — none are shipped; plugins/goalforge/commands/ contains only wayfind.md. The same claim is repeated verbatim/near-verbatim at packages/goalforge/SKILL.md:67, plugins/goalforge/SKILL.md:62, and packages/goalforge/README.md:3 (frontmatter description). A consumer who installs the goalforge plugin gets /wayfind and nothing else, with no documented way to drive the chain.
  - Fix: Either author commands/spec.md, plan.md, implement.md, verify.md in plugins/goalforge/commands/ (hand-authored, PRESERVE list, mirroring wayfind.md's thin-dispatch shape), or rewrite every one of these passages to state that the four entry commands live in the maintainer's dotfiles and that plugin consumers invoke `goalforge-run` by name.
- **HIGH** `packages/goalforge/SKILL.md`:82 — CONFIRMED. "with one script rename: `goalforge-route.sh` → `goalforge-route.sh`" is an identity mapping that says nothing. references/alias-map.md:41,56 shows the intended content is `sdd-goal-route.sh` → `goalforge-route.sh`. Identical defect confirmed at plugins/goalforge/SKILL.md (same 'Alias layer' section, header at plugins/goalforge/SKILL.md:73).
  - Fix: Delete the sentence along with the whole stale ## Alias layer section (see next finding), or restore it as `sdd-goal-route.sh` → `goalforge-route.sh`.
- **HIGH** `packages/goalforge/SKILL.md`:78 — CONFIRMED. The `## Alias layer (copy-first migration)` section (lines 78-85) asserts retired content as current: "The legacy `sdd-*` skills and `sdd-*.sh` scripts remain in place as LOCAL-pointing aliases" and "Deletion of the `sdd-*` sources is deferred behind a separate human sign-off gate", including external-consumer names (tangram ADR-0008, ProSIP). This contradicts CLAUDE.md's own policy that `sdd-*` aliases were RETIRED 2026-07-21. Mirrored at plugins/goalforge/SKILL.md:73 ("## Alias layer" header confirmed present), so it ships to consumers.
  - Fix: Delete lines 78-85 from packages/goalforge/SKILL.md (and the mirrored block in plugins/goalforge/SKILL.md) and regenerate. Optionally replace with a one-line retirement note.
- **HIGH** `packages/goalforge/SKILL.md`:28 — CONFIRMED, line is 28 not 27. "The LOCAL dotfiles tree is the source of truth; the cogwright `goalforge` plugin is a downstream **export**" (line 28) contradicts README.md:57 (`packages/<name>/` = **Source of truth.** ... Edit here) and docs/ARCHITECTURE.md:8-9 (`packages/<name>/` is authored; `plugins/<name>/` is generated). It also cites a private/gitignored path, `plans/suite-extraction/overview.md`.
  - Fix: Rewrite to match README/ARCHITECTURE: packages/goalforge is the authored source of truth, plugins/goalforge is its generated artifact. Drop the private plans/ citation.
- **MEDIUM** `packages/goalforge/references/state-machine.md`:6 — CONFIRMED. Names `hooks/goalforge-transition-guard.sh` as "the advisory guard" consuming this file. No such file exists anywhere in the repo (a repo-wide filename search returns nothing; only *references* to it exist). Shipped identically at plugins/goalforge/references/state-machine.md:6, and plugins/goalforge/hooks/goalforge-single-writer.sh:18 documents a 'DIVISION OF LABOR' with the same phantom file.
  - Fix: Delete the reference from both state-machine.md copies and from the goalforge-single-writer.sh header, or ship the guard.
- **MEDIUM** `packages/goalforge/references/state-machine.md`:5 — Cites the write mechanism as `skills/goalforge/scripts/goalforge-transition.sh` — a path shape that exists in neither tree. In the package it is `scripts/goalforge-transition.sh` (verified at packages/goalforge/scripts/goalforge-transition.sh); in the plugin, `${CLAUDE_PLUGIN_ROOT}/scripts/goalforge-transition.sh` (verified at plugins/goalforge/scripts/goalforge-transition.sh). Same defect at plugins/goalforge/references/state-machine.md:5.
  - Fix: Use `scripts/goalforge-transition.sh` (package) / `${CLAUDE_PLUGIN_ROOT}/scripts/goalforge-transition.sh` (plugin) via a generator rewrite.
- **MEDIUM** `plugins/goalforge/SKILL.md`:33 — Every one of the 15 rows in the Children table gives the child path as `capture/`, `spec/`, `harden/`, ... — the package layout, verbatim identical to packages/goalforge/SKILL.md. In the shipped plugin the children are physically at `skills/capture/`, `skills/spec/`, etc. per the generator's own mapping rule (`packages/goalforge/<child>/ -> plugins/goalforge/skills/<child>/`), but the plugin SKILL.md's table is unrewritten and still says `capture/` etc. Same for the prose notes lower in the file (`prototype/`, `wayfind/`, `brief/`).
  - Fix: Add the child-path table to the generator's rewrite classes (`\`<child>/\`` -> `\`skills/<child>/\`` for the 18 known child names), or write the rows as bare skill names with no path column.
- **MEDIUM** `packages/goalforge/references/alias-map.md`:4 — This whole file is migration-era scaffolding published as reference. (a) It instructs the reader to resolve `$COGWRIGHT_ROOT` to a cogwright checkout "default `~/10_projects/cogwright`" and build every skill/script path from it, rather than using ${CLAUDE_PLUGIN_ROOT} for a plugin install. (b) Line ~37 header claims "exec-forward shims live at `../scripts/`" while the file's own table maps every sdd-*.sh to a plain rename under the plugin scripts dir, not a shim. (c) It is written in unresolved future tense: "finalized by the member-move task (task-02)" and "Callers must be repointed at the plugin copy directly (task-04 rewire)" — both confirmed present verbatim. (d) Its child-skill table lists only the 14 legacy sdd-* names and omits brief, interview, prototype, wayfind (none of which had sdd-* predecessors). Shipped at plugins/goalforge/references/alias-map.md.
  - Fix: Either rewrite as a pure historical name map with no $COGWRIGHT_ROOT paths and no open task references, or drop it from the package (only packages/goalforge/SKILL.md and plugins/goalforge/SKILL.md link to it, both pointing at a ~/.claude path).
- **MEDIUM** `packages/goalforge/run/SKILL.md`:3 — The skill description declares "the canonical route enum one-go|fast|standard|wave", but packages/goalforge/scripts/goalforge-route.sh states the canonical enum is `fast|standard|wave` and that legacy vocab (`full`->`standard`, `one-go`->`fast`) normalizes on read, "never a 4th enum value". references/schema.md repeats the 4-value framing (route table lists one-go/fast/standard/wave as "Four values") though its back-compat note does say fast/full normalize. Separately, run/chain.yaml's top-level description still says "full = capture → spec → ..." (legacy name) while its own step entries use `when_route: standard` (canonical name) — an internal inconsistency confirmed in the file.
  - Fix: Make goalforge-route.sh authoritative: change run/SKILL.md and schema.md to `fast|standard|wave` (moving one-go/full to a 'legacy, normalized on read' note), and change chain.yaml's description line `full` -> `standard`.
- **MEDIUM** `README.md`:82 — Version claims disagree with the artifacts. README says goalforge is "shipped (v0.1.0)" but packages/goalforge/SKILL.md declares `metadata.version: 3.0.0`, and plugins/goalforge/.claude-plugin/plugin.json stamps `"version": "33b31eab96c9"` (a commit SHA). README also says "wayfind (v0.2.0)" while packages/goalforge/wayfind/SKILL.md declares 0.3.0. prototype (v0.3.0 in README) does match packages/goalforge/prototype/SKILL.md's 0.3.0.
  - Fix: Pick one version authority (SKILL.md metadata.version) and make README quote it: goalforge v3.0.0, wayfind v0.3.0. Decide separately whether plugin.json should carry a semver instead of a SHA and document the choice in README.
- **MEDIUM** `README.md`:82 — "18 skills — 15 chain stages plus `wayfind`, `prototype`, and `brief`" implies brief is NOT a stage, matching packages/goalforge/SKILL.md's explicit note that brief is a chain-support asset, not a stage. But docs/ARCHITECTURE.md puts `BRF[brief]` inside `subgraph SUP["support stages"]` — i.e. a subgraph literally titled "support stages" — while the CHAIN subgraph (capture→spec→decompose→harden→execute→verify) and SUP together omit `interview` entirely; INT appears only as a separate node connected via `HAR --> INT`, outside both subgraphs. Since packages/goalforge/SKILL.md's own Children table counts interview as one of its 15-row stage list, ARCHITECTURE.md's diagram structurally disagrees with both README and the package's own stage count on which 15 skills are "stages".
  - Fix: Move BRF out of the `support stages` subgraph in ARCHITECTURE.md (into the co-tenants group or its own node) and add INT/interview into the CHAIN or SUP grouping, so the diagram agrees with README/SKILL.md that the 15 stages include interview and exclude brief.
- **LOW** `README.md`:94 — "The chain is fifteen stage skills, but two of them are worth naming separately" then names wayfind and prototype — which the immediately preceding catalog line explicitly places OUTSIDE the fifteen chain stages ("15 chain stages plus wayfind, prototype, and brief"). "two of them" contradicts that same paragraph's own count.
  - Fix: Reword to "...but two skills that are not stages are worth naming separately".
- **MEDIUM** `docs/examples/README.md`:17 — Public example docs point readers at `/handoff-pickup` (table row, and repeated in docs/examples/session-handoff.md's "Suggested skills next session" section, which also names `/idea-review`), and the goal-object-anatomy row references `/plan` and `/implement`. Checked plugins/goalforge/commands/ — it contains only wayfind.md (plus .gitkeep); none of handoff-pickup, idea-review, plan, or implement is shipped as a command by any plugin in this marketplace. A reader following the examples has no way to run them from an installed cogwright plugin.
  - Fix: Add a note stating which commands are maintainer-dotfiles-only and not part of the shipped plugin surface, or scrub the command names to skill names.
- **MEDIUM** `CONTRIBUTING.md`:11 — "A new or changed skill includes deterministic eval cases (`skills/<name>/evals/`)" and the Plugin-shape block (`skills/<skill>/SKILL.md  # + scripts/, references/, evals/ per skill`) both point contributors at a plugin-side evals/ path. Confirmed against scripts/goalforge-generate.sh's own header comment: `packages/goalforge/evals/ -> EXCLUDED (workspace/pyc pollution...)` — evals are deliberately dropped from the generated plugin artifact and live only at `packages/<pkg>/<skill>/evals/` (verified present there, e.g. packages/goalforge/capture/evals). CONTRIBUTING never states the packages/-authored vs plugins/-generated rule (that only appears in README.md's Repository layout table, which explicitly says "Do not hand-edit" plugins/), so a contributor following CONTRIBUTING alone is steered toward a nonexistent generated eval path and not warned off hand-editing plugins/.
  - Fix: Change the eval path to `packages/<pkg>/<skill>/evals/`, annotate the plugin-shape block as generated output (no evals/), and add a ground rule pointing to README's authored-vs-generated distinction.
- **LOW** `packages/goalforge/references/dispatch-template.md`:7 — Points at `skills/execute/references/dispatch-resolution.md`. That resolves in the plugin (confirmed: plugins/goalforge/skills/execute/references/dispatch-resolution.md exists) but not in the package, where the file is actually at `execute/references/dispatch-resolution.md` (confirmed: packages/goalforge/execute/references/dispatch-resolution.md exists; `skills/execute/...` does not exist under packages/). The authored source of truth uses a plugin-shaped path.
  - Fix: Use package-relative `execute/references/dispatch-resolution.md` in the package source and let the generator's rewrite rule turn it into the plugin-shaped path in the generated copy.
- **LOW** `packages/goalforge/run/SKILL.md`:281 — Gives `commands/spec.md` as a concrete example of an entry command bypassing the orchestrator. No commands/spec.md exists anywhere in the repo (plugins/goalforge/commands/ holds only .gitkeep and wayfind.md; the only spec.md files found are unrelated eval fixtures and plans/goalforge/spec.md). The paragraph documents runtime behaviour of four command files that are not part of this repo.
  - Fix: Drop the `commands/spec.md` parenthetical, or ship the command files and the reference becomes valid.
- **LOW** `packages/goalforge/SKILL.md`:72 — "reachable via the installer's top-level symlinks (Interface Contract §5)" cites a document called 'Interface Contract' that does not exist in the repo as a file or heading — only scattered informal uses of the phrase 'Interface Contract' inside unrelated spec.md prose and handoff docs, none numbered into sections. (The symlink behaviour itself is real: scripts/install.sh documents `<skills>/prototype` and `<skills>/wayfind` as top-level symlinks.)
  - Fix: Replace the citation with `scripts/install.sh`, or with a real anchor in docs/ARCHITECTURE.md.
- **LOW** `packages/goalforge/capture/SKILL.md`:104 — References a `goalforge-frontmatter-touch.sh` hook that "also bumps these on every Write/Edit". No such script file exists anywhere in the repo (confirmed via find); the only other mentions are the identical claim mirrored in plugins/goalforge/skills/capture/SKILL.md:97 and a bare filename reference inside a comment in plugins/goalforge/hooks/goalforge-single-writer.sh:26.
  - Fix: Delete the claim or ship the hook — as written the skill tells the agent a mtime/updated field is maintained automatically when nothing maintains it.
- **LOW** `packages/goalforge/README.md`:10 — "Orchestrated by `goalforge-run` (sibling `chain.yaml`)" — chain.yaml is not a sibling of this README (which lives at packages/goalforge/README.md); it is at packages/goalforge/run/chain.yaml (and plugins/goalforge/skills/run/chain.yaml for the plugin copy).
  - Fix: Change to `run/chain.yaml`.
- **LOW** `docs/ARCHITECTURE.md`:130 — "Declared degradations, verbatim from `plugins/goalforge/relations.yaml`" — the interview row is not verbatim: relations.yaml:13 says "one-question-at-a-time AskUserQuestion loop in the main session", the table says "one-question-at-a-time question loop in the main session" — dropping 'AskUserQuestion'. A claim of verbatim reproduction that drifts is worse than an unclaimed paraphrase, since nothing gates it.
  - Fix: Restore the exact string, or drop the word 'verbatim'. Better: add a check to CI that diffs the table against relations.yaml.
- **LOW** `docs/examples/goal-object-anatomy-wp.md`:47 — This published example contains multiple live-sounding references to retired sdd-* names (sdd-transition.sh, sdd-goal-hash.sh, sdd-frontmatter-touch.sh, hooks/sdd-transition-guard.sh, sdd-validate.sh) confirmed present in the file. Internally it flags them as "CURRENT pre-migration names", but docs/examples/README.md presents this file as a "Real, working artifact" scrubbed only for absolute paths, with no note that the naming is historical — while CLAUDE.md policy states goalforge is the canonical and ONLY name (sdd-* RETIRED 2026-07-21). A reader grepping for sdd-transition.sh finds nothing live.
  - Fix: Add one line to docs/examples/README.md noting this WP is a frozen pre-migration artifact predating the sdd-*→goalforge-* rename; script names in it are historical. Do not rewrite the artifact itself.
- **LOW** `packages/goalforge/references/schema.md`:119 — The plans-root override env var is `SDD_PLANS_DIR` (confirmed at schema.md:50, "env `SDD_PLANS_DIR` → project git-root...") — a retired-prefix name that survives across at least 62 files repo-wide (README.md, schema.md, run/SKILL.md, scripts, plugin mirrors). It is consistent everywhere, so nothing is functionally broken, but it directly contradicts packages/goalforge/README.md's claim that goalforge is 'the canonical and ONLY name' of the chain.
  - Fix: Low priority and a breaking change for existing users. If renamed: accept GOALFORGE_PLANS_DIR with SDD_PLANS_DIR as a documented deprecated fallback, updated in one sweep. Otherwise add an explicit note that the sdd-prefixed env var name is retained deliberately for back-compat.


---

# 4. Install story audit (INSTALL.md draft landed at repo root)

A fresh external install today is a two-line marketplace flow (`/plugin marketplace add Truncuso/cogwright` → `/plugin install goalforge@cogwright`) that clones `origin/main` into `~/.claude/plugins/marketplaces/cogwright/` and activates 18 plugin skills, exactly one command (`/wayfind`), one always-on PreToolUse hook, plus root-level `scripts/` and `references/`. That is materially less than the documented product: the four advertised entry points `/spec`, `/plan`, `/implement`, `/verify` are NOT in the plugin — they exist only in the author's private dotfiles (`~/.claude/commands/`), so an external user installs a chain with no front door. The deepest defect is path leakage: 101 occurrences of `~/.claude/skills/goalforge/...` survive into the generated plugin (SKILL.md prose, references, and script defaults), pointing at a directory that exists only on the author's machine; the generator's pinned rewrite table (classes i–vii) covers `${CLAUDE_SKILL_DIR}` and script climbs but never the plugin's own `~/.claude/skills/goalforge` self-references. Real undeclared runtime dependencies are python3 + **PyYAML** (hard-fails 9 scripts), **jq** (93 call sites, guarded at only 2), `flock`, `timeout`, `realpath`, `tar`, and git — several absent on stock macOS — none mentioned anywhere in README or CONTRIBUTING. `scripts/install.sh --mode consumer` is decorative (it prints the two commands and runs `claude plugin validate`, which needs a checkout the consumer does not have), and `--mode contributor` hardcodes the author's `~/dotfiles/claude/skills` layout and refuses any origin remote that is not `github.com/Truncuso/cogwright`, so a fork cannot use it without the undocumented `GF_SKIP_REPO_PRECHECK=1` / `GF_TARGET_DIR` env vars. Secondary gaps: `origin/main` is ~6 days behind local HEAD and lacks the `interview` marketplace entry; `evals/` is deliberately excluded from the artifact so external users have no runnable acceptance test; the flatten-to-plugin step inverts the package's privacy model, making all 15 "PRIVATE" chain children independently discoverable/auto-triggerable; `plugin.json` stamps a commit SHA (`33b31eab96c9`) as version while the README claims v0.1.0; and there is no uninstall documentation for the PreToolUse hook, the appended git `pre-commit` marker block, or the contributor symlinks. A complete external-user INSTALL.md draft is in the details, covering prerequisites, plugin route, manual route, verification, troubleshooting, and uninstall — plus an explicit "known limitations" section so the doc stays honest about the missing commands and dead `~/.claude` paths until those are fixed.

---

# goalforge — external-user install audit

Files read: `scripts/install.sh`, `scripts/goalforge-generate.sh`, `README.md`,
`CONTRIBUTING.md`, `docs/ARCHITECTURE.md`, `.claude-plugin/marketplace.json`,
`plugins/goalforge/**` (manifest, `SKILL.md`, `README.md`, `relations.yaml`,
`hooks/`, `commands/`, `scripts/`, 18 child `SKILL.md`),
`plans/goalforge/wp-18-symlink-installer/overview.md`,
`plans/goalforge/wp-20-consumer-migration/overview.md`,
`~/dotfiles/claude/commands/{plan,implement}.md`, `~/.claude/plugins/` layout.

---

## 1. What a fresh install actually requires and produces today

### The marketplace (consumer) route

```
/plugin marketplace add Truncuso/cogwright
/plugin install goalforge@cogwright
```

**Requires:** Claude Code with plugin support, `git`, network access to GitHub.
Nothing else is checked or announced.

**Mechanically produces** — the marketplace is cloned to
`~/.claude/plugins/marketplaces/cogwright/` (confirmed against this machine's
`~/.claude/plugins/{marketplaces,installed_plugins.json,known_marketplaces.json}`),
so `${CLAUDE_PLUGIN_ROOT}` resolves to
`~/.claude/plugins/marketplaces/cogwright/plugins/goalforge`. The user gets:

| Surface | What lands | Count |
|---|---|---|
| Skills | `plugins/goalforge/SKILL.md` (parent) + `skills/<child>/SKILL.md` | 1 + 18 |
| Commands | `commands/wayfind.md` → `/wayfind` | **1** |
| Hooks | `hooks/hooks.json` → PreToolUse `Edit\|Write\|MultiEdit` single-writer guard | **1, auto-active** |
| Shared assets | root `scripts/` (~35 scripts), `references/`, `workflow-authoring/` | — |
| Evals | **none** — `evals/` is excluded by the generator by design | 0 |
| Agents | **none** — no `agents/` dir, though skills dispatch roles `wp-harden-delta`, `wp-verify`, `feature-audit`, `integration-review` | 0 |

**Does NOT produce:** `/spec`, `/plan`, `/implement`, `/verify`. README §Catalog
and `docs/ARCHITECTURE.md` both name these as "the human entry points"; they live
only in the maintainer's `~/.claude/commands/` (verified: `plan.md`,
`implement.md`, `spec.md`, `verify.md` exist there, and their bodies route via
`~/.claude/skills/goalforge/...`). **An external user installs the chain with no
front door for 4 of its 5 entry points.** `plugins/goalforge/commands/` is on the
generator's `PRESERVE` list, so this is an authoring omission, not a generator bug.

**Dotfiles assumptions:** none are *required* for the marketplace route, but many
are *assumed by content* (see §2). No `~/dotfiles` layout is needed to install.

### `scripts/install.sh --mode consumer`

Effectively a no-op: prints the two `/plugin` lines to stderr, then runs
`claude plugin validate` if the CLI is on PATH. That validate call resolves
against the *current working directory* — a consumer who has not cloned the repo
has nothing to validate. This mode has no reason to exist for an external user
(`install.sh` only reaches them via a git clone they didn't need).

### `scripts/install.sh --mode contributor`

Dev-only symlink installer, and it is author-shaped:

- Default target `GF_TARGET_DIR="$HOME/dotfiles/claude/skills/goalforge"` — the
  maintainer's dotfiles layout. Overridable by env, **undocumented in README**.
- `precheck_remote()` hard-fails unless `origin` matches
  `github.com/Truncuso/cogwright`. **A fork's remote fails.** The escape hatch
  `GF_SKIP_REPO_PRECHECK=1` exists but is undocumented outside the source.
- `precheck_checkout_clean()` refuses on any uncommitted tracked change under
  `packages/goalforge` — reasonable for the author, hostile to a contributor
  mid-edit.
- Also links siblings `<skills>/prototype` and `<skills>/wayfind`; `interview/`
  stays unlinked (private by design).
- Quality note: the 8-case sandboxed `--self-test` is genuinely good — fresh /
  correct / wrong-target / dangling / transient-only / dirty-real /
  missing-checkout / legacy-sibling, with tar-backup rollback and retained
  dirty-dir tarballs. The engineering is solid; the *addressing* is personal.

### Repo-state caveat

`origin/main` HEAD is `0be25cb6` (2026-07-31); local HEAD is `dd9a3395`
(2026-08-06). `/plugin marketplace add` pulls the default branch, so external
users currently get a tree ~6 days stale, **without** the `interview` marketplace
entry that exists locally, and missing 25 files / +1225 lines of wayfind work.
Marketplace freshness is gated on pushing `main`.

---

## 2. Hidden dependencies on the author's environment

### 2a. `~/.claude` path leakage into the shipped artifact — the headline defect

101 occurrences of `~/.claude/skills/goalforge/...` survive into
`plugins/goalforge/`, plus:

| Leaked prefix | Hits | Effect on an external user |
|---|---|---|
| `~/.claude/skills/goalforge` | **101** | Dead path. Prose tells the model to `bash ~/.claude/skills/goalforge/scripts/goalforge-route.sh …`; nothing is there. |
| `~/.claude/plans/` | 17 (+5 `_archived`) | Benign — this *is* the documented global PLANS_ROOT fallback. |
| `~/.claude/skills/idea` | 6 | `provenance-mapping.md`, `idea-overlap.sh` — author-only skill, no `recommends` entry, no declared degrade. |
| `~/.claude/skills/autopilot` | 4 | `autonomy-policy.md` — author-only, referenced by `harden`, `spec`, `execute`, `run`. |
| `~/.claude/scripts/handoff-env.sh` | 1 | `goalforge-attribution.sh` default (`HANDOFF_ENV_SCRIPT` override exists). |
| `~/.claude/hooks/goalforge-open-questions-gate.sh` | 1 | Author-only hook. |
| `~/.claude/commands/wayfind.md`, `~/.claude/rules/common`, `~/.claude/skills/fable-mode` | 3 | Mirror-sync notes / vendored-source attribution — cosmetic. |

Root cause is a gap in the generator's own pinned rule table
(`scripts/goalforge-generate.sh` header, classes i–vii): it rewrites
`$SCRIPT_DIR/../scripts` climbs and `${CLAUDE_SKILL_DIR}/<sub>` prose, and class
(vi) *deliberately* leaves cross-skill prose (autopilot/idea) verbatim rather
than inventing dead paths. But the package's references to **its own** assets via
`~/.claude/skills/goalforge/...` are in no class at all — they are neither
rewritten to `${CLAUDE_PLUGIN_ROOT}` nor recognised as a leak. Note some files
already use `${CLAUDE_PLUGIN_ROOT}` correctly (`harden/SKILL.md`,
`recap/SKILL.md`, `redecompose/SKILL.md`), so the artifact is internally
inconsistent — a mixed-addressing bug, not a uniform convention.

`scripts/goalforge-preharden-lint.sh` even lints *for* `$CLAUDE_PLUGIN_ROOT` /
`plugins/cogwright` literals in the local tree (enforcing the reverse direction);
there is no symmetric lint catching `~/.claude/skills/goalforge` in the plugin.

### 2b. Undeclared external binaries and libraries

Nothing in README, CONTRIBUTING, or the plugin manifest states prerequisites.
Actual usage across `plugins/goalforge/{scripts,hooks}`:

| Dependency | Call sites | Guarded? | Notes |
|---|---|---|---|
| `git` | 144 | — | assumed |
| **`jq`** | **93** | Only 2 (`goalforge-attribution.sh`, `goalforge-single-writer.sh`) | The other ~91 sites fail opaquely without it. |
| `python3` | 61 | — | stdlib only otherwise (`json/os/re/subprocess/argparse/fcntl/pathlib/typing/tempfile/importlib`) |
| **PyYAML** | 9 scripts | Yes — explicit `ImportError` → `pip3 install pyyaml`, exit 1 | Hard, non-stdlib. Blocks `goalforge-validate.sh`, `-status`, `-frontier`, `-rollup`, `-wp-complexity`, `-plan-index`, `-reconcile-diff`, `-pick-agent`, `-goal-eval`. |
| `flock` | 13 | No | util-linux. **Absent on stock macOS** → transition locking breaks. |
| `timeout` | 4 | No | GNU coreutils. **Absent on stock macOS.** |
| `realpath` | 4 | No | **Absent on stock macOS** (pre-coreutils). |
| `tar`, `diff`, `sed`, `awk` | many | No | POSIX-ish; GNU-flag risk on BSD `sed`. |
| `rg` | 6 | **Yes** — `command -v rg` with grep fallback | Good precedent, not followed elsewhere. |
| `claude` CLI | 36 | mixed | dispatch paths |
| bash ≥ 4 | `goalforge-archive-batch.sh` uses `mapfile`/`declare -A` | No | macOS ships bash 3.2. |

Net: **untested on macOS**, and the failure mode is a silent/opaque script error
rather than a preflight message.

### 2c. Hooks with author-path defaults

- `hooks/hooks.json` wires `goalforge-single-writer.sh` as a **PreToolUse
  `Edit|Write|MultiEdit` blocker** the moment the plugin is installed. It blocks
  hand-edits to `status:` / `goal_approved_version:` in
  `<git-root>/plans/**` or `~/.claude/plans/**` (basenames `overview.md`,
  `spec.md`, `task-*.md`). It degrades to allow-all without `jq`
  (`command -v jq || { cat >/dev/null; exit 0; }`) — so on a jq-less box the
  guard silently does nothing while the rest of the chain silently misbehaves.
  **This side effect is documented nowhere user-facing.**
- `hooks/goalforge-pre-commit.sh` defaults its validator to
  `$HOME/.claude/skills/goalforge/scripts/goalforge-validate.sh`
  (`GOALFORGE_VALIDATE_SCRIPT` override). For a plugin user that path is dead —
  the hook is zero-breakage (prints a notice, exit 0), so it installs and does
  nothing. Only reachable via `goalforge-install-hooks.sh`, which does resolve
  package-relative first, so the practical impact is limited to the fallback arm.

### 2d. Soft/agent dependencies

`relations.yaml` honestly declares 3 `recommends` with named degrades
(`research-analyst` agent, `interview-loop` skill, `adr-write` skill). But it
does **not** cover the author-only `idea` and `autopilot` skills that 10
reference sites reach into, nor the four dispatch roles (`wp-harden-delta`,
`wp-verify`, `feature-audit`, `integration-review`) that ship no agent
definitions.

### 2e. Version / identity confusion

`plugin.json` stamps `"version": "33b31eab96c9"` — a cogwright commit SHA, chosen
deliberately (documented experiment: version-less passes `claude plugin validate`
but fails `--strict`). README catalog says goalforge is "shipped (v0.1.0)"; the
parent `SKILL.md` frontmatter says `version: 3.0.0`. Three different version
strings for the same artifact. External users cannot tell what they have.

### 2f. Privacy-model inversion

The package design is explicit: children are PRIVATE, discovery is one level
deep, nesting *is* the privacy mechanism ("Children do not trigger by discovery").
Flattening `packages/goalforge/<child>/` → `plugins/goalforge/skills/<child>/`
makes all 18 children **top-level plugin skills**, independently discoverable and
auto-triggerable as `goalforge:goalforge-harden`, etc. External-user behavior
therefore differs structurally from the author's. Worth a deliberate decision:
either accept it and document the invocation names, or suppress child discovery.

---

## 3. Gaps vs. a clean external-user experience

Ranked by user impact:

1. **No entry commands.** `/spec`, `/plan`, `/implement`, `/verify` are not in
   the plugin. Highest-impact, cheapest fix: author 4 files in
   `plugins/goalforge/commands/` (already on the generator PRESERVE list),
   `${CLAUDE_PLUGIN_ROOT}`-addressed.
2. **101 dead `~/.claude/skills/goalforge` paths.** Add a class-viii rewrite
   (`~/.claude/skills/goalforge/` → `${CLAUDE_PLUGIN_ROOT}/`, with the
   child-flattening map `<child>/` → `skills/<child>/`), plus a symmetric
   preharden lint so it can't regress.
3. **No INSTALL.md and no stated prerequisites.** Install info is split across
   README §Installing (30 lines, contributor-biased) and the `install.sh` header
   comment. PyYAML/jq/flock are discovered by crashing.
4. **No verification story.** `evals/` is excluded from the artifact by design,
   `scripts/discovery-probe.sh` lives at repo root and is not shipped. External
   users have no "did this install correctly?" command.
5. **No uninstall story.** Nothing documents removing the PreToolUse hook, the
   appended `# >>> sdd-pre-commit >>>` block in a repo's `.git/hooks/pre-commit`,
   or contributor symlinks.
6. **`main` is stale.** Marketplace consumers get a week-old tree missing the
   `interview` entry. Needs a release/push discipline, ideally a tagged ref in
   `marketplace.json` rather than an implicit default branch.
7. **`--mode consumer` is decorative** and `--mode contributor` is fork-hostile
   (remote precheck) and dotfiles-shaped (`$HOME/dotfiles/claude/skills`).
   Document `GF_TARGET_DIR` / `GF_SKIP_REPO_PRECHECK`, or auto-detect the skills
   dir (`$CLAUDE_CONFIG_DIR/skills`, `~/.claude/skills`).
8. **Undisclosed blocking hook** on install.
9. **macOS untested** (bash 3.2, no flock/timeout/realpath).
10. **Version string incoherence** (SHA vs 0.1.0 vs 3.0.0).
11. **Privacy inversion** undocumented — users don't know the child skills are
    directly invocable, or that they may auto-trigger.
12. **Undeclared `idea`/`autopilot` couplings** with no degrade path in
    `relations.yaml`.
13. **CONTRIBUTING.md documents the wrong tree.** Its "Plugin shape" section
    tells contributors to edit `plugins/<name>/skills/<skill>/SKILL.md`; README
    and ARCHITECTURE say `plugins/` is generated and must not be hand-edited
    (`--check` blocks it in pre-commit). A new contributor following CONTRIBUTING
    will have their commit rejected.

---

## 4. DRAFT — `INSTALL.md`

> Suggested location: repo root (`/home/cunger/10_projects/cogwright/INSTALL.md`),
> linked from README §Quickstart. Written for someone who is not the author.
> The "Known limitations" section is deliberately included so the doc is honest
> today; delete those entries as the gaps in §3 are closed.

````markdown
# Installing cogwright plugins

This guide covers installing **goalforge** (and the other plugins in this
marketplace) on your own machine. You do not need to be a cogwright contributor
to follow it.

Two routes:

- **[Plugin route](#plugin-route-recommended)** — the normal path. Claude Code
  manages the clone and updates for you.
- **[Manual route](#manual-route)** — clone the repo and point your Claude Code
  skills directory at it. Use this if you want to modify goalforge, pin a
  specific commit, or run it without the plugin system.

---

## Prerequisites

goalforge is a set of skills plus ~35 shell/Python scripts. The skills load
without anything installed, but the scripts — which the chain calls for
validation, status, frontier computation, and state transitions — need the
following on your `PATH`.

### Required

| Tool | Why | Check |
|---|---|---|
| Claude Code | host | `claude --version` |
| `git` ≥ 2.30 | plan state, transitions, hooks | `git --version` |
| `bash` ≥ 4.0 | associative arrays, `mapfile` | `bash --version` |
| `python3` ≥ 3.9 | validation, plan index, trace tooling | `python3 --version` |
| **PyYAML** | every frontmatter parser | `python3 -c "import yaml; print(yaml.__version__)"` |
| **`jq`** ≥ 1.6 | ~90 script call sites; the single-writer hook silently disables itself without it | `jq --version` |
| `flock` | concurrency lock on status transitions | `command -v flock` |
| `timeout` | dispatch timeouts | `command -v timeout` |
| `realpath` | path resolution | `command -v realpath` |
| `tar`, `diff`, `sed`, `awk` | installer + drift checks | POSIX baseline |

### Optional

| Tool | Improves |
|---|---|
| `ripgrep` (`rg`) | faster migration/rewire sweeps (falls back to `grep`) |
| `gh` | GitHub operations from chain skills |

### Platform notes

**Linux (Debian/Ubuntu)**

```bash
sudo apt-get install -y git jq python3 python3-pip util-linux coreutils
pip3 install --user pyyaml
```

**Fedora/RHEL**

```bash
sudo dnf install -y git jq python3 python3-pip util-linux coreutils
pip3 install --user pyyaml
```

**macOS** — the stock system ships bash 3.2 and lacks `flock`, `timeout`, and
`realpath`. goalforge is **not currently tested on macOS**; install the GNU
toolchain first and expect rough edges:

```bash
brew install bash jq python3 coreutils util-linux
pip3 install pyyaml
# ensure Homebrew bash and gnubin are ahead of /usr/bin on your PATH
```

**Windows** — use WSL2 and follow the Linux instructions. Native Windows is not
supported.

### Verify prerequisites in one shot

```bash
for c in git bash python3 jq flock timeout realpath tar; do
  command -v "$c" >/dev/null && echo "ok   $c" || echo "MISS $c"
done
python3 -c "import yaml" 2>/dev/null && echo "ok   PyYAML" || echo "MISS PyYAML"
bash -c '((BASH_VERSINFO[0]>=4))' && echo "ok   bash>=4" || echo "MISS bash>=4"
```

Every line should read `ok`.

---

## Plugin route (recommended)

Inside Claude Code:

```
/plugin marketplace add Truncuso/cogwright
/plugin install goalforge@cogwright
```

Restart Claude Code (or start a new session) so skills, commands, and hooks are
picked up.

### What this installs

The marketplace is cloned to `~/.claude/plugins/marketplaces/cogwright/`. After
installing `goalforge` you have:

| Surface | What you get |
|---|---|
| **Skills** | `goalforge` (front door) plus 18 skills: the 15 chain stages (`goalforge-capture`, `-spec`, `-decompose`, `-harden`, `-interview`, `-execute`, `-verify`, `-redecompose`, `-archive`, `-recap`, `-onboard`, `-watchdog`, `-plan-index`, `-arbiter`, `-run`), `goalforge-brief`, plus the co-tenants `wayfind` and `prototype` |
| **Commands** | `/wayfind` |
| **Hooks** | one `PreToolUse` guard — see [Hooks installed](#hooks-installed) |
| **Scripts** | `${CLAUDE_PLUGIN_ROOT}/scripts/goalforge-*.sh` (validation, status, transitions, frontier, rollup, archive) |
| **References** | schemas, state machine, templates, tier map, specialist map |

Nothing is written outside `~/.claude/plugins/`. Your shell profile, dotfiles,
and existing skills are untouched.

### Where your plans live

goalforge writes plan state to a **PLANS_ROOT**, resolved in this order:

1. `$SDD_PLANS_DIR` if set
2. `<git-root>/plans/` — the repo you are working in (normal case)
3. `~/.claude/plans/` — global fallback when you are not in a repo

Feature layout is flat: `plans/<feature>/<wp>/`, with status in frontmatter.
There are no lifecycle folders to maintain.

### Updating

```
/plugin marketplace update cogwright
```

### Installing the other plugins

```
/plugin install interview@cogwright
```

Each plugin is self-contained — installing one never requires another. Declared
companions degrade gracefully (a missing `interview-loop` falls back to a
one-question-at-a-time loop in the main session, not an error).

---

## Manual route

Use this if you want to edit goalforge, pin a commit, or run without the plugin
system.

### 1. Clone

```bash
git clone https://github.com/Truncuso/cogwright.git ~/src/cogwright
cd ~/src/cogwright
```

To pin a known-good revision:

```bash
git checkout <commit-or-tag>
```

### 2. Point your skills directory at the package

The authored source of truth is `packages/goalforge/` (the nested v2 package).
`plugins/goalforge/` is a *generated* flattened artifact — do not edit it.

Symlink the package into your Claude Code skills directory:

```bash
SKILLS="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/skills"
mkdir -p "$SKILLS"
ln -s ~/src/cogwright/packages/goalforge "$SKILLS/goalforge"
ln -s ~/src/cogwright/packages/goalforge/prototype "$SKILLS/prototype"
ln -s ~/src/cogwright/packages/goalforge/wayfind   "$SKILLS/wayfind"
```

`interview/` is intentionally not linked at the top level — it is a private
child invoked by `goalforge-harden`.

### 3. Or use the bundled installer

`scripts/install.sh` automates step 2 with pre/post-verification, drift refusal,
and idempotent re-runs. It defaults to the maintainer's layout, so override the
two env vars for your own machine:

```bash
GF_TARGET_DIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/skills/goalforge" \
GF_SKIP_REPO_PRECHECK=1 \
  bash scripts/install.sh --mode contributor --dry-run   # preview
```

Drop `--dry-run` to apply.

| Variable | Purpose | Default |
|---|---|---|
| `GF_TARGET_DIR` | where the `goalforge` symlink is created | `$HOME/dotfiles/claude/skills/goalforge` |
| `GF_LINK_TARGET` | what it points at | `<repo>/packages/goalforge` |
| `GF_SKIP_REPO_PRECHECK` | set to `1` to skip the origin-remote and clean-checkout gates | `0` |

`GF_SKIP_REPO_PRECHECK=1` is **required if you cloned a fork** — the default
precheck only accepts an `origin` matching `github.com/Truncuso/cogwright`.

Installer behavior worth knowing:

- **Idempotent.** Re-running on a correct install is a no-op (exit 0).
- **Repairs** a wrong-target or dangling symlink.
- **Refuses to clobber.** An existing real directory with content differing from
  the package is refused rather than overwritten (transients like
  `__pycache__/` and `evals/workspace/` are ignored).
- **Backs up before swapping.** Replaced directories are tarred to a scratch
  path, printed on stderr, and restored automatically if post-verification fails.

Sanity-check the installer itself — it runs 8 cases in a sandbox and never
touches your real `$HOME`:

```bash
bash scripts/install.sh --self-test
```

### 4. Optional: the git pre-commit validator

goalforge ships a pre-commit hook that blocks a commit leaving a touched feature
with a `goalforge-validate --strict` error. Install it into a project repo:

```bash
cd /path/to/your/project
GOALFORGE_VALIDATE_SCRIPT="$HOME/src/cogwright/packages/goalforge/scripts/goalforge-validate.sh" \
  bash ~/src/cogwright/packages/goalforge/scripts/goalforge-install-hooks.sh .
```

It is chain-safe: an existing `pre-commit` hook is appended to inside
`# >>> sdd-pre-commit >>>` markers, never overwritten, and it exits 0 on every
error path so it can't break your commit flow.

---

## Hooks installed

Installing the goalforge **plugin** activates one hook automatically:

**`goalforge-single-writer` (PreToolUse, matcher `Edit|Write|MultiEdit`)** —
blocks direct tool-surface edits to the `status:` and `goal_approved_version:`
frontmatter fields in `<git-root>/plans/**` and `~/.claude/plans/**` (files named
`overview.md`, `spec.md`, `task-*.md`). Those fields have a single sanctioned
writer, `goalforge-transition.sh`.

- Creating a new plan file with an initial `status:` is **allowed** — the guard
  only protects existing values.
- Files outside a `plans/` root are never touched.
- Without `jq` on `PATH` the hook allows everything through silently. Install
  `jq`.

To change a status, use the chain (`/verify`, the stage skills) or call
`goalforge-transition.sh` directly — do not hand-edit.

---

## Verify the install

### 1. Skills are discoverable

In Claude Code:

```
explain goalforge
```

The `goalforge` front-door skill should load and list the chain stages. Also try
`/wayfind` — it should be recognised as a command.

### 2. Scripts run

```bash
GF="$HOME/.claude/plugins/marketplaces/cogwright/plugins/goalforge"   # plugin route
# GF="$HOME/src/cogwright/packages/goalforge"                          # manual route

bash "$GF/scripts/goalforge-validate.sh" --help
```

Expected: usage output. If you see
`ERROR: PyYAML not available` → `pip3 install pyyaml`.

### 3. End-to-end smoke test on a throwaway repo

```bash
mkdir -p /tmp/gf-smoke && cd /tmp/gf-smoke && git init -q
mkdir -p plans/demo-feature/wp-01-demo
cat > plans/demo-feature/wp-01-demo/overview.md <<'EOF'
---
name: wp-01-demo
title: "Smoke test work package"
status: draft
schema_version: 5
plan: demo-feature
task_type: code
---
## Goal
Confirm goalforge validation runs.
EOF

bash "$GF/scripts/goalforge-validate.sh" plans
bash "$GF/scripts/goalforge-status.sh"   plans
```

Expected: both commands complete and report on `demo-feature`. Validation
warnings about missing fields are fine — a crash or an import error is not.

Clean up: `rm -rf /tmp/gf-smoke`.

### 4. The single-writer hook is live (plugin route)

Ask Claude to edit the `status:` line of
`/tmp/gf-smoke/plans/demo-feature/wp-01-demo/overview.md` with the Edit tool. The
attempt should be blocked with a single-writer message. If it succeeds, check
that `jq` is installed and that the plugin's hooks were loaded (restart Claude
Code).

---

## Uninstall

### Plugin route

```
/plugin uninstall goalforge@cogwright
/plugin marketplace remove cogwright
```

This removes the skills, the `/wayfind` command, and the PreToolUse hook. Your
`plans/` directories are **not** touched — they are your content.

### Manual route

```bash
SKILLS="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/skills"
rm -f "$SKILLS/goalforge" "$SKILLS/prototype" "$SKILLS/wayfind"   # symlinks only
rm -rf ~/src/cogwright                                            # the clone
```

`rm -f` on a symlink removes the link, never the target. Confirm with
`ls -l "$SKILLS"` before deleting anything that is not a symlink.

### Remove the git pre-commit hook

The installer appends a marked block. Delete the lines between and including:

```
# >>> sdd-pre-commit >>>
# <<< sdd-pre-commit <<<
```

in `<your-repo>/.git/hooks/pre-commit`. If that block is the entire file, delete
the file.

### Leftovers to check

```bash
ls ~/.claude/plugins/marketplaces/cogwright   # should not exist after removal
grep -rn 'sdd-pre-commit' .git/hooks/ 2>/dev/null
```

---

## Troubleshooting

| Symptom | Cause | Fix |
|---|---|---|
| `ERROR: PyYAML not available` | missing PyYAML | `pip3 install pyyaml` (match the `python3` on your PATH) |
| Script exits with no output / `jq: command not found` | missing `jq` | install `jq` |
| `flock: command not found` (macOS) | util-linux missing | `brew install util-linux` and put it ahead of `/usr/bin` |
| `declare -A: invalid option` (macOS) | bash 3.2 | `brew install bash`, put it first on `PATH` |
| `refusing to clobber: real dir has uncommitted tracked drift` | your skills dir has a real `goalforge/` directory that differs from the package | commit/revert/move it, then re-run |
| `unexpected origin remote` | you cloned a fork | `GF_SKIP_REPO_PRECHECK=1` |
| `link target does not resolve to a goalforge package` | wrong `GF_LINK_TARGET`, or clone incomplete | point at `<repo>/packages/goalforge` |
| A skill references `~/.claude/skills/goalforge/...` and the file is missing | known path-leak bug, see below | read the same relative path under `${CLAUDE_PLUGIN_ROOT}` instead |
| `/spec`, `/plan`, `/implement`, `/verify` are unknown commands | not shipped yet, see below | invoke the skills by name |

---

## Known limitations (current release)

Stated plainly so you are not debugging a documented gap:

1. **Only `/wayfind` ships as a command.** The `/spec`, `/plan`, `/implement`,
   and `/verify` entry points described in the README and ARCHITECTURE docs are
   not yet part of the plugin. Until they are, drive the chain by invoking the
   skills directly by name — `goalforge-capture`, `goalforge-spec`,
   `goalforge-decompose`, `goalforge-harden`, `goalforge-execute`,
   `goalforge-verify` — or ask the `goalforge-run` orchestrator to drive it.
2. **Some skill text points at `~/.claude/skills/goalforge/...`.** Those are
   leftover maintainer-machine paths. The same file exists under
   `${CLAUDE_PLUGIN_ROOT}/` — for a child skill's own assets, under
   `${CLAUDE_PLUGIN_ROOT}/skills/<child>/`. Scripts referenced this way are all
   present in `${CLAUDE_PLUGIN_ROOT}/scripts/`.
3. **A few references reach into skills that are not part of this marketplace**
   (`idea`, `autopilot`). Those sections degrade — treat them as optional.
4. **Child skills are individually discoverable.** In the package they are
   private children of the `goalforge` front door; flattened into a plugin they
   become top-level skills and may trigger on their own.
5. **`evals/` is not shipped.** The plugin artifact excludes the eval harness, so
   there is no bundled acceptance test. Use the smoke test above, or clone the
   repo and run evals from `packages/goalforge/evals/`.
6. **macOS is untested.** See the platform notes.
7. **Version strings disagree** — `plugin.json` carries a commit SHA, the README
   catalog says v0.1.0, and the skill frontmatter says 3.0.0. The commit SHA in
   `plugin.json` is the reliable identifier of what you installed.

Bug reports and PRs welcome: <https://github.com/Truncuso/cogwright/issues>.
See [CONTRIBUTING.md](CONTRIBUTING.md) — note that `packages/` is the authored
tree and `plugins/` is generated by `scripts/goalforge-generate.sh`; edit
`packages/`, then regenerate.
````

---

## Recommended follow-up work packages

If the goal is a genuinely clean external install, in dependency order:

1. **`wp-commands-export`** — author `/spec`, `/plan`, `/implement`, `/verify` in
   `plugins/goalforge/commands/`, `${CLAUDE_PLUGIN_ROOT}`-addressed, with the
   dotfiles copies flagged as downstream mirrors (same MIRROR-SYNC convention
   `commands/wayfind.md` already uses).
2. **`wp-path-class-viii`** — extend the generator's rewrite table with
   `~/.claude/skills/goalforge/` → `${CLAUDE_PLUGIN_ROOT}/` (with `<child>/` →
   `skills/<child>/`), and add a symmetric lint so `~/.claude` cannot re-enter
   `plugins/`. Deterministic verification: `grep -rc '~/\.claude/skills/goalforge'
   plugins/ == 0`.
3. **`wp-preflight`** — a shipped `${CLAUDE_PLUGIN_ROOT}/scripts/goalforge-doctor.sh`
   that checks every dependency in the prerequisites table and exits non-zero on
   a missing hard dep. Also gives INSTALL.md a one-command verification step.
4. **`wp-install-md`** — land the draft above, trim README §Installing to a
   pointer, and fix the CONTRIBUTING.md `packages/` vs `plugins/` contradiction.
5. **`wp-release-discipline`** — push `main`, tag a release, and pin
   `marketplace.json` to a ref rather than an implicit default branch.



---

# 5. Chain design review — duplication, state machine, complexity

The goalforge chain is 31,665 lines across 312 files in `/home/cunger/10_projects/cogwright/packages/goalforge/`, and it carries a near-complete second copy of itself at `/home/cunger/10_projects/cogwright/plugins/goalforge/` (22,464 lines) that has already drifted on four files — the largest single duplication in the system, and the reason a load-bearing hard guardrail (`goalforge-single-writer.sh`) now exists in three versions of which the newest is the one *not* wired. The state machine is no longer coherent: the feature enum declares six states but no skill or script writes `spec` or `active` (only test fixtures do), which makes 18 of 30 hand-written feature edge rows unreachable, makes `verify/SKILL.md`'s "holds the feature at `active`" an impossible instruction, and makes the package's own eval #2 contradict `chain.yaml`. The route enum is drifted three ways — schema declares `one-go|fast|standard|wave`, `goalforge-route.sh` emits only `fast|standard|wave` and normalizes `one-go`→`fast` as legacy, while `capture/SKILL.md` (the declared "routing home") still documents and branches on the retired `fast|full` pair. The biggest vestigial subsystem is the orchestrator itself: `run/SKILL.md`'s own last gotcha states the four entry commands bypass `goalforge-run` entirely, contradicting the package `SKILL.md`, so ~600 lines of orchestrator have no production caller. Roughly 330 of the eval assertions are `grep -qF` checks for literal sentences in SKILL.md prose — tautological by construction, and the direct causal driver of the 4,619 lines of SKILL.md verbosity, because no sentence can be tightened without breaking a test. Complexity has outrun the chain's own measured evidence: `decompose/SKILL.md` records 106 WPs at `spec` against 3 executing and 57% of a month's commits spent on coordination surfaces, and the response since has been to add Tier-1/Tier-2 audits, a panel protocol, a dissent ledger, an assumption-recheck substrate, a brief-staleness stage and a ~2,200-line trace substrate that has one producer and no in-chain consumer. Two core scripts (`goalforge-validate.sh` 1,934 lines, `goalforge-transition.sh` 1,123 lines with 11 separate `python3` spawns per status write) are Python programs wearing a bash costume, in direct violation of the repo's own coding-style rule. Realistic net removable: ~24,000 lines, of which ~22,500 is the duplicate tree and ~1,500 is genuine dead/derivable weight inside the package.

---

# Deep design review — goalforge chain

**Target:** `/home/cunger/10_projects/cogwright/packages/goalforge/`
**Scale:** 312 files, 31,665 lines — 4,619 lines of `SKILL.md` prose (18 skills), 3,564 lines of `references/`, 12,679 lines of `scripts/`, 6,139 lines of `evals/`.

**Method:** read the parent `SKILL.md`, `README.md`, all 18 child `SKILL.md`s, all 8 named references plus the harden/execute/decompose/capture sub-references, `run/chain.yaml`; built a full script→consumer reference graph across both package trees and the dotfiles tree; structurally skimmed the 30+ scripts (shape, flags, signal vocabularies, subprocess counts) rather than line-by-line. Behavioral claims about script internals are marked where they rest on structure rather than execution.

---

## 1. DUPLICATION

### D1 — Two full copies of the package, already drifted *(CRITICAL)*

`/home/cunger/10_projects/cogwright/packages/goalforge/` (31,665 lines) and `/home/cunger/10_projects/cogwright/plugins/goalforge/` (22,464 lines) are the same system. `diff -rq` shows `scripts/` and most of `references/` byte-identical; the child skills live at `plugins/goalforge/skills/<name>/` vs `packages/goalforge/<name>/`.

Four files have already diverged — the `interview-loop` → `interview` plugin rename landed in `packages/` only:

| File | packages/ | plugins/ |
|---|---|---|
| `references/schema.md:90` | "the `interview` plugin engine" | "the global `interview-loop` engine" |
| `references/fidelity.md:16,49,71` | `interview` plugin | `interview-loop` |
| `SKILL.md:44` | interview plugin engine | global interview-loop |
| `README.md:23,59` | `interview` (plugin) | `interview-loop` |

This is not cosmetic: `/home/cunger/.claude/skills/interview-loop/` still exists as a live skill alongside the `interview:` plugin, so the two copies name **two different engines** for the same delegation.

Worse, `hooks/goalforge-single-writer.sh` — the wp-08 hard guardrail `execute/SKILL.md` Step 2b explicitly depends on ("the wp-08 single-writer hook permits [the Bash path] while it BLOCKS an Edit-tool status write") — exists in **three** states:

- `/home/cunger/dotfiles/claude/hooks/goalforge-single-writer.sh` (22,545 B) — the one actually wired, per `settings.json:276`
- `/home/cunger/10_projects/cogwright/plugins/goalforge/hooks/goalforge-single-writer.sh` (21,593 B) — **22 lines different**; missing the `brief-immutable` block that blocks Edit/Write on an existing `brief-task-*.md`
- `/home/cunger/10_projects/cogwright/packages/goalforge/hooks/` — **does not contain it at all**

So the tree declared "the LOCAL, authoritative source of truth" (`SKILL.md:27-30`) does not own the guardrail its own execute stage depends on, and the *newer* copy is the one not running.

### D2 — `state-machine.md` hand-writes 59 rows it derives in prose

`/home/cunger/10_projects/cogwright/packages/goalforge/references/state-machine.md` states the derivation rule at lines 23-27 ("Forward edge: legal, `reason_required: no`. Reverse edge: legal, `reason_required: yes`") and then hand-writes all 29 WP edges (lines 72-103) and all 30 feature edges (lines 148-179). The only non-derivable content is two named exceptions (signal-scoped auto-advance on `hardened→ready`; evidence-gated `ready→hardened`) and two `human_gated` flags.

The rows are load-bearing — `goalforge-transition.sh:239-264` parses the `## Edges` markdown tables at runtime — but the package already solved this exact problem correctly elsewhere: `references/tier-map.md:1-5` is a **generated projection** of `ROLE_TIER` with a `--test-tiers` drift-check eval. Two identical problems, two different treatments.

### D3 — `## Plans root` restated in 8 skills

`capture`, `spec`, `decompose`, `harden`, `verify`, `archive`, `wayfind`, `run` each carry a `## Plans root` block restating "env `SDD_PLANS_DIR` → project git-root `plans/` → global `~/.claude/plans/`" — *and each block cites* `references/schema.md` §PLANS_ROOT resolution in the same breath. The pointer is there; the copy alongside it is pure redundancy (~48 lines).

### D4 — `## Unattended mode` restated in 6 skills

`spec`, `harden`, `verify`, `execute`, `archive`, `run` each carry a near-identical `SDD_AUTONOMY=unattended` section restating the PARK-don't-block rule and pointing at `~/.claude/skills/autopilot/references/autonomy-policy.md`. `execute/references/autonomy.md` (19 lines) is the only one that is *just* a pointer — the pattern that should have been applied to all six (~60 lines).

### D5 — `fidelity.md` repeats the same trailing clause six times

`references/fidelity.md:47-52`: every row of the per-stage routing table ends with the identical `— spike spec: ~/.claude/skills/goalforge/prototype/references/spike-spec.md`. One footnote, six copies.

### D6 — Dispatch knowledge split across three files that each disclaim duplicating the others

- `references/tier-map.md` — generated projection of `ROLE_TIER`
- `references/dispatch-template.md:3-9` — "This file carries **strictly net-new** content… that content is **referenced, never duplicated here**"
- `execute/references/dispatch-resolution.md` §Model tier + effort

The disclaimers are the tell. `dispatch-resolution.md:52-54` still restates `low → sonnet@low, medium → opus@low, high → opus@high`, which is exactly what `tier-map.md:15-17` states. Three files, one fact, three restatements of "don't restate this".

### D7 — The coverage/facet rule is stated three times

`references/schema.md:494-505` ("Coverage rule" + "Facet-coverage self-check"), `decompose/SKILL.md:232-238` ("Coverage rule") **and** `decompose/SKILL.md:270-274` (Step 7b.6 "Facet coverage") — i.e. twice within one file — plus `harden/SKILL.md:241-261` ("Goal-facet completeness"). ~40 lines of near-verbatim restatement.

### D8 — `plans/INDEX.md` has two generators

`plan-index/SKILL.md:33-35` admits it: "default writes `<PLANS_ROOT>/INDEX.md` — which project-track-sweep's `backfill_wps.py` also generates… pass `-o` to avoid clobbering a sweep-generated index." One artifact, two writers, no declared owner, and the workaround is a flag.

### D9 — `SKILL.md` and `README.md` are two competing package indexes

`/packages/goalforge/SKILL.md` and `/packages/goalforge/README.md` both carry a children table, a chain diagram, a shared-references table and a status machine — and they contradict each other on two guardrail facts (see Q1 and Q6).

---

## 2. DESIGN QUALITY

### Q1 — Contradictory statements about which transition is human-gated

| Site | Claim |
|---|---|
| `README.md:51` | "`draft → spec` and `hardened → ready` are human-gated" |
| `spec/SKILL.md:235` (§Human-gate rationale) | "`draft → spec` is one of two human-gated transitions" |
| `spec/SKILL.md` Step 3 + Outputs table | gates `draft → ready` |
| `spec/SKILL.md:257` (Gotchas) | "advancing OUT of `draft` (to `ready`)" — correct |
| `references/state-machine.md:139` | `draft→ready` and `spec→ready` carry `human_gated: yes` |
| `references/schema.md:98` | "`draft → ready` (feature gate)… are the two human-gated transitions" |

`spec/SKILL.md` contradicts itself in two places within one file, on a guardrail statement. `draft → spec` is not human-gated in any machine-parsed table.

### Q2 — Vestigial feature states `spec` and `active`

No skill and no script writes feature `status: active` or feature `status: spec`. A grep across the package finds them only in `scripts/goalforge-validate.sh:300` (self-test fixture) and three test files. `references/schema.md:116` admits it outright: `# active: reserved-for-future (no skill writes it yet; sdd-lifecycle-redesign)`.

The actual feature path is `draft` (capture) → `ready` (spec) → `completed` (verify last-WP rule) → `archived` (archive). Four reachable states, six declared. Consequences:

- **18 of 30 feature edge rows** in `state-machine.md:148-179` have `spec` or `active` as an endpoint and are unreachable.
- `verify/SKILL.md:182`: "a blocking finding holds the feature at `active` (do not advance to `completed`)" — an instruction to hold at a state nothing can set. The feature will actually sit at `ready`.
- `archive/SKILL.md` refusal template lists `active` among offending statuses.
- `evals/evals.json` eval #2 asks about "a feature where `overview.md` has `status: spec`" and expects `goalforge-decompose` — but `run/chain.yaml:36-38` requires feature `status: ready` for decompose. **The eval's ground truth contradicts the chain.**

### Q3 — Route enum drifted three ways; the "routing home" documents a retired vocabulary

| Source | Enum |
|---|---|
| `references/schema.md:152-159`, `run/SKILL.md:37` | `one-go \| fast \| standard \| wave` (canonical) |
| `scripts/goalforge-route.sh:5,65-68` | emits `fast \| standard \| wave`; `full` **and** `one-go` are LEGACY, normalized on read (`full→standard`, `one-go→fast`) |
| `capture/SKILL.md:136` | documents the script output as `{"route":"fast"\|"full"}` |

`capture/SKILL.md` is declared "the routing home" (Step 4c) and branches on `full` four separate times — Step 4c confidence rules, Step 5 report line (`route: <fast\|full>`), fast-path step 1 re-route, and its own Gotchas. `spec/SKILL.md:27` and `decompose/SKILL.md:438` also say `route: full`. The stage that stamps the value documents a vocabulary the classifier retired.

### Q4 — `one-go` is vocabulary-only

`references/schema.md:156` gives `one-go` distinct semantics ("Smallest unit — reuses fast-path 1-WP mechanics with a single dispatch"). The classifier normalizes it away. `chain.yaml` has no `when_route: one-go`. No skill branches on it. A four-value enum documented, three implemented.

The `wave` route is a weaker version of the same problem: `run/SKILL.md:57-148` describes a four-stage choreography, but `chain.yaml` carries no wave steps, and `run/SKILL.md:135-148` defers two of its six documented stages as "documented but not wired… Do not add these to `execution_plan.steps` or assert them in fixtures until the first real wave run motivates them."

### Q5 — The orchestrator has no production caller *(largest vestigial subsystem)*

`run/SKILL.md:281`, its own last gotcha:

> The entry commands (`/spec`, `/plan`, `/implement`, `/verify`) call their child skills **directly** (e.g. `commands/spec.md` → `goalforge-capture`/`goalforge-spec`) — they do NOT route through `goalforge-run`, so its resume + gate logic is bypassed when you use the slash commands.

The package `SKILL.md:67-68` asserts the opposite: "`/spec`, `/plan`, `/implement`, `/verify` are the human entry points; they drive the chain via the `goalforge-run` orchestrator." So `run/SKILL.md` (281 lines) + `chain.yaml` (80) + `run/scripts/goalforge-router.sh` + `run/scripts/goalforge-plan-consumer.sh` (228) + `run/evals/` (140) ≈ **600–800 lines of orchestration that nothing invokes**, including the route-awareness, the resume table, the `--dry-run` mode and the wave choreography.

This also means the route machinery of Q3/Q4 is doubly dead: the classifier stamps a value that only the un-invoked orchestrator reads.

### Q6 — sdd→goalforge migration residue

- `SKILL.md:78-85` §Alias layer: "The legacy `sdd-*` skills and `sdd-*.sh` scripts **remain in place** as LOCAL-pointing aliases… Deletion of the `sdd-*` sources is deferred behind a separate human sign-off gate."
- `README.md:13`: "the legacy `sdd-*` aliases **were retired** 2026-07-21."

Direct contradiction. And `SKILL.md:82` carries a botched rename from the migration sed: *"with one script rename: `goalforge-route.sh` → `goalforge-route.sh`"* — identical on both sides, because the sed rewrote both halves of `sdd-goal-route.sh → goalforge-route.sh`.

`references/alias-map.md` (83 lines) is entirely vestigial: it maps to `$COGWRIGHT_ROOT/plugins/goalforge/skills/…`, a layout matching neither tree, and references "task-02"/"task-04 rewire" that completed. It is also the **sole remaining reference** for several scripts — deleting it would immediately expose which scripts are truly orphaned (see C4).

Residual `sdd-` tokens across the tree: 12× `sdd-pre-commit`, 5× `sdd-verification-integrity-gaps`, plus ~40 scattered `sdd-<stage>` mentions in `schema.md`, `execute/SKILL.md`, `redecompose/SKILL.md`, `watchdog/SKILL.md`, `onboard/SKILL.md` and 8 scripts.

### Q7 — The schema doc annotates its own version confusion instead of fixing it

`references/schema.md:1` says "Schema version: **3**". Lines 10-41 then spend **32 lines** explaining that this doesn't mean what it says: that the goal layer is v4, that v5 is a per-plan opt-in marker, and that three distinct "version" concepts (doc revision / plan opt-in marker / template marker) must not be conflated. A 32-line disambiguation section is a symptom — the header is wrong and should be corrected.

### Q8 — `redecompose` contradicts the schema on supersession and WP archival

- `redecompose/SKILL.md:99` instructs writing `superseded_by: "<reason or new-slug>"` into **WP** frontmatter. `references/schema.md:203-205` forbids the concept at WP level: *"there is NO `superseded` WP status — supersession is expressed by the `superseded_by` relationship edge (feature-level); adding a WP status here would double-own the concept."* And `schema.md:349` requires `[[wikilink]]` form, not a free-text reason string.
- `redecompose/SKILL.md:105`: "A dropped WP that is **not** verified can be archived normally (rename to `_archived-<slug>/`)." That is a **third** archive layout — `capture/SKILL.md:58` probes `_archived/<feature>/`, `archive/SKILL.md` moves to `_archived/<feature>/`. And `state-machine.md:61-68` states plainly that no goalforge script writes `archived` to a WP.

### Q9 — The evals are grep-on-prose *(root cause of the verbosity)*

~330 assertions across the 17 `evals/run.sh` files are `grep -qF "<literal sentence>" SKILL.md`. Counts: `execute` 72, `prototype` 34, `archive` 29, `verify` 29, `decompose` 28, `harden` 27, `arbiter` 26, `capture` 19, `watchdog` 19, `recap` 14, `redecompose` 10, `spec` 10, `plan-index` 7.

Example, `harden/evals/run.sh:57`:
```bash
check 'engine repointed to the interview plugin' 'the `interview` plugin engine'
```

Three consequences:

1. **Tautological.** They can only fail when the prose is reworded, never when behavior is wrong — the anti-pattern `rules/common/testing.md` names explicitly ("expected values from an independent source of truth").
2. **They freeze the prose.** This is the direct causal driver of the 4,619 lines of SKILL.md: a sentence cannot be tightened without breaking a test, so every clarification is *added* rather than substituted. It explains the accretive, self-referential register throughout (`harden/SKILL.md` is 531 lines with a 14-bullet Gotchas section).
3. **They now contort around the guardrails.** `harden/evals/run.sh:11-15` documents a workaround: the eval must split `status:` from its enum value into `SK="status:"` so the single-writer hook's literal grep does not false-match the test's own assertions.

Real behavioral coverage is thin: `scripts/tests/` holds only **5** test files for 30+ scripts (`goalforge-validate`, `goalforge-archive`, `goalforge-archived-collision`, `goalforge-prototype-retain`, `goalforge-transition-evidence`, plus one pytest for archive-sweep).

### Q10 — Two skills ship no evals

`interview/` and `brief/` have no `evals/` directory, against `rules/common/skill-development.md` ("every skill ships a deterministic `evals/` harness").

### Q11 — The package boundary has dissolved

Per `SKILL.md:70-76` and `README.md:35-36`, the package contains:

- 15 declared chain children — but `goalforge-archive` is "**NOT** wired into `chain.yaml`" (`archive/SKILL.md:202`)
- `prototype/` and `wayfind/` — "non-chain tenants co-located in this package (not chain stages)", with their own top-level installer symlinks
- `brief/` — "a chain-support asset — not a chain stage (no status edge) and not a co-tenant (no top-level symlink)"
- `interview/` — a 70-line private wrapper whose entire net content is four procedure steps around an external engine
- `workflow-authoring/` (628 lines of `scripts/distill` + `scripts/render`) — **not mentioned in `SKILL.md`, not in `README.md`, not in the children table, no SKILL.md of its own**

Four different membership categories plus an undeclared fifth. The boundary has become "things that were near goalforge when they were written."

---

## 3. COMPLEXITY

### C1 — Two core scripts violate the repo's own coding-style rule

| Script | Lines | Shape |
|---|---|---|
| `scripts/goalforge-validate.sh` | **1,934** | ~1,195 lines are a single embedded Python heredoc (`<<'PYEOF'` at line 745); ~739 lines of bash wrapper and self-test fixtures |
| `scripts/goalforge-transition.sh` | **1,123** | **11 separate `python3` subprocess spawns**, each a fresh interpreter with its own heredoc, for one status write |
| `scripts/recap.sh` | 640 | 7 `python3` spawns |

`rules/common/coding-style.md`: *"MANY SMALL FILES > FEW LARGE FILES… 200-400 lines typical, 800 max"* and *"Feature scripts, hooks, and prototypes default to cross-platform TypeScript or Python. Bash stays where genuinely better-suited: thin git-hook glue, POSIX plumbing, CLI orchestration, one-liners — a deliberate call, not the path of least resistance."*

These are Python programs wearing a bash costume. The 11-spawn transition is also the hot path — it runs on every status edge in the chain.

### C2 — Gate count has outrun the chain's own measured evidence

A standard-route WP now passes, before a line of code is written:

frontier gate (harden Step 0) → preharden lint (0a.0) → Tier-1 freshness hash (0a.1) → complexity route (0a.2) → Tier-2 delta **or** panel + dissent ledger → knowledge query (0b) → migration rewire scan (0c) → interview loop → arbiter (conditional) → goal-block validation (2.1) → open-questions gate (2.2) → signal-scoped auto-advance check (2.3) → mechanical premise inventory → goal-hash record → transition.

**14 gates.** Meanwhile `decompose/SKILL.md:26-35` records the chain's own diagnosis:

> Decompose-ahead builds a speculative WP buffer whose todo.md rollups, `depends_on` edges, and mirrored sequence entries drift before the work ever runs — measured 2026-07-16: **106 WPs at `spec` against 3 executing, and 57% of a month's commits spent on coordination surfaces.**

The system measured its coordination-overhead problem and then added Tier-1/Tier-2 audits, a panel protocol with a dissent ledger, an assumption-recheck substrate, a brief-authoring stage with git-blob + goal-hash staleness anchors, a re-harden evidence file format, and a trace-event substrate on top of it. The JIT rule (a soft "confirm before proceeding") is the only counter-pressure, and it is advisory.

Senior-practitioner test: for a WP whose complexity verdict is `simple`, severity `LOW`, non-migration — the case the signal-scoped auto-advance was built for — the chain still runs the frontier gate, preharden lint, Tier-1 hash recompute, complexity route, knowledge query, interview, goal validation and OQ gate before it can skip the human. That is a lot of machinery to arrive at "just do it."

### C3 — Three classifiers, one of which is a pure relabel

- `scripts/goalforge-route.sh` (288 lines) — signals R1–R5, feature → route
- `scripts/goalforge-wp-complexity.sh` (383 lines) — signals S1–S5, WP → `simple|complex`
- `scripts/goalforge-harden-route.sh` (156 lines) — **1:1 relabel** of wp-complexity's verdict: `complex→panel`, `simple→single-pass`, passing `tripped` through unchanged

The third is exactly the "shallow pass-through wrapper" `rules/common/coding-style.md` names. `harden/SKILL.md` Step 0a.2 could read `goalforge-wp-complexity.sh` directly and map two strings inline. ~145 net lines removable.

Two separate signal vocabularies (R1–R5 / S1–S5) for overlapping concepts (`R4` distinct path tokens ≈ `S3` distinct touched files; `R1` migration/ops task_type ≈ the `task_type ≠ migration` leg of the auto-advance rule) is a smaller but real duplication.

### C4 — Scripts whose only remaining reference is the vestigial migration doc

| Script | Lines | Non-alias-map references |
|---|---|---|
| `scripts/goalforge-goal-eval.sh` | 18 | **none** — body is `exec python3 goalforge-goal-eval.py "$@"`; every real caller imports the `.py` directly |
| `scripts/goalforge-hygiene.sh` | 93 | only `goalforge-archive-batch.sh` |
| `scripts/goalforge-archive-sweep.py` | 250 | only its own pytest |
| `scripts/goalforge-completed.sh` | ~? | only `goalforge-archive-batch.sh` + `goalforge-validate.sh` |

Deleting `references/alias-map.md` first is the cheap way to make this visible.

### C5 — Half-built subsystems shipped as if complete

- **`scripts/goalforge-learning-route.sh` (530 lines)** — `verify/SKILL.md:152`: *"The script does the deterministic plumbing only and emits the detection record to stdout; routing (tactical → `findings.md`, strategic → propose-only) and the `capture-learning` L1/L2/L3 invocation are **added in task-02**."* 530 lines run on every verify and route nothing.
- **Retrospective stage** — `references/retrospective.md:12`: the distiller is *"Owned by task-02."* Line 38: *"`dispatch-mismatch` is vocabulary-only until a `dispatch.*` producer lands."*
- **Wave route** — `run/SKILL.md:135-148`: two of six stages "documented but not wired."
- **Trace substrate ≈ 2,200 lines** — `references/trace-events.md` (558) + `scripts/goalforge-trace-emit` (447) + `goalforge-trace-derive` (385) + `goalforge-trace-read` (214) + `goalforge-retrospect` (354) + `goalforge-issue` (248). Exactly **one producer** (`goalforge-transition.sh`) and **no consumer inside the chain**. `trace-events.md:6-9` names its consumers as "goalforge-viz, the wp-15 retrospective stage, and wp-12 workflow-authoring" — one external tool and two future WPs.

Each of these is individually defensible as an in-progress WP. Collectively they mean a material fraction of the package is scaffolding for work that has not landed, indistinguishable from working code to a reader.

### C6 — The most externally-coupled script is the least documented

`scripts/goalforge-plan-index-json` (349 lines) has **zero** references anywhere inside `packages/goalforge/` — not in a SKILL.md, not in a reference, not in an eval. It is nonetheless consumed by:

- `/home/cunger/dotfiles/claude/tools/goalforge-viz/src/readPlanIndex.ts`
- `/home/cunger/dotfiles/claude/tools/goalforge-viz/app/src-tauri/src/refresh.rs`
- `/home/cunger/dotfiles/claude/tools/goalforge-viz/app/src-tauri/src/registry.rs`

The staging tree at `plans/goalforge/wp-13-local-rename/references/plugin-staging/evals/data-contract/run.sh` carried a contract eval for it; the `packages/` tree dropped it. The package's only cross-tool data contract is undeclared and untested.

---

## 4. Script inventory — load-bearing vs thin vs dead

Reference counts exclude `evals/`, `scripts/tests/`, and `references/alias-map.md` (vestigial).

**Load-bearing (leave alone, but see C1):** `goalforge-validate.sh` (21 consumers), `goalforge-transition.sh` (14), `goalforge-goal-hash.sh` (10), `goalforge-pick-agent.py` (13), `goalforge-rollup.sh` (11), `goalforge-wp-complexity.sh` (8), `goalforge-frontier.sh` (7), `goalforge-route.sh` (7), `goalforge-plan-index.py` (6), `recap.sh` (3), `goalforge-attribution.sh` (6), `goalforge-feature-hash.sh` (4), `goalforge-archive.sh` (3), `goalforge-ensure-committed.sh` (3), `goalforge-goal-eval.py` (4), `goalforge-stamp-tables.sh` (5), `goalforge-status.sh` (4).

**Thin/shallow wrapper:** `goalforge-harden-route.sh` (156 lines, 1:1 relabel), `goalforge-goal-eval.sh` (18 lines, `exec`).

**Half-built:** `goalforge-learning-route.sh` (530, routing unimplemented), `goalforge-retrospect` (354, distiller "owned by task-02").

**Producer-only, no in-chain consumer:** `goalforge-trace-emit` (447), `goalforge-trace-derive` (385), `goalforge-trace-read` (214), `goalforge-issue` (248).

**Orphan candidates:** `goalforge-archive-sweep.py` (250, own test only), `goalforge-hygiene.sh` (93), `goalforge-completed.sh`.

**Undeclared external contract:** `goalforge-plan-index-json` (349).

**Not in the package's own index at all:** `workflow-authoring/scripts/distill` (349), `workflow-authoring/scripts/render` (279).

---

## 5. Top 10 improvements, ranked by value / effort

**1. Stop committing `/plugins/goalforge/`; generate it from `packages/`.** *(value: highest / effort: low)*
It is already drifting on four files, and the drift is on a live delegation target (`interview-loop` vs `interview` plugin). Add a build step + a `diff -r` CI check, or make `plugins/goalforge/` a symlink farm. Net removable: **~22,464 lines**. Concurrently, move `goalforge-single-writer.sh` into `packages/goalforge/hooks/` as its single home and reconcile the 22-line divergence — a hard guardrail must not have three versions.

**2. Fix the human-gate contradiction.** *(highest / trivial)*
`README.md:51` and `spec/SKILL.md:235` both say `draft → spec` is human-gated; the machine-parsed tables say `draft → ready`. Three-line fix, but it is a false statement about a guardrail in the two most-read documents.

**3. Retire feature states `spec` and `active`.** *(high / low)*
Nothing writes them. Removing them deletes **18 of 30** feature edge rows, fixes `verify/SKILL.md:182`'s impossible "holds the feature at `active`", fixes `archive/SKILL.md`'s refusal template, and fixes `evals/evals.json` eval #2 whose expected answer contradicts `chain.yaml`. If `active` is genuinely wanted for the last-WP integration-review hold, then make `goalforge-verify` actually write it — but decide, don't leave it reserved-for-future in a shipped enum.

**4. Collapse the route vocabulary to what the classifier emits.** *(high / low)*
Pick one: either delete `one-go` from `schema.md:156` and `run/SKILL.md` (the classifier already treats it as legacy), or implement it. Then rewrite `capture/SKILL.md` Step 4c/Step 5/fast-path/Gotchas — plus `spec/SKILL.md:27` and `decompose/SKILL.md:438` — from `fast|full` to `fast|standard|wave`. The stage that stamps the value currently documents a retired vocabulary.

**5. Decide `goalforge-run`'s fate.** *(high / medium)*
Either wire `/spec /plan /implement /verify` through it (which is what the package `SKILL.md:67` claims) or delete `run/` and fold the resume table into the command files. Today it is ~600–800 lines of orchestrator, route-awareness, wave choreography and `--dry-run` with no production caller, and it is the reason the route machinery of items 3–4 is doubly dead. Deleting is the honest default; wiring is the right call only if the resume + gate logic is actually wanted.

**6. Delete `references/alias-map.md` and the `sdd-*` residue.** *(medium-high / low)*
83 lines describing a path layout that matches neither tree, plus the botched self-rename at `SKILL.md:82` (`goalforge-route.sh → goalforge-route.sh`) and the `SKILL.md` §Alias layer / `README.md:13` contradiction. Deleting it first also exposes the orphan scripts of C4 — do it before the script cull, not after.

**7. Generate `state-machine.md`'s edge tables.** *(medium-high / low-medium)*
Mirror the pattern `tier-map.md` already uses: declare the two orderings + the two named exceptions, generate the 59 rows, add a drift-check eval. Keeps `goalforge-transition.sh`'s markdown parser working unchanged while removing the hand-maintained source. Combined with item 3, ~65 derivable rows stop being hand-edited.

**8. Replace grep-on-prose evals with behavioral ones.** *(highest value / highest effort)*
~330 `grep -qF` assertions against SKILL.md sentences are tautological and are the mechanism keeping the prose at 4,619 lines. This is the root cause behind most of the duplication in §1 — a sentence cannot be replaced by a pointer while a test asserts the sentence. Concrete first step: for each skill, keep the fixture-driven checks (e.g. `archive/evals/fixtures/*`, `redecompose/evals/fixtures/*.json`, `capture/evals/fixtures/plans-archived-collision/`), delete the prose greps, and move contract assertions to `scripts/tests/` where they can run against behavior. Also add the missing `interview/evals/` and `brief/evals/`. Expect the SKILL.md files to shrink 30–50% once they are unfrozen.

**9. Split `goalforge-validate.sh` and `goalforge-transition.sh` into real Python modules.** *(medium-high / medium)*
1,934 and 1,123 lines respectively, the former ~62% a single Python heredoc, the latter spawning 11 interpreters per status write on the chain's hot path. Both exceed the repo's own 800-line ceiling by 40–140%. A `goalforge/validate/` package with one module per check family and a thin CLI is the same logic in files you can test individually — and `scripts/tests/` currently covers only 5 of 30+ scripts, which this would make tractable.

**10. Cull the thin and half-built layer; declare or delete the external contract.** *(medium / low)*
Delete `goalforge-harden-route.sh` (145 net lines, pure relabel — read the verdict directly in `harden/SKILL.md` Step 0a.2) and `goalforge-goal-eval.sh` (18 lines, `exec` shim). Land or remove `goalforge-learning-route.sh`'s unimplemented routing half (530 lines currently emitting to stdout on every verify). Confirm and delete `goalforge-archive-sweep.py` / `goalforge-hygiene.sh` if the item-6 deletion leaves them orphaned. Give `goalforge-plan-index-json` a documented consumer contract + the `evals/data-contract/` harness that the staging tree had, or delete it and let goalforge-viz read `goalforge-plan-index.py`. Separately: decide whether the ~2,200-line trace substrate stays — it has one producer and no in-chain consumer, and it is the single largest speculative investment in the package.

---

## Net removable estimate

| Item | Lines |
|---|---|
| `plugins/goalforge/` duplicate tree | ~22,464 |
| `run/` (if deleted rather than wired) | ~700 |
| `references/alias-map.md` | 83 |
| `goalforge-harden-route.sh` (net of call-site) | ~145 |
| `goalforge-archive-sweep.py` (if orphaned) | 250 |
| `goalforge-hygiene.sh` (if orphaned) | 93 |
| Derivable `state-machine.md` rows (source) | ~65 |
| Dead feature edge rows | 18 |
| `## Plans root` ×8 → pointer | ~48 |
| `## Unattended mode` ×6 → pointer | ~60 |
| Coverage-rule triplication | ~40 |
| `goalforge-goal-eval.sh` | 18 |
| `fidelity.md` repeated clause | ~6 |
| **Total** | **~24,000** |

Of which ~22,500 is the duplicate tree and **~1,500 lines is genuine dead or derivable weight inside `packages/goalforge/` itself** — before counting the ~2,200-line trace substrate (a judgment call, not clearly dead) and the SKILL.md shrinkage that item 8 would unlock (plausibly another 1,500–2,000 lines).

---

## Calibration

**Verified by direct reading:** all duplication findings (D1–D9), all design-quality findings (Q1–Q11) — each is quoted from the cited file and line. The script reference graph (§4) was built mechanically across both package trees and the dotfiles tree.

**Verified structurally, not by execution:** C1's subprocess counts (grep of `python3 ` occurrences — 11 in `goalforge-transition.sh` is an upper bound on spawns per invocation, since some are in branches or self-test). C3's claim that `goalforge-harden-route.sh` is a pure relabel rests on its header contract and the visible mapping at lines 12-22, not on a full read of its 156 lines.

**Not assessed:** the correctness of the validator's ~40 individual checks; whether `goalforge-pick-agent.py`'s `ROLE_TIER` projection is currently in sync with `tier-map.md` (there is a `--test-tiers` eval for it, which is the right design); the `wayfind/` sub-tree beyond its SKILL.md header and script inventory; runtime behavior of any script.



---

# 6. Customizable workflows + mixed-provider execution — feasibility

Both goals are further along than a greenfield framing suggests, but they live in two different repos that have never been wired to each other. goalforge (cogwright) already owns the *policy* half of provider-agnostic dispatch — an authoritative ROLE_TIER dict (role × autonomy-profile → tier × effort) with a generated, drift-checked `tier-map.md` projection, a provider-neutral dispatch-brief contract in `dispatch-template.md` (owned/off-limits, return-as-DATA, EscalationRequired), and a surface-selection rule that already names "headless CLI / leaf" as the cross-provider path. It also already ships the declarative workflow substrate: `execution_plan` routes captured from run traces by wp-12, stored at `packages/goalforge/run/workflows/<name>.md`, validated by `goalforge-plan-consumer.sh`, byte-deterministic, and copied verbatim into the plugin artifact by `scripts/goalforge-generate.sh`. What goalforge lacks is any *execution* binding: `route: api|ollama` is a two-valued enum with a hardcoded `OLLAMA_MODELS` dict, its `ollama_health` callable points at a skill that was renamed away, and no code path ever launches a non-Anthropic worker. The execution half already exists in dotfiles as `~/.claude/agents-dispatch/` — a 1137-line `bin/dispatch` CLI over a SQLite bus with seven provider plugs (claude, ollama, deepseek, zai, nvidia, moonshot, openrouter), each carrying its own declarative `provider.conf` with a `tier_map`, a verified headless Worker tier that writes typed briefs and launches process-group-isolated children, a capability model, and a lethal-trifecta gate at spawn. My recommendation is to put the seam at a single resolved `executor` string in the dispatch brief plus one executor-contract script that shells to `dispatch spawn --headless`, keeping goalforge free of all provider knowledge and letting each plug's `tier_map` own tier→model — which also deletes goalforge's duplicate `OLLAMA_MODELS` table. The first two executor rows should be the `judge` role on a different vendor (which simultaneously discharges a live policy violation: co-working.md mandates judge ≠ executor model, yet ROLE_TIER routes both `judge` and `implement` to opus) and the cheap mechanical roles on a free tier. For shipping workflows, declarative `execution_plan` routes already ship today and need only an explicit precedence rule; imperative Workflow-tool scripts can ship as plugin assets invoked by `scriptPath` (the resolver also honours a project-local `./.claude/workflows/`, which is the user-override mechanism, already implemented). One decision blocks the packaging half and is not agent-resolvable: wayfind ticket-06 is actively reconsidering whether agent-dispatch becomes a cogwright plugin at all or a standalone public repo, which reverses the draft wp-47.

---

# Feasibility + design sketch — goalforge: shippable customizable workflows & mixed-provider execution

Scope note: two systems are in play. **goalforge** lives in `/home/cunger/10_projects/cogwright` (canonical package `packages/goalforge/`, generated flat artifact `plugins/goalforge/`). **agent-dispatch** lives in `/home/cunger/dotfiles/claude` (runtime `~/.claude/agents-dispatch/`, plan `plans/agent-dispatch/`, 67 WPs). They declare a relationship (`consumed_by: goalforge` in the agent-dispatch overview) that **does not exist in code**.

---

## 1. What already exists toward these goals

### 1a. goalforge — the policy and contract layer (built, verified)

| Asset | Path | State |
|---|---|---|
| Authoritative role→tier×effort dict | `packages/goalforge/scripts/goalforge-pick-agent.py` (`ROLE_TIER`, `TIER_DISPATCH`, `resolve_role_tier`, `tier_to_dispatch`) | verified |
| Generated human projection | `packages/goalforge/references/tier-map.md` | generated, drift-gated by `--test-tiers` |
| Dispatch brief contract | `packages/goalforge/references/dispatch-template.md` | verified |
| Surface/effort/escalation detail | `packages/goalforge/execute/references/dispatch-resolution.md` | verified |
| Vendored discipline stamp | `packages/goalforge/references/discipline-core.md` + `.vendored-allowlist.txt` | verified |
| Declarative route consumer | `packages/goalforge/run/scripts/goalforge-plan-consumer.sh` | verified |
| Route library (shipped) | `packages/goalforge/run/workflows/captured-full-chain.md` | verified |
| Trace-capture → named route | `packages/goalforge/workflow-authoring/scripts/{distill,render}` + shared `scripts/goalforge-trace-read` | wp-12 verified |
| Wave fan-out + ownership check | `packages/goalforge/run/SKILL.md`, `evals/wave-route/owned-set-disjoint.py` | wp-07 verified |
| Trace substrate carrying `model` + `provider` per event | `packages/goalforge/references/trace-events.md` | wp-14 verified |

Three properties are worth naming because the design below leans on them:

- **`ROLE_TIER` is deliberately provider-free.** It emits bare tier names (`haiku|sonnet|opus|fable`) and bare efforts; a hard constraint forbids pinned vendor model IDs, enforced by `! grep -Eq "claude-(opus|sonnet|haiku)-[0-9]"` in the wp-05 verify. The tier vocabulary is already the cross-provider lingua franca — every `provider.conf` on the dotfiles side maps the same four names.
- **`tier-map.md` is a *generated projection* of a single authoritative dict, drift-checked by an eval.** This is the pattern to clone for any new axis. It was a deliberate human decision (2026-07-13) after an earlier design tried runtime markdown parsing.
- **`dispatch-template.md` already fixes the brief shape**: `role / model / effort / autonomy / owned / off-limits / task_spec / context`, a return-as-DATA contract, and `EscalationRequired` as the single escalation vocabulary. Nothing in it is Anthropic-specific except the `effort` semantics.

### 1b. goalforge — the workflow-shipping substrate (built, verified)

wp-12 resolved the representation question explicitly (`B-12-DOMAIN`): **declarative `execution_plan`, no new engine, no emitted CC Workflow script**, restricted to the goalforge chain domain. General/ad-hoc orchestration capture was routed *out* to the dotfiles `rules/common/workflows.md` promote flow.

The shipped shape (`run/workflows/captured-full-chain.md`):

```yaml
execution_plan:
  steps: [harden, execute, verify]
  dispatch: {execute: inline, harden: inline, verify: inline}
  parallel: [[harden], [execute], [verify]]
  tiers: {}
name: captured-full-chain
provenance: fixtures/trace-events.jsonl
```

plus a Mermaid step-graph. The consumer (`goalforge-plan-consumer.sh --emit-batches`) hard-validates: every step resolves to a `chain.yaml` basename, the selection is a contiguous path, `dispatch`/`parallel` keys are subsets of `steps`, `tiers` are carried as **opaque hints** (deliberately not resolved there). `--dispatch-of <step>` returns `inline|agent`.

Capture is byte-deterministic (strips seq/ts/session/model/provider/agent) with a round-trip eval.

### 1c. goalforge — plugin packaging (built, verified)

- Canonical source `packages/goalforge/` → deterministic generator `scripts/goalforge-generate.sh` → flat artifact `plugins/goalforge/`; pre-commit + CI re-run and fail on diff.
- Path-rewrite rule table pinned (classes i–vii), including `${CLAUDE_PLUGIN_ROOT}` climbs.
- **A directory without a `SKILL.md` is copied verbatim** (documented rule, `workflow-authoring/` is the existing instance) — so `run/workflows/` already ships, and a future `workflows/` dir would too, with **no generator change**.
- `plugin.json` omits a semver; version = commit SHA → consumers auto-update per push. `marketplace.json` at repo root.
- `scripts/install.sh` has `--mode contributor` (symlink `~/.claude/skills/goalforge` → `packages/goalforge`) and `--mode consumer` (marketplace install).

### 1d. dotfiles — the execution substrate (mostly built; this is the load-bearing find)

`~/.claude/agents-dispatch/`:

```
bin/dispatch            1137 lines — spawn/status/list/despawn/actas/pump/
                        pipe/send/receive/cap/egress/providers/provider/doctor
lib/bus.sh registry.sh worker.sh capability.sh egress.sh
    driver-registry.sh identity.sh rate-limit.sh payload-schemas.sh migrate.sh
schema.sql              SQLite runtime DB
providers/{claude,ollama,deepseek,zai,nvidia,moonshot,openrouter}/
    provider.conf  _dispatch.sh  _health.sh  _parse_findings.sh  [wrapper]
tests/ evals/
```

A `provider.conf` is a declarative manifest, **allowlist-parsed, never sourced**:

```
name=openrouter
cli=openrouter-claude
cli_is_wrapper=yes
models=deepseek/deepseek-v4-flash deepseek/deepseek-v4-pro z-ai/glm-5.2 …
default_model=deepseek/deepseek-v4-pro
default_mode=headless
tier_map=haiku:deepseek/deepseek-v4-flash sonnet:deepseek/deepseek-v4-pro opus:z-ai/glm-5.2 fable:moonshotai/kimi-k3
tier_map.moonshot=haiku:moonshotai/kimi-k2.6 sonnet:moonshotai/kimi-k2.7-code …
capabilities=interactive headless
storage=sqlite
delivery=file
backend_hosts=openrouter.ai
key_storage=libsecret
key_namespace=agent-dispatch-openrouter
```

Note `tier_map` uses **exactly goalforge's tier vocabulary**, and named presets (`tier_map.moonshot`) already exist — the "customizable" knob for provider selection is already data, not code.

Verified capabilities relevant here: v2 bus core (wp-34), the 3-axis plug convention storage × harness × delivery (wp-35), **headless Worker tier** (wp-36 — `write_brief()` emits a typed frontmatter brief at `run/briefs/<id>.md` 0600, `worker_launch()` uses `setsid` for process-group kill, child stdout/stderr → `run/findings/<id>.raw`, findings adapter), peer data-plane (wp-37), collaborator tmux tier (wp-38/44), capability mint/check/revoke (wp-39), unified dispatch registry (wp-27), advisor wiring (wp-53), and provider leaves for nvidia NIM (wp-48) and moonshot direct (wp-49).

`cmd_spawn` enforces a **lethal-trifecta gate**: a brief requesting private-context + untrusted-input + egress simultaneously is denied at construction.

Unbuilt tail that matters: wp-40 egress firewall `executing`; wp-41 tracing/observability `ready`; wp-50 OpenRouter **`openai` tier_map preset** `ready` (this is the user's "OpenAI-family cheap coding" path, specified but not built); wp-51 reliability fallback chain `ready`; wp-52 dispatch trace tree `ready`; wp-42 cutover and wp-43 eval-conformance `spec`; wp-47 extract-to-cogwright `draft`.

### 1e. dotfiles — the governing rules already encode the target policy

`references/rules/performance.md` carries the Dispatch Routing Matrix, per-tier Ollama fallbacks, the cross-provider Kimi tie-break (direct beats openrouter for the same id; NIM beats direct for free haiku-tier bursts), and a hard rule: **never gate an autonomous decision on a wrapper's self-reported cost** (observed ~37× divergence on OpenRouter-routed dispatch).

`references/rules/co-working.md` already mandates:
- the judge model **MUST differ** from the executor model; for high-stakes panels **prefer a different vendor**;
- a dispatch reliability fallback chain: retry same provider → alternate provider same tier → native Anthropic → report, every hop logged;
- degrade-never-block when an external provider is down or unkeyed.

`hooks/agent-dispatch-model-guard.sh` is the hard backstop — it blocks implicit-model Agent/Task/Workflow dispatch, a fable worker on every surface including headless `claude -p`, and applies its count heuristic to `{scriptPath}` and `{name}` workflow invocations.

### 1f. Native harness mechanics (confirmed, load-bearing for §3)

From the model-guard hook header (authoritative — it implements the resolution) and the workflows rule:

- `Workflow({name})` resolves against **`~/.claude/workflows/<name>.js`** *and* **`./.claude/workflows/<name>.js`**. A project-local file therefore already provides per-repo override by name.
- `Workflow({scriptPath})` runs an arbitrary path and is subject to the same guard checks (the previous unconditional allow was closed as a bypass in 2026-07-22).
- `agent(prompt, {model, effort})` is the **only** surface with a per-agent effort knob — and it is **Anthropic-only**. There is no provider parameter.
- The Agent tool sets model only; effort inherits the session.
- **Plugins have no documented `workflows/` component.** No installed plugin under `~/.claude/plugins/` ships one. `~/.claude/workflows/*.md` sidecars are what surfaces `review-verified` / `application-judge` / `repo-refactor-discovery` as invocable names.

### 1g. Gaps and live defects in goalforge

1. **No executor binding.** `route: api|ollama` resolves, then nothing consumes it. `dispatch-resolution.md` names `ollama_health` as "the `ollama-dispatch` health check" — that skill was renamed to `agent-dispatch-ollama` in wp-02. Stale pointer to a dead name.
2. **A duplicate tier→model table.** `goalforge-pick-agent.py` hardcodes `OLLAMA_MODELS = {low: nemotron-3-nano, medium: deepseek-v4-pro, high: deepseek-v3.2}`. `providers/ollama/provider.conf` already owns that mapping. This violates the leaf contract's own §3.1 rule 1 ("a leaf's tier→model map lives in **one** place") and the no-pinned-vendor-ID rule that wp-05 enforces for the *api* route only.
3. **Judge-diversity violation shipped as the default.** `ROLE_TIER["judge"]` = `medium` → opus; `ROLE_TIER["implement"]` at `complexity: medium` → opus. co-working.md: "A model judging its own output is not a second opinion." goalforge's default configuration is the thing that rule forbids.
4. **`execution_plan.dispatch` is `{inline|agent}` only** — no dimension for surface or provider. Any cross-provider route is currently unexpressible in a shipped workflow.
5. **No cost signal in the loop.** Nothing in goalforge reads spend, so "route cheap work to a cheap provider" has no closed-loop check.
6. **Packaging destination unresolved.** `plans/base-system-map/wayfind/ticket-06-cogwright-extraction-wave.md` is `open` and records a user leaning that *reverses* wp-47: agent-dispatch may become a standalone public repo ("agentic workflows builder") rather than `cogwright/plugins/agent-dispatch`, with cogwright as a connection hub. Blocked on ticket-10 (settled-contract definition) and ticket-09 (publish gate).

---

## 2. Architecture options — provider-agnostic dispatch

### The trade-off that forces the shape

| Surface | Provider choice | Per-agent effort | Concurrency | Context cost |
|---|---|---|---|---|
| Workflow `agent()` | **no** (Anthropic only) | **yes** | scripted, native | returns as data, cheap |
| Agent tool | **no** | no (session-inherited) | batched message | cheap |
| Bash → `dispatch spawn --headless` | **yes** (7 plugs) | no (advisory only) | manual (poll/await) | file-mediated, cheap |
| MCP tool | yes (if built) | no | in-session, blocking | returns into context |
| Anthropic-compat proxy (`ANTHROPIC_BASE_URL`) | yes, but **process-wide** | yes (nominally) | native | cheap |

The consequence: **a mixed-provider wave cannot be expressed inside `agent()` alone.** The realistic best-of-both shape is a Workflow script whose stages mix native `agent()` legs (Anthropic, effort-tuned) with `Bash`-launched `dispatch` legs (other providers), joined in script. That is worth stating in the design because it decides where the seam can *not* go.

### Option A — Executor string in the brief + one contract script  ← recommended

goalforge never learns what a provider is. `pick_agent` gains one resolved field, `executor`, and one contract:

```
goalforge-exec-dispatch.sh --executor <id> --tier <bare> --effort <bare> \
                           --brief <path> --out <path>
```

Bound to `dispatch spawn --headless <provider> --model <tier> …`. Tier→model resolution stays where it already lives: the plug's `provider.conf tier_map`. goalforge never names a concrete model.

- **Cost now:** one dict + one generated projection + one field in `dispatch-template.md` + one ~40-line script.
- **Cost of the second executor:** one map row.
- **Degradation:** `dispatch` absent → `EscalationRequired` (never a silent native fallback — matches the module's existing no-silent-fallback contract). goalforge stays installable standalone and *gains* cross-provider capability when agent-dispatch is present. Capability detection, not a hard dependency — which sidesteps the fact that the plugin marketplace has no dependency resolution.
- **Seam vs abstraction:** this is a seam (a string and a calling convention), not an abstraction (no provider interface, no plug registry inside goalforge). Correct per "draw a seam now, defer the abstraction to the second concrete need."

Concretely, mirroring the wp-05 pattern exactly:

```python
# authoritative — scripts/goalforge-pick-agent.py
ROLE_EXECUTOR: dict[str, dict[str, str]] = {
    #  role                autonomous-minimal   semi-autonomous
    "implement":          {"autonomous-minimal": "native",  "semi-autonomous": "native"},
    "discovery":          {"autonomous-minimal": "cheap",   "semi-autonomous": "native"},
    "arbiter-grid":       {"autonomous-minimal": "cheap",   "semi-autonomous": "native"},
    "judge":              {"autonomous-minimal": "diverse", "semi-autonomous": "diverse"},
    "panel":              {"autonomous-minimal": "diverse", "semi-autonomous": "diverse"},
    ...
}
```

`native` / `cheap` / `diverse` are **intent aliases**, not provider names — resolved to a concrete plug by a single user-editable binding file (`references/executor-bindings.yaml`, or better: read from `~/.agents/dispatch/providers/` at call time). Keeping the alias layer means the shipped plugin expresses *policy* ("the judge must not be the writer") without hardcoding *your* provider keys, which is exactly what makes it shippable to other people.

Projection `references/executor-map.md` generated from the dict; `--test-executors` mirrors `--test-tiers` for the drift gate. `route: api|ollama` becomes an alias of `executor` for one deprecation lap, then dies — one vocabulary, per the existing single-owner discipline that killed `needs_escalation`.

### Option B — goalforge imports the provider-plug layer directly

Higher capability: registry rows, cap minting, trace-tree parentage, egress grants all become first-class in goalforge. But it makes goalforge structurally dependent on agent-dispatch's internals across a repo boundary that is *itself* an open question (ticket-06). Defer; Option A's contract script is the forward-compatible stub — it can later grow to pass `--private-context/--untrusted-input/--egress` legs and cap tokens without changing goalforge's brief shape.

### Option C — MCP tool as the dispatch surface

An MCP server exposing `dispatch(provider, tier, brief) → findings`. Genuinely harness-neutral (the one thing a CLI contract is not) and would matter if a second harness ever appears. Against it now: returns land in-context (large findings are expensive), no effort knob, a server lifecycle to manage, and `plans/suite-extraction/overview.md` records an explicit user decision (2026-07-16) to **YAGNI-defer harness portability** — "a second harness is a concrete need that does not exist yet."

### Option D — Shared Anthropic-compat proxy

Point `ANTHROPIC_BASE_URL` at a local FastAPI translator and every `claude -p` becomes cross-provider with zero goalforge change. Already partially built (wp-48 ships a NIM-scoped `nim-proxy.py`) and generalization is captured as `plans/ideas/shared-openai-compat-proxy.md` with an MIT reference implementation. Fatal limitation for this use case: **the base URL is process-wide**, so it cannot mix providers across stages of one run — it is an *interactive-session* solution, not a *dispatch-routing* one. Its documented reopen trigger (second interactive OpenAI-compat plug) is the right gate; do not pull it forward.

### Where the seam belongs — summary

| Layer | Owner | Rationale |
|---|---|---|
| role → tier × effort × **executor-intent** | goalforge `ROLE_TIER` / `ROLE_EXECUTOR` | policy; portable; no vendor facts |
| executor-intent → concrete plug | user binding file / plug discovery | deployment-specific; the customization knob |
| tier → concrete model | `provider.conf tier_map` | provider fact; already single-sourced |
| launch, isolate, capture findings | `dispatch spawn --headless` | already verified; carries the security gates |

goalforge's `OLLAMA_MODELS` dict spans rows 2–3 of that table and must be deleted as part of P1/P2 — that deletion is a strict simplification, not added scope.

**Effort does not port.** `effort` is Anthropic-specific; Moonshot's `kimi-k3` currently exposes `max` only (documented in both `performance.md` and the leaf contract, with a retier trigger). Treat `effort` in the brief as **advisory** for non-native executors and let `tier_map` be binding. Document this; do not emulate effort levels.

---

## 3. Shipping customizable workflows with the plugin

Two different things are called "workflow". Keep them separate — wp-12 already made this ruling and it should not be relitigated:

- **(i) Declarative `execution_plan` routes** — goalforge chain domain, consumed by `goalforge-plan-consumer.sh`.
- **(ii) Imperative CC Workflow scripts** (`*.js` with `agent()`/`parallel()`/`pipeline()`) — general orchestration, explicitly out of goalforge's scope, homed in `~/.claude/workflows/`.

### S1 — Ship declarative routes (works today; needs one rule)

Already functional: `run/workflows/*.md` lives in the package, and the generator copies non-SKILL.md dirs verbatim into `plugins/goalforge/`. wp-12 gives capture-from-trace, Mermaid render, and byte-determinism evals.

The one missing piece is an **explicit precedence rule**, currently implicit:

```
feature overview.md execution_plan block      (highest — a run's own plan)
  > <repo>/.claude/goalforge/routes/<name>.md (user override, per-repo)
  > ${CLAUDE_PLUGIN_ROOT}/run/workflows/<name>.md (shipped defaults)
```

This is a lookup-order change in one script plus a merge rule. Design the customization surface as **data, not code**: a user overrides a shipped route by dropping a file that sets only `executors:` / `tiers:` / `dispatch:` and inherits the rest. One merge function, one documented precedence, no plugin edit.

The `execution_plan` schema needs one additive field to carry §2:

```yaml
execution_plan:
  steps: [harden, execute, verify]
  dispatch: {harden: inline, execute: agent, verify: agent}
  executors: {verify: diverse, execute: native}   # NEW — intent aliases
  tiers: {}                                        # already opaque
```

`executors` stays **opaque to the consumer** exactly as `tiers` already is — resolution belongs to pick-agent, and the consumer's own header already pins that discipline ("`.tiers` are captured as OPAQUE hints only — tier resolution is wp-05's").

### S2 — Ship imperative Workflow scripts as plugin assets

Mechanism: `${CLAUDE_PLUGIN_ROOT}/workflows/<name>.js`, invoked as `Workflow({scriptPath})` from a shipped skill or command. No installer, no copy, survives plugin updates, and the generator already handles a non-SKILL.md dir with no change.

Two real constraints to design against:

1. **The model-guard hook reads scriptPath files** and applies its count heuristic — a shipped script with fewer `model:`/`effort:` keys than `agent()` calls is **BLOCKED**. This is a shipping conformance requirement (and a good one). Add it as an eval: lint every shipped workflow against the same counts the hook uses.
2. **User override is already implemented** — the resolver honours `./.claude/workflows/<name>.js`. A user customizes by copying the shipped script into their repo. Document this; build nothing.

### S3 — Installer-managed copy into `~/.claude/workflows/`

Only buys `Workflow({name})` ergonomics plus the `.md` sidecar that surfaces the name as invocable. `cogwright/scripts/install.sh` already has contributor/consumer modes; a `--with-workflows` leg would symlink. Costs: update drift on a copied file, and name collisions with the user's own workflows (which is exactly why the `.md` sidecar surfacing is a shared global namespace). **Defer** unless name-invocation ergonomics are explicitly demanded.

### What "customizable" should mean, concretely

| Knob | Surface | Mechanism |
|---|---|---|
| which steps run, in what order/parallelism | `execution_plan.steps/parallel` | feature overview block or route override file |
| inline vs subagent per step | `execution_plan.dispatch` | same |
| which provider per role | `executors:` + binding file | binding file is user-owned, never shipped |
| tier/effort per role | `ROLE_TIER` (shipped policy) | overridable via a repo-local overlay if demanded — defer |
| the orchestration code | shipped `.js` | copy to `./.claude/workflows/` (already resolved by name) |

Ship policy; never ship keys, provider names, or a user's tier bindings.

---

## 4. Phased recommendation

### P0 — Decide, don't build (blocks everything in §3)

**Resolve wayfind ticket-06.** cogwright-plugin vs standalone-repo for agent-dispatch determines whether goalforge's executor contract calls a sibling plugin, an adjacent repo's installed CLI, or a vendored copy. This is a strategy/preference call with an irreversible naming and publication consequence — route to the human via `AskUserQuestion`, not to an agent. It depends on ticket-10 (settled-contract definition) and ticket-09 (publish gate), both open. Note that whichever way it goes, **Option A's capability-detection posture is unaffected** — that is precisely why it is the right first move.

### P1 — Executor axis in pick-agent (1 WP, deterministic verify)

Authoritative `ROLE_EXECUTOR` dict + generated `references/executor-map.md` + `executor` in `pick_agent`'s return + one `executor:` field in `dispatch-template.md`. Alias `route: api|ollama` onto it for one lap, then delete `OLLAMA_MODELS`. Verify: `--test-executors` (mirrors `--test-tiers`) + regeneration-drift diff. No network, no provider needed.

### P2 — The executor-contract script (1 WP, deterministic verify)

`scripts/goalforge-exec-dispatch.sh`: one verb, delegates to `dispatch spawn --headless`, raises `EscalationRequired` when the backend is absent. Must **pass through** the trifecta legs (`--private-context`, `--untrusted-input`, `--egress`) rather than bypass the spawn gate — do not create a second dispatch path that skips the security choke point. Verify against a fake executor fixture on `$PATH` (no network, no keys).

### P3 — The first two real executor rows (1 WP)

- `judge` / `panel` → `diverse`. **This discharges the live co-working violation in §1g.3** and is exactly the user's "unbiased review by a different provider than the one that wrote the code." Highest value, lowest blast radius — a judge is read-only.
- `discovery` / `arbiter-grid` / `wp-harden-delta` (autonomous-minimal) → `cheap`. NVIDIA NIM `kimi-k2.6` free tier or local ollama; matches the user's "fast cheap models for mechanical work."

Verify: a fixture run's `trace-events.jsonl` shows `provider != "anthropic"` on the judge event and `provider` differing between the `implement` and `judge` rows. The trace schema already carries `provider` — this is a binding, not a schema change.

Deliberately **not** in P3: routing `implement` to another provider. Code-writing is where a provider swap costs most and is hardest to verify; earn it with data from P3's cheaper roles first.

### P4 — Workflow shipping, S1 (1 WP)

Explicit precedence rule + route-override merge + additive `executors:` field (opaque to the consumer) + 2–3 curated shipped routes. The byte-determinism and round-trip evals from wp-12 already cover the hard parts.

### Next (after P1–P4 see real usage)

- **wp-51 reliability fallback chain** (already `ready`) — becomes load-bearing the moment a non-native executor sits on the critical path; without it one provider outage stalls a chain run. Sequence it immediately after P3.
- **wp-50 OpenRouter `openai` preset** (already `ready`) — the actual "cheap OpenAI-family coding" path the user asked for. Specified, unbuilt, and specified *not* to include direct `api.openai.com`.
- **wp-41 / wp-52 tracing + trace tree** — cross-provider attribution and the parent-linkage hook that the traced-delegation charter is explicitly gated on ("Traced delegation activates only once the enforcing hook is live").
- **Cost ground truth** (wp-63 queryable dispatch results) — required before any *automatic* cost-driven executor selection, per the never-trust-wrapper-cost rule.
- **S2 plugin-shipped `.js` workflows** via `scriptPath`, with a model-guard conformance eval.

### Defer explicitly, with the trigger that reopens each

| Deferred | Reopen when |
|---|---|
| `custom-workflow-engine` (own orchestration primitives) | native Workflow/Agent orchestration is *demonstrably* insufficient in a real run — the idea file already states this gate; honour it |
| direct `api.openai.com` plug | wp-50's OpenRouter preset has real cost data showing the marketplace hop hurts |
| shared OpenAI-compat proxy | the **second** interactive OpenAI-compat plug lands |
| MCP dispatch surface | a second harness becomes a concrete need (currently a ratified YAGNI) |
| `dynamic-dispatch-graphs` | research lane; keep as an idea |
| S3 installer-copied workflows | `Workflow({name})` ergonomics are explicitly requested |

---

## 5. Risks and contradictions to carry into the spec

1. **Live policy violation, shipped.** `ROLE_TIER` routes `judge` and `implement` both to opus; co-working.md forbids a model judging its own output. Fixed by P3 — but until then goalforge ships a default that its own governing rule prohibits. Worth stating in the WP as the motivating defect rather than as a feature.
2. **Duplicate tier→model authority.** `OLLAMA_MODELS` in `goalforge-pick-agent.py` duplicates `providers/ollama/provider.conf tier_map` and pins vendor IDs that the api-route path is explicitly forbidden to pin. Deleting it is part of P1/P2, not extra scope.
3. **Stale pointer.** `dispatch-resolution.md` references the `ollama-dispatch` health check; that skill was renamed `agent-dispatch-ollama` in wp-02. One-line fix, but symptomatic — the ollama route has never been exercised.
4. **Plugin dependency has no mechanism.** The marketplace does not resolve inter-plugin dependencies. Capability detection with `EscalationRequired` degradation (Option A) is the only honest posture; do not declare a dependency the installer cannot satisfy.
5. **Security surface widens.** Cross-provider dispatch is private repo context + external egress by construction. agent-dispatch already gates the lethal trifecta at spawn, mints task-scoped caps, and reads `backend_hosts` into the egress allowlist. The executor contract must route *through* that gate. wp-40 (egress firewall) is still `executing` — network-level enforcement is not yet real, so treat the trifecta gate as declaration-time only until it lands, and say so.
6. **Effort semantics are non-portable** (§2). Advisory on non-native executors; `tier_map` binds.
7. **`agent()` cannot go cross-provider.** Any shipped workflow mixing providers must be a hybrid: native `agent()` legs plus Bash→`dispatch` legs joined in script. Design shipped routes around that shape rather than discovering it at implementation time.
8. **Extraction destination is unresolved (P0).** wp-47 (`draft`, `extracts-to: cogwright/plugins/agent-dispatch`) is directly contradicted by the ticket-06 user leaning toward standalone repos with cogwright as a relations hub. Building the executor contract *before* resolving this is fine — building any *packaging* of it is not.

---

## Key file references

**cogwright / goalforge**
- `/home/cunger/10_projects/cogwright/packages/goalforge/scripts/goalforge-pick-agent.py` — `ROLE_TIER`, `TIER_DISPATCH`, `COMPLEXITY_MODEL`, `OLLAMA_MODELS`, `resolve_role_tier`, `tier_to_dispatch`, `blast_radius`, `EscalationRequired`
- `/home/cunger/10_projects/cogwright/packages/goalforge/references/tier-map.md` — generated projection (pattern to clone)
- `/home/cunger/10_projects/cogwright/packages/goalforge/references/dispatch-template.md` — brief contract
- `/home/cunger/10_projects/cogwright/packages/goalforge/execute/references/dispatch-resolution.md` — surface selection; names the cross-provider path
- `/home/cunger/10_projects/cogwright/packages/goalforge/execute/SKILL.md` — Steps 3–6b (dispatch, worktrees, checkpoint)
- `/home/cunger/10_projects/cogwright/packages/goalforge/run/scripts/goalforge-plan-consumer.sh` — `execution_plan` validation + `--emit-batches` / `--dispatch-of`
- `/home/cunger/10_projects/cogwright/packages/goalforge/run/workflows/captured-full-chain.md` — shipped route instance
- `/home/cunger/10_projects/cogwright/packages/goalforge/run/chain.yaml` — canonical step order
- `/home/cunger/10_projects/cogwright/scripts/goalforge-generate.sh` — deterministic package → plugin generator, path-rewrite rule table
- `/home/cunger/10_projects/cogwright/plans/goalforge/plugin-authority-design.md` — contributor-symlink / consumer-marketplace decisions
- `/home/cunger/10_projects/cogwright/plans/goalforge/wp-05-dispatch-tiering/`, `wp-07-wave-route/`, `wp-12-workflow-authoring/`

**dotfiles / agent-dispatch**
- `/home/cunger/.claude/agents-dispatch/bin/dispatch` — verb CLI (`cmd_spawn` at line 130, usage at 1071)
- `/home/cunger/.claude/agents-dispatch/lib/worker.sh` — `write_brief`, `worker_launch`, `_worker_conf_get`
- `/home/cunger/.claude/agents-dispatch/providers/*/provider.conf` — declarative plug manifests with `tier_map`
- `/home/cunger/dotfiles/claude/skills/agent-dispatch/references/leaf-interface.md` — v1 leaf contract + §3.1 tier resolution rules
- `/home/cunger/dotfiles/claude/references/rules/performance.md` — Dispatch Routing Matrix, cost ground-truth rule, Kimi tie-break
- `/home/cunger/dotfiles/claude/references/rules/co-working.md` — judge diversity, fallback chain, traced-delegation charter
- `/home/cunger/dotfiles/claude/references/rules/workflows.md` — Workflow triggers, promote flow, advisor stage
- `/home/cunger/dotfiles/claude/hooks/agent-dispatch-model-guard.sh` — authoritative workflow-name/scriptPath resolution + block conditions
- `/home/cunger/dotfiles/claude/plans/agent-dispatch/overview.md`, `DIRECTION-2026-07.md`, `wp-47-extract-to-cogwright/overview.md`
- `/home/cunger/dotfiles/claude/plans/base-system-map/wayfind/ticket-06-cogwright-extraction-wave.md` — the open packaging decision
- `/home/cunger/dotfiles/claude/plans/suite-extraction/overview.md` — extraction sequence + harness-portability YAGNI decision
- `/home/cunger/dotfiles/claude/plans/ideas/{custom-workflow-engine,shared-openai-compat-proxy,agent-dispatch-direct-openai-plug,dynamic-dispatch-graphs}.md`
- `/home/cunger/dotfiles/claude/workflows/review-verified.js` — the closest existing model for a shippable multi-lens, quorum-verified review workflow


---

# 7. Related plans & ideas inventory

# Goalforge System — Planned Work & Ideas Inventory

## 1. WP Status — `plans/goalforge/` (feature status: **completed**, 21/21 WPs `verified`)

| WP | Status | Scope |
|---|---|---|
| wp-01-schema-v5 | verified | Schema v5: route enum, `execution_plan`, `optional_depends_on`, goal-mandatory + version marker |
| wp-02-package-migration | verified | Migrate `sdd-*` → cogwright `plugins/goalforge/` + alias layer |
| wp-03-route-classifier | verified | `goalforge-route.sh` 3-route classifier (fast/standard/wave; one-go folded in) + capture stamps `execution_plan` |
| wp-04-runner-plan-consumer | verified | `goalforge/run` + `chain.yaml` consume `execution_plan` |
| wp-05-dispatch-tiering | verified | Role→tier map + dispatch template + trust-boundary contracts |
| wp-06-brief-stage | verified | Optional tier-inversion brief stage (`ready→briefed→executing`) |
| wp-07-wave-route | verified | Wave orchestration: fan-out → parallel spec authors → cross-spec judge → fixer, file-ownership discipline |
| wp-08-single-writer-hook | verified | PreToolUse single-writer hook blocking direct status edits |
| wp-09-e2e-docs | verified | Per-route E2E runbooks, docs, telemetry baseline |
| wp-10-repo-bootstrap | verified | Bootstrap public `cogwright` monorepo marketplace + plugin skeleton |
| wp-11-data-contract | verified | Deterministic `plan-index.json` (index-only read contract) |
| wp-12-workflow-authoring | verified | Workflow-authoring skill: capture an emergent run into a reusable `execution_plan` |
| wp-13-local-rename | verified | Local `sdd-*`→`goalforge-*` rename; local tree becomes source of truth |
| wp-14-trace-substrate | verified | Versioned append-only trace-event log + validating emitter + chain wiring |
| wp-15-retrospective-stage | verified | Issue/bottleneck capture + propose-only improvement-report distiller |
| wp-16-preharden-lint | verified | Deterministic pre-harden lint (plugin-anchored paths, tautological verifies) |
| wp-17-package-move-generator | verified | Move package into `cogwright/packages/goalforge/` + generated flat plugin artifact + drift gate |
| wp-18-symlink-installer | verified | Deterministic installer (contributor symlink / consumer marketplace) |
| wp-19-claude-md-verify | verified | CLAUDE.md pointer verification + dedup + naming rule |
| wp-20-consumer-migration | verified | Migrate external consumers (tangram, ProSIP) to `goalforge-*` names |
| wp-21-sdd-deletion | verified | Delete legacy `sdd-*` surface (13 alias dirs, 27 shims) in one reversible commit |

**Related/adjacent feature, also verified:** `goalforge-prototype-native` (7 WPs, verified+merged) — prototype-mode SDD conformance, native-fidelity hooks, `goalforge-interview` specialization child. Spun off two ideas: `prototype-spec-soft-reference`, a brief/tenancy spin-off (neither found materialized in current ideas dirs — likely dropped or absorbed).

**A third, unfinished feature:** `goalforge-review-assist` — spec drafted + judge-hardened 2026-07-29 (an automated code-review/verification control-loop actuator, `references/rules/agentic-control-loops.md` design frame), status `draft`, human ratify-gate never taken. **The `plans/goalforge-review-assist/` directory referenced by its handoff no longer exists in the repo** — either abandoned, never committed, or superseded; treat as **stalled/orphaned**, not done.

## 2. Open/Unfinished Items (from `todo.md` auto-rollup + `improvement-report.md`)

All WPs show `verified`, but several carry residual straggler work recorded in the auto-generated todo:

- **wp-04**: execute-time route-vocab migration items were "specified, not done at harden" per its findings (chain.yaml `full`→`standard`, stale `goalforge-goal-route.sh` reference) — check whether execute lap closed these (recap shows wp-04 green, so likely closed, but todo.md still lists it — todo.md may be stale relative to recap).
- **wp-13**: plugin export re-sync (plugin ← local) deliberately deferred, "final [step TBD]" — cut off mid-sentence in the source file.
- **wp-19**: inventory (2026-07-21) found 9 missing CLAUDE.md refs (docs/analysis/, docs/decisions/, taxonomy.md, MEMORY.md, USER.md, skills/scripts, skills/skill-systems/, 2 template placeholders) — status of the fix unclear from todo.md alone (WP is verified, so presumably fixed, but not re-confirmed here).
- **wp-21**: known straggler — `goalforge-install-hooks.sh` still hardcodes a legacy `SDD_HOOK_PATH` to the deleted `skills/sdd/scripts/hooks/sdd-pre-commit.sh`.
- **Improvement report (unresolved, propose-only, routing pending)**:
  - `tool-failure` (×2): a test-harness git remote rewire that broke pushes; `recap.sh record-wp` silent-success/arg-error UX gap.
  - `spec-gap` (wp-19): harden auto-advance doesn't re-run the route/complexity helper after doc edits before transition — flagged for a rule/memory fact, not yet written.
  - `skill-defect` (wp-04): stale `sdd-goal-route.sh` reference inherited into the e2e runbook — below the ≥2× auto-improve threshold, so not yet routed to `/skill-improve`.
  - `tool-failure`: `goalforge-retrospect`/`goalforge-issue` invoked via bash on a python-shebang script — doc/self-test mismatch in the handoff SKILL.md snippet.
- **Explicitly deferred (recorded as intentionally out-of-scope, not "unfinished")**: cross-feature RUNNER (auto-driving feature DAGs), attachable deterministic pipelines (sub-idea 2 of `sdd-optional-deps...`), a custom workflow *engine* (only workflow-*authoring* shipped), alias-sunset/removal (gated on telemetry).

## 3. Related Ideas by Goal

### (a) Customizable / shippable workflows
- **`custom-workflow-engine`** (idea, kind: system) — replace native CC orchestration with a first-class in-house workflow-engine primitive for dynamic loops (autopilot etc.); `chain.yaml` today only covers fixed chains. Directly references the goalforge feature as precedent/dependency.
- **`sdd-feature-chaining-orchestration`** (idea, kind: feature) — cross-feature DAG runner; explicitly the "Out" item from goalforge's own scope (stays YAGNI-deferred there).
- **`sdd-optional-deps-and-deterministic-pipelines`** (status: refined) — sub-idea 2, "attachable deterministic pipelines," stays live/independently promotable; sub-idea 1 (`optional_depends_on` edge) was absorbed into goalforge wp-01.
- **`goalforge-extend-inventory-stage`**, **`goalforge-status-state-machine`** (both idea, kind: skill) — smaller extensions to the shipped chain (not yet triaged/read in depth here — titles only surfaced via grep, worth a follow-up read if prioritizing).
- Goalforge's own **wp-12-workflow-authoring** (verified) is the shippable-workflow deliverable that *did* land: capture an emergent dynamic run into a reusable, named `execution_plan`.

### (b) Mixed-provider agents (OpenAI/local models — cheap coding or unbiased review)
- **`agent-dispatch-direct-openai-plug`** (idea, priority: low) — direct `api.openai.com` provider plug, bypassing the current OpenRouter passthrough.
- **`agent-dispatch-perspective-fanout`** (idea, kind: feature) — parallel **multi-provider** perspective fan-out at the worker tier — directly serves "unbiased review" (structurally diverse judges, not just prompt-diverse).
- **`external-agent-runtime-plugs`** (idea, priority: medium) — LangChain/LangGraph, Google ADK as governed dispatch provider-plugs.
- **`pi-harness-as-dispatch-runtime`** — `pi` (earendil-works) as an alternate collaborator harness + structured RPC transport.
- **`shared-openai-compat-proxy`** (idea) — one shared local Anthropic↔OpenAI proxy for *all* OpenAI-compat provider plugs (nvidia, openrouter, deepseek, minimax, kimi, z.ai, groq, cerebras…), replacing today's one-off proxy per provider (wp-48's nim-proxy.py was the first).
- **`agent-dispatch-agentic-runtime`** (idea, kind: system, freshest — 2026-08-07) — a broader "agentic runtime rework" of agent-dispatch: build/manage custom agents and workflows with typed guardrails.
- **`dynamic-dispatch-graphs`** (status: refined, kind: system) — orchestrator-composed agent topologies with typed relations and **per-node harness/provider choice**.
- Already **shipped, not just ideas**: the `agent-dispatch-{deepseek,moonshot,nvidia,ollama,zai}` skills — interactive terminal sessions or headless sub-agent dispatch to non-Anthropic models, largely for cheap/mechanical or 1M-context work. These are the delivered instance of "cheap coding on a different provider."

### (c) Verification workflows
- **`goalforge-review-assist`** (draft spec, stalled — see §1) — a control-loop-based automated review/verification actuator; the most direct hit for this goal, but currently orphaned (plans dir missing).
- **`viz-embedded-review-agent`** — TUI + `goalforge-reviewer` skill embedded in the viz tool; references the `goalforge-review-assist` spec as its dependency, so it inherits the same stall.
- **`efficient-verification-fanout`** (status: captured) — cap adversarial fan-out in review/harden workflows; prefer a cross-checking panel over per-finding adversarial verify. Concrete trigger: a wave-2 harden run spawned ~27 agents (~23 verifiers) for one WP's planning-doc review — cost disproportionate. Points at `skills/goalforge/harden/references/panel-protocol.md`.
- **`panel-debate-rebuttal-round`** (idea, kind: skill) — bounded rebuttal round for the adjudication/panel debate mode.
- Goalforge's shipped wp-15-retrospective-stage + wp-14-trace-substrate are the verification-*observability* layer that already landed (issue capture, propose-only distiller) — but note the improvement-report's own findings above remain unresolved/unrouted, i.e., the loop hasn't closed yet on its own output.

### (d) Dispatch tiering (cheap models for mechanical work)
- Shipped: **wp-05-dispatch-tiering** (role→tier map, bare tier names, effort defaults, inline-threshold rule) and **wp-06-brief-stage** (tier-inversion: strong tier authors a brief once, cheap tier executes+revalidates) — both `verified`, form the core delivered dispatch-tiering mechanism.
- **`efficient-verification-fanout`** also bears on this: it's a *cost-control* correction to tiering, arguing panel/fan-out sizing itself needs a cheaper default.
- **`shared-openai-compat-proxy`** and the `agent-dispatch-*` provider skills extend tiering *across providers*, not just across Anthropic tiers — the natural next lever for "cheap coding" beyond haiku/sonnet.
- **`dynamic-dispatch-graphs`** generalizes tiering into a full topology-composition primitive (per-node harness/provider AND tier choice).

## 4. Serve vs. Conflict

**Directly serve the stated goals (build on what shipped, no rework needed):**
- `agent-dispatch-perspective-fanout`, `external-agent-runtime-plugs`, `shared-openai-compat-proxy`, `agent-dispatch-direct-openai-plug`, `agent-dispatch-agentic-runtime`, `dynamic-dispatch-graphs`, `pi-harness-as-dispatch-runtime` — all extend goalforge's wp-05 tier-map / dispatch-template abstraction outward to more providers/topologies; none require touching the map's shape, only adding rows/plugs.
- `efficient-verification-fanout` — directly tunes the wp-07 wave-route panel/adversarial-verify cost, using data from a real run.
- `goalforge-review-assist` + `viz-embedded-review-agent` — the verification-workflow ask's most direct answer, currently just stalled at the human ratify-gate, not conflicting with anything shipped.
- `custom-workflow-engine`, `sdd-feature-chaining-orchestration` — extend wp-12/wp-04's `execution_plan`/runner primitives to dynamic and cross-feature composition, the acknowledged "next lever" goalforge deliberately left YAGNI.

**Conflict or overlap risk:**
- `custom-workflow-engine` **directly conflicts in spirit** with goalforge's own recorded design decision (spec.md, Design point 3 / Out-of-scope list): "Custom workflow engine — stays a deferred, evidence-gated seam; this feature only RECORDS the native posture (Agent-tool fan-out primary; Workflow tool for mechanical parallel stages)." Building it now would need to first show the evidence gate the goalforge spec set as its precondition — pursuing it without that is scope creep against a ratified decision.
- `sdd-feature-chaining-orchestration`'s cross-feature RUNNER is explicitly, twice-ratified, "Out" of goalforge (overview.md Out list + spec Out list) — same conflict pattern: a live idea pushing directly against a decision the shipped feature already closed off as YAGNI. Promoting either idea should re-open that decision explicitly, not silently reverse it.
- `pi-harness-as-dispatch-runtime` and `external-agent-runtime-plugs` (LangChain/ADK) risk duplicating the governance/trust-boundary work wp-05 already built for Claude-native dispatch (owned-files, return-as-DATA contracts) — adopting either means re-deriving those guardrails for a foreign runtime, not reusing them; worth resolving as one integration layer rather than parallel one-offs, especially since `shared-openai-compat-proxy` already proposes a single consolidation point for provider variety.
- `goalforge-review-assist`'s stalled plans directory means `viz-embedded-review-agent`, which depends on it, is currently unpromotable until the parent spec is re-found or re-drafted — a soft blocking conflict, not a design conflict.

**Not evaluated in depth** (surfaced by grep only, titles suggest smaller/orthogonal scope): `goalforge-extend-inventory-stage`, `goalforge-status-state-machine`, `migrate-legacy-to-v2` (mostly historical — already executed as wp-02), `panel-debate-rebuttal-round`, `skill-lifecycle-traceability` (status: promoted, likely already landed elsewhere).

**Sources**: `/home/cunger/10_projects/cogwright/plans/goalforge/{overview,spec,todo,improvement-report,plugin-authority-design,recap}.md` and all 21 `wp-*/` dirs; `docs/handoffs/goalforge-review-assist/2026-07-29-handoff.md`; `docs/handoffs/_archived/goalforge-prototype-native/2026-07-27-handoff.md`; `/home/cunger/10_projects/cogwright/plans/ideas/*.md` (57 files, grep-filtered); `/home/cunger/dotfiles/claude/plans/ideas/*.md` (4 files, none goalforge-core-relevant beyond wayfind/portfolio, which are a sibling planning-chain effort, not goalforge itself).
