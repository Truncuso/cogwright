---
name: goalforge
description: >
  PUBLIC front door for the goalforge Spec-Driven Development (SDD) planning
  chain — the LOCAL, authoritative source of truth for the capture → spec →
  decompose → harden → execute → verify workflow. Use when explaining what the
  SDD/goalforge chain is, how the planning workflow works, which child skill to
  invoke for a given stage, or where the schemas, templates, and scripts live.
  Routes names to the PRIVATE nested children under this package. Trigger
  phrases: "explain SDD", "explain goalforge", "how does the planning chain
  work", "which goalforge skill should I use", "show me the planning workflow",
  "spec-driven development overview", "what does goalforge-harden do", "what's
  the difference between goalforge-spec and goalforge-decompose", "where are the
  goalforge templates". Do NOT use to RUN the chain — use /spec /plan /implement
  /verify directly (they dispatch the stage children directly; the goalforge/run
  orchestrator is the end-to-end alternative).
metadata:
  skill-kind: preference
  version: 3.0.0
---

# goalforge — Spec-Driven Development chain (LOCAL authority)

The **goalforge** package carries the authoritative SDD (Spec-Driven
Development) planning chain. `packages/goalforge/` is the authored source of
truth; `plugins/goalforge/` is its generated artifact (`scripts/goalforge-generate.sh`,
drift-gated). The maintainer's dotfiles reach this package via a per-machine
symlink (installer contributor mode).

This is a **PUBLIC-parent package** (`metadata.version` 3.0.0): a PUBLIC parent
(this file) owning PRIVATE nested children. Children do not trigger by
discovery — they are invoked by name from the entry commands and the
orchestrator, or referenced here.

## Children (name → stage → path)

| Skill | Stage | Path |
|-------|-------|------|
| `goalforge-capture` | free-text intent → `overview.md` (draft) + route | `capture/` |
| `goalforge-spec` | design pass → `spec.md`, draft → ready | `spec/` |
| `goalforge-decompose` | spec → work packages + tasks; `--add-wp` mode | `decompose/` |
| `goalforge-harden` | WP spec → hardened → ready (review + interview) | `harden/` |
| `goalforge-interview` | fidelity-aware goal-hardening grilling (wraps the interview plugin engine) | `interview/` |
| `goalforge-execute` | run ready-WP tasks → implemented | `execute/` |
| `goalforge-verify` | executing → verified (single semantic gate) | `verify/` |
| `goalforge-redecompose` | reconcile a re-decomposition on a learning event | `redecompose/` |
| `goalforge-archive` | completed → archived (supersede edges) | `archive/` |
| `goalforge-recap` | feature/WP status recap | `recap/` |
| `goalforge-onboard` | onboard an existing repo into the chain | `onboard/` |
| `goalforge-watchdog` | drift/health monitoring | `watchdog/` |
| `goalforge-plan-index` | plan index generation | `plan-index/` |
| `goalforge-arbiter` | adjudication support | `arbiter/` |
| `goalforge-run` | chain orchestrator (route-aware) | `run/` |

## Shared assets

| You want… | At |
|-----------|-----|
| Frontmatter schemas, status machine | `${CLAUDE_PLUGIN_ROOT}/references/schema.md`, `references/state-machine.md` |
| File templates | `${CLAUDE_PLUGIN_ROOT}/references/templates/` |
| Old `sdd-*` → `goalforge-*` name map | `${CLAUDE_PLUGIN_ROOT}/references/alias-map.md` |
| Validation / goal / routing scripts | `${CLAUDE_PLUGIN_ROOT}/scripts/goalforge-*.sh` |

## Entry points

`/spec`, `/plan`, `/implement`, `/verify` are the human entry points; each is a
thin dispatch surface that reads the stage child's `SKILL.md` directly and runs
the procedure in-session. The `goalforge-run` orchestrator (`run/`) is the named
alternative for driving the whole chain end-to-end.

Note: `prototype/` and `wayfind/` are non-chain tenants co-located in this
package (not chain stages), reachable via the installer's top-level symlinks
(Interface Contract §5).

Note: `brief/` is a chain-support asset — not a chain stage (no status edge)
and not a co-tenant (no top-level symlink): the `brief` skill authors task
briefs that `goalforge-execute` consumes.

## Legacy naming

The `sdd-*` skill/script aliases were RETIRED 2026-07-21. Historic
name map: `references/alias-map.md`.

## Gotchas

- **Route vocabulary is `fast | standard | wave` — nothing else.** That set is
  what `scripts/goalforge-route.sh` actually emits. Prose elsewhere in the
  package has said `full` (`run/chain.yaml`, `commands/spec.md`) and `one-go`
  (`run/SKILL.md`); neither value is ever produced by the classifier. Trust the
  classifier's output, not the prose, and read a route value as one of the three.
- **`goalforge-run` is named but not reachable by the Skill tool.** It is a
  PRIVATE nested child with no `commands/` wrapper and no discovery entry, so
  invoking `goalforge-run` by name answers "Unknown skill". The only way in is
  to read `run/SKILL.md` by path and follow it in-session. Prefer `/spec`,
  `/plan`, `/implement`, `/verify` for stage-at-a-time work.
- **No nested child here resolves via the Skill tool.** Discovery is one level
  deep: only `goalforge`, `prototype`, and `wayfind` are discoverable. Every
  other name in the Children table — `goalforge-capture`, `goalforge-harden`,
  and the rest — must be reached by reading `<child>/SKILL.md` by path. A
  command or brief that says "invoke goalforge-<stage>" is stating a dispatch
  that the runtime cannot perform.
