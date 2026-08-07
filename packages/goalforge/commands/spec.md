---
description: "Spec authoring via the goalforge chain — scaffold a new feature with goalforge-capture, then draft→spec with goalforge-spec. Human-gated draft→spec transition. First step of the chain."
---

# /spec

Entry point of the goalforge chain: `/spec → /plan → /implement → /verify`.

`/spec` produces a written, reviewed `spec.md` under `<PLANS_ROOT>/<feature>/`.
It writes no code.

## Arguments

`$ARGUMENTS` = a one-line description of what to build. If empty, ask the user
for it before starting.

## Routing

`goalforge-capture` and `goalforge-spec` are PRIVATE children of the `goalforge`
package: they do not trigger by discovery and have no separate Skill-tool name.
Execute them by reading their `SKILL.md` directly and following the procedure
in-session — `${CLAUDE_PLUGIN_ROOT}/skills/capture/SKILL.md` and
`${CLAUDE_PLUGIN_ROOT}/skills/spec/SKILL.md`. `Skill(skill: "goalforge-spec")`
fails with "Unknown skill" — do not retry that call. Delegating through the
`goalforge-run` orchestrator (`${CLAUDE_PLUGIN_ROOT}/skills/run/SKILL.md`) is
the alternative when the whole chain should be driven end-to-end.

**If no `<PLANS_ROOT>/<feature>/` folder exists yet for the described idea:**

1. Run `goalforge-capture` — scaffolds `<feature>/overview.md` with frontmatter
   metadata, captures the raw idea, creates the feature folder in the flat
   layout, and **stamps the chain route** (`route: fast|full`; borderline
   verdicts are confirmed with the user).
2. **Branch on the stamped route:**
   - `route: full` — run `goalforge-spec`: an interview-style design pass
     producing `<feature>/spec.md`; continue below.
   - `route: fast` — **skip `goalforge-spec` entirely.** Follow
     `goalforge-capture` §Fast path: single WP via `goalforge-decompose
     --add-wp`, deterministic gates, `--mode auto` advance, then `/implement`.
     No spec.md, no human spec gate; verification is never skipped.

**If the feature folder already exists (resuming or refining):** run
`goalforge-spec` on it — updates or completes `spec.md` (on a `route: fast`
feature this is the deliberate promotion path: author the spec retroactively
and flip `route: full`).

`<PLANS_ROOT>` resolves per `${CLAUDE_PLUGIN_ROOT}/references/schema.md`
§PLANS_ROOT resolution.

## Human gate (draft → spec, full route)

- Present the full `spec.md` to the user.
- **Wait for explicit user approval** before the feature status advances.
- If the user requests changes, loop `goalforge-spec` until they approve.
- A WP leaves `/spec` at `status: spec` ONLY when both its **outcome** and its
  **verification method** are written. Unresolved unknowns keep it at `draft`.

## Rules

- No code. Terminal state (full route): an approved `spec.md` with work
  packages at `status: spec`. Fast route: one WP at `status: ready` via the
  deterministic gates.
- Layout is FLAT: `<PLANS_ROOT>/<feature>/<wp>/` — no lifecycle folders.
- Next: `/plan` (full route) or `/implement` directly (fast route).
