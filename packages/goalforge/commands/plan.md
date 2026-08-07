---
description: "Decompose the current feature's spec.md into work packages via goalforge-decompose, then harden WPs to ready via goalforge-harden. Human-gated hardened→ready transition. WAIT for user confirmation before any implementation."
---

# /plan

Decompose and harden the current feature's spec into work packages before any
code is written.

## Routing

`goalforge-decompose` and `goalforge-harden` are PRIVATE children of the
`goalforge` package: they do not trigger by discovery and have no separate
Skill-tool name. Execute them by reading their `SKILL.md` directly —
`${CLAUDE_PLUGIN_ROOT}/skills/decompose/SKILL.md` and
`${CLAUDE_PLUGIN_ROOT}/skills/harden/SKILL.md` — and following the procedure
in-session. `Skill(skill: "goalforge-decompose")` fails with "Unknown skill" —
do not retry that call. Delegating through the `goalforge-run` orchestrator
(`${CLAUDE_PLUGIN_ROOT}/skills/run/SKILL.md`) is the alternative when the whole
chain should be driven end-to-end.

1. **`goalforge-decompose`** — reads the feature's `spec.md` (feature must be at
   `status: ready`) and produces WP folders with frontmatter-first `overview.md`
   files. Layout is FLAT — no lifecycle folders. For a **single mid-flight WP
   add**, use `goalforge-decompose --add-wp`; `goalforge-redecompose`
   (`${CLAUDE_PLUGIN_ROOT}/skills/redecompose/SKILL.md`) handles restructures.
2. **`goalforge-harden`** — offered after decomposition. Drives open questions
   to zero (a question may stay open only as a recorded `[risk-accepted]`
   risk), appending findings to each WP. Advances WPs from `spec → hardened`.

**Present the decomposed plan and WAIT for explicit user confirmation** before
advancing any WP to `ready` — except WPs in the signal-scoped class (`simple` +
severity ≤ MEDIUM + non-migration), which `goalforge-harden` auto-advances with
a `--mode auto` ledger record.

A `route: fast` feature normally skips `/plan` entirely — its single WP is
authored and gated at capture time. Invoke `/plan` on it only when promoting to
the full route.

## Rules

- No code. Terminal state is a set of WPs at `status: ready` (or `hardened`
  pending the approval gate).
- Feature layout is flat: `<PLANS_ROOT>/<feature>/<wp>/`, resolved per
  `${CLAUDE_PLUGIN_ROOT}/references/schema.md` §PLANS_ROOT resolution.
- Next: `/implement` (runs `goalforge-execute` on the next `ready` WP).
