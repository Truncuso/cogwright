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
  /verify directly (they drive the chain via the goalforge/run orchestrator).
metadata:
  version: 3.0.0
---

# goalforge — Spec-Driven Development chain (LOCAL authority)

The **goalforge** package carries the authoritative SDD (Spec-Driven
Development) planning chain in this repo. The LOCAL dotfiles tree is the source
of truth; the cogwright `goalforge` plugin is a downstream **export**, synced as
the last step (user decision 2026-07-16, `plans/suite-extraction/overview.md`).

This is a **v2 package**: a PUBLIC parent (this file) owning PRIVATE nested
children. Children do not trigger by discovery — they are invoked by name from
the entry commands and the orchestrator, or referenced here.

## Children (name → stage → path)

| Skill | Stage | Path |
|-------|-------|------|
| `goalforge-capture` | free-text intent → `overview.md` (draft) + route | `capture/` |
| `goalforge-spec` | design pass → `spec.md`, draft → ready | `spec/` |
| `goalforge-decompose` | spec → work packages + tasks; `--add-wp` mode | `decompose/` |
| `goalforge-harden` | WP spec → hardened → ready (review + interview) | `harden/` |
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
| Frontmatter schemas, status machine | `~/.claude/skills/goalforge/references/schema.md`, `references/state-machine.md` |
| File templates | `~/.claude/skills/goalforge/references/templates/` |
| Old `sdd-*` → `goalforge-*` name map | `~/.claude/skills/goalforge/references/alias-map.md` |
| Validation / goal / routing scripts | `~/.claude/skills/goalforge/scripts/goalforge-*.sh` |

## Entry points

`/spec`, `/plan`, `/implement`, `/verify` are the human entry points; they drive
the chain via the `goalforge-run` orchestrator (`run/`).

## Alias layer (copy-first migration)

The legacy `sdd-*` skills and `sdd-*.sh` scripts remain in place as
LOCAL-pointing aliases (redirect stubs / exec-forward shims to this package),
with one script rename: `sdd-goal-route.sh` → `goalforge-route.sh`. Deletion of
the `sdd-*` sources is deferred behind a separate human sign-off gate, and the
alias layer outlives external consumers still pinned to `sdd-*` names (tangram
ADR-0008 `sdd-status --json`; ProSIP `sdd-validate.sh --strict`).
