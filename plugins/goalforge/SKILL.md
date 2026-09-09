---
name: goalforge
description: >
  PUBLIC front door for the goalforge Spec-Driven Development (SDD) chain:
  capture → spec → decompose → harden → execute → verify. Use to explain the
  chain, pick the stage child, or locate schemas, templates, and scripts.
  Triggers: "explain goalforge", "explain SDD", "which goalforge skill",
  "where are the goalforge templates". Not for RUNNING the chain — use
  /spec /plan /implement /verify or /goalforge-run.
metadata:
  skill-kind: preference
  version: 4.0.0
---

# goalforge — Spec-Driven Development chain (LOCAL authority)

`packages/goalforge/` is the authored source of truth; `plugins/goalforge/` is
its generated artifact (`scripts/goalforge-generate.sh`, drift-gated). The
maintainer's dotfiles reach this package via a per-machine symlink.

This is a **PUBLIC-parent package**: a PUBLIC parent (this file) owning PRIVATE
nested children. Children do not trigger by discovery — they are invoked by
name from the entry commands and the orchestrator, or referenced here.

Contract: `plans/<feature>/spec.md` carries the Interface Contract C1-C7 (WP
shape, frontmatter, gate set, stop rules, dispatch unit, trace, human
touchpoints); `references/schema.md` and `references/state-machine.md` are the
field and status authorities. A WP is one `overview.md` with 8 fixed sections
and a checklist; there are no task files.

## Children (name → stage → path)

| Skill | Stage | Path |
|-------|-------|------|
| `goalforge-capture` | free-text intent → `overview.md` (draft) | `capture/` |
| `goalforge-spec` | design pass → `spec.md` with goal + behaviors, draft → ready | `spec/` |
| `goalforge-decompose` | spec → WP overviews with checklists; `--add-wp` mode | `decompose/` |
| `goalforge-harden` | WP spec → hardened → ready (gates G1-G4, 2-round stop) | `harden/` |
| `goalforge-execute` | ready → executing → implemented (one owner, one commit) | `execute/` |
| `goalforge-verify` | implemented → verified (gates A/B/C) | `verify/` |
| `goalforge-redecompose` | reconcile a re-decomposition on a learning event | `redecompose/` |
| `goalforge-archive` | completed → archived (supersede edges) | `archive/` |
| `goalforge-onboard` | onboard an existing repo into the chain | `onboard/` |
| `goalforge-plan-index` | plan index generation | `plan-index/` |
| `goalforge-run` | chain driver by status | `run/` |

## Shared assets

| You want… | At |
|-----------|-----|
| Frontmatter schema, status machine | `${CLAUDE_PLUGIN_ROOT}/references/schema.md`, `references/state-machine.md` |
| File templates | `${CLAUDE_PLUGIN_ROOT}/references/templates/` |
| Trace event schema | `${CLAUDE_PLUGIN_ROOT}/references/trace-events.md` |
| Gate, hash, transition scripts | `${CLAUDE_PLUGIN_ROOT}/scripts/goalforge-*.sh` |
| Gate sabotage pairs + harness | `hooks/tests/`, `scripts/tests/`, `evals/run.sh` |

## Entry points

`/spec`, `/plan`, `/implement`, `/verify` are the human entry points; each is a
thin dispatch surface that reads the stage child's `SKILL.md` directly and runs
the procedure in-session. `/goalforge-run` pins the `goalforge-run` driver
(`run/`) for the whole chain.

`prototype/` and `wayfind/` are non-chain tenants co-located in this package,
reachable via the installer's top-level symlinks.

## Legacy naming

The `sdd-*` skill/script aliases were RETIRED 2026-07-21. Historic
name map: `references/alias-map.md`.

## Gotchas

- **`goalforge-run` is PUBLIC-PINNED as `/goalforge-run`, not as a Skill-tool
  name.** It is a PRIVATE nested child with no discovery entry; invoking
  `goalforge-run` by name answers "Unknown skill". `commands/goalforge-run.md`
  loads `run/SKILL.md` by path.
- **No nested child resolves via the Skill tool.** Discovery is one level deep:
  only `goalforge`, `prototype`, and `wayfind` are discoverable. Every other
  name in the Children table is reached by reading `<child>/SKILL.md` by path.
- **A gate that does not emit `gate.result` is not a gate.** Every PreToolUse
  guard and gate script emits through `scripts/goalforge-trace-emit` and ships
  a sabotage pair (known-bad exit 2, known-good exit 0) under `evals/run.sh`.
  `goalforge-pre-commit.sh` (git hook) and `goalforge-frontmatter-touch.sh`
  (non-blocking) ship pairs but emit no row.
