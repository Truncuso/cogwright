---
name: goalforge
description: "Router and index for the goalforge (Spec-Driven Development) planning skill chain, v3.0.0. Points to the child skills (capture → spec → decompose → harden → execute → verify plus the support stages) and holds the shared schema, templates, and specialist map. Use goalforge when you need to find the right planning skill, understand the folder/frontmatter contract, or are invoked via /spec /plan /implement /verify."
---

# goalforge — Skill Chain Index

**Chain:** `capture → spec → decompose → harden → execute → verify`

Orchestrated by `goalforge-run` (`run/chain.yaml`). Flat on-disk layout:
`plans/<feature>/<wp-id>/files`. Status lives in frontmatter — no lifecycle folders.
`goalforge` is the canonical and ONLY name of this chain; the legacy `sdd-*`
aliases were retired 2026-07-21.

## Child Skills

| Skill | Contract |
|---|---|
| `goalforge-capture` | Free-text intent → feature `overview.md` (status: draft) + route |
| `goalforge-spec` | Write `spec.md`; define measurable goal + verification criteria (draft → ready) |
| `goalforge-decompose` | Break the spec into WP `overview.md` files — WP overview + checklist, no task stubs; `--add-wp` mode |
| `goalforge-harden` | Resolve open questions; advance to `ready` |
| `goalforge-execute` | Dispatch one owner for the whole WP; one commit, no per-task checkpoint; `ready`/`executing` → `implemented` |
| `goalforge-verify` | Three gates (A deterministic, B fresh-context review, C goal judge) over the WP's single commit; `implemented → verified` |
| `goalforge-redecompose` | Reconcile a re-decomposition on a learning event |
| `goalforge-archive` | completed → archived (supersede edges) |
| `goalforge-onboard` | Onboard an existing repo into the chain |
| `goalforge-plan-index` | Plan index generation |
| `goalforge-run` | Chain orchestrator (route-aware); wires the chain via `chain.yaml` |

`prototype/` and `wayfind/` are non-chain tenants co-located in this package
(not chain stages). Details: `SKILL.md`.

## Shared References

| File | Purpose |
|---|---|
| `references/schema.md` | v3 frontmatter schemas, edge vocabulary |
| `references/state-machine.md` | Status machine + transition rules |
| `references/templates/` | Canonical file templates (frontmatter-first, placeholder tokens) |
| `references/dispatch.yaml` | per-stage model, effort, provider, endpoint, egress class |

## Status Machine (WP)

`draft → spec → hardened → ready → executing → verified`

`draft → ready` (feature gate) and `hardened → ready` (WP gate) are human-gated. `archived` is
terminal, reached only via explicit user action. Details:
`references/state-machine.md`.

## Related Skills

| Skill | Relationship |
|---|---|
| `implement` | Reused inside `goalforge-execute` sub-cycle |
| `verify-and-simplify` | Reused inside `goalforge-execute` sub-cycle |
| `wayfind` | Optional pre-capture on-ramp; graduates a converged decision map into `goalforge-capture` |
| `prototype` | Co-tenant; spike/prototype execution in a worktree |
| `goalforge-validate.sh` | Schema + status-vs-evidence + link + staleness checks |
