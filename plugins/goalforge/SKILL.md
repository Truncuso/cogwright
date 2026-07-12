---
name: goalforge
description: >
  PUBLIC router for the goalforge Spec-Driven Development (SDD) plugin — the
  successor to the legacy dotfiles `sdd-*` skill family. Owns the full
  feature-building chain and routes each request to the right stage skill by
  intent. Use when the user wants to plan, spec, decompose, harden, execute, or
  verify a feature; run the SDD chain end-to-end; or reach any stage capability
  by name. Trigger phrases: "goalforge", "run the SDD chain", "capture this
  feature", "spec this out", "decompose into work packages", "harden this WP",
  "execute this work package", "verify this WP", "archive this feature",
  "recap the plan", "re-decompose on a learning", "onboard this project",
  "watchdog the plans", "index the plans", "arbiter". Reference child skills by
  bare name (`goalforge-<stage>`); the plugin auto-registers them. Do NOT use
  this router to hand-edit `status:`/`goal_approved_version:` — those go through
  the sanctioned stage writers.
metadata:
  version: 1.0.0
---

# goalforge — SDD v2 (router parent)

Goalforge packages Spec-Driven Development as a Claude Code plugin. It is a
**router**: this parent holds the chain map and stage vocabulary; each stage is
a nested child skill under `skills/<stage>/`, reachable by its bare registered
name `goalforge-<stage>`.

Resolve `$COGWRIGHT_ROOT` to your cogwright checkout (default
`~/10_projects/cogwright`). The plugin root is
`$COGWRIGHT_ROOT/plugins/goalforge/`.

## The chain

```
capture → spec → decompose → harden → execute → verify   (→ archive)
```

Human-gated at `spec` (draft → spec) and `harden` (hardened → ready); automated
from `execute` onward. `goalforge-run` orchestrates the whole chain via
`chain.yaml`; the individual stage skills can also be invoked directly for a
single step.

## Capabilities (route by stage)

| Intent | Skill (bare name) | Directory |
|--------|-------------------|-----------|
| Capture free-text intent → feature scaffold, classify `route:` | `goalforge-capture` | `skills/capture/` |
| Design pass → `spec.md`; advance draft → spec (human-gated) | `goalforge-spec` | `skills/spec/` |
| Break the spec into work packages + tasks | `goalforge-decompose` | `skills/decompose/` |
| Drive a WP `spec → hardened → ready` (open questions → zero) | `goalforge-harden` | `skills/harden/` |
| Execute all tasks in a `ready` WP (clean → eval → commit) | `goalforge-execute` | `skills/execute/` |
| The single semantic gate; advance WP `executing → verified` | `goalforge-verify` | `skills/verify/` |
| Reconcile a re-decomposition against verified WPs on a learning | `goalforge-redecompose` | `skills/redecompose/` |
| Archive a completed feature to terminal `archived` | `goalforge-archive` | `skills/archive/` |
| Recap a plan / feature state | `goalforge-recap` | `skills/recap/` |
| Onboard a project into the goalforge conventions | `goalforge-onboard` | `skills/onboard/` |
| Watch the plans tree for drift / stale status | `goalforge-watchdog` | `skills/watchdog/` |
| Index the plans corpus | `goalforge-plan-index` | `skills/plan-index/` |
| Adjudicate a contested harden / verify decision | `goalforge-arbiter` | `skills/arbiter/` |
| Orchestrate the full chain end-to-end | `goalforge-run` | `skills/run/` |

## Naming & aliases

Every legacy `sdd-<name>` skill maps to `goalforge-<name>`; the runner
`sdd-run` maps to `goalforge-run` (directory `skills/run/`, not bare `run`, to
avoid colliding with the existing `run` skill). Scripts move to
`scripts/goalforge-<x>.sh` (one rename: `sdd-goal-route.sh` →
`goalforge-route.sh`). The authoritative row-per-name table is
`references/alias-map.md`. During the migration window the dotfiles `skills/sdd/`
redirect stub and `sdd-*.sh` exec-forward shims keep legacy callers resolving.

## Shared assets (plugin-level siblings of `skills/`)

| You want… | At |
|-----------|-----|
| Frontmatter schemas, status machine | `references/schema.md` |
| File templates | `references/templates/` |
| Validation / goal / routing scripts | `scripts/goalforge-*.sh` |
| Old→new name map | `references/alias-map.md` |

## Entry points

`/spec`, `/plan`, `/implement`, `/verify` remain the human entry points; their
prose references the `goalforge-*` skills.
