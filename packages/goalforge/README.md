---
name: sdd
description: "Router and index for the SDD (Spec-Driven Development) planning skill chain. Points to the six child skills (capture → spec → decompose → harden → execute → verify) and holds the shared schema, templates, and specialist map. Use sdd when you need to find the right planning skill, understand the folder/frontmatter contract, or are invoked via /spec /plan /implement /verify."
---

# SDD — Skill Chain Index

**Chain:** `capture → spec → decompose → harden → execute → verify`

Orchestrated by `sdd-run` (sibling `chain.yaml`). Flat on-disk layout:
`plans/<feature>/<wp-id>/files`. Status lives in frontmatter — no lifecycle folders.

## Child Skills

| Skill | Contract |
|---|---|
| `sdd-capture` | Elicit raw input; write the feature `overview.md` (status: draft) |
| `sdd-spec` | Write `spec.md`; define measurable goal + verification criteria (status: draft → spec) |
| `sdd-decompose` | Break the spec into WP `overview.md` files with task stubs |
| `sdd-harden` | Grill each WP via `interview-loop`; resolve open questions; advance to `ready` |
| `sdd-execute` | Run the execute sub-cycle per task (pick-agent → dispatch → checkpoint → verify) |
| `sdd-verify` | Run `superpowers:verification-before-completion`; mark WP `verified` |

## Shared References

| File | Purpose |
|---|---|
| `references/schema.md` | v3 frontmatter schemas, status machine, edge vocabulary |
| `references/templates/` | 7 canonical file templates (frontmatter-first, placeholder tokens) |
| `references/specialist-map.yaml` | extension + tag → specialist agent routing seed |

## Status Machine (WP)

`draft → spec → hardened → ready → executing → verified`

`draft → spec` and `hardened → ready` are human-gated. `archived` is
terminal, reached only via explicit user action. Details: `references/schema.md`.

## Related Skills

| Skill | Relationship |
|---|---|
| `interview-loop` | Delegated to by `sdd-harden` |
| `implement` | Reused inside `sdd-execute` sub-cycle |
| `verify-and-simplify` | Reused inside `sdd-execute` sub-cycle |
| `sdd-run` | Orchestrator; wires the chain via `chain.yaml` |
| `sdd-validate.sh` | Schema + status-vs-evidence + link + staleness checks |
