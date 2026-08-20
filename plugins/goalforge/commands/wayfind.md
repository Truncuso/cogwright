---
description: "Chart a foggy, multi-session effort into a decision map, then drive a frontier-computed work loop across sessions, and graduate the converged map into goalforge-capture. No slug → discovery: list the active efforts (slug, open count, frontier) to resume. Auto-phase: no map → chart; map present → work (offers graduate on convergence)."
argument-hint: "[<effort-slug>] [chart]"
---

# /wayfind

<!-- AUTHORED SOURCE: packages/goalforge/commands/wayfind.md. The plugin copy
     plugins/goalforge/commands/wayfind.md is GENERATED from this file by
     scripts/goalforge-generate.sh — edit here, never there.
     MIRROR-SYNC OBLIGATION: the maintainer's dotfiles copy is a downstream
     mirror loaded by a direct, non-plugin /wayfind. Any contract change here
     must be propagated there in the same lap. The mirror is NOT byte-identical:
     besides the skill-path form (the plugin route uses ${CLAUDE_PLUGIN_ROOT}),
     it carries an extra Discovery step and a wider argument-hint. evals/e2e.sh
     gates THIS file. -->

Thin dispatch surface into the `wayfind` skill — no logic lives here; the
skill owns chart/work/graduate.

## Steps

1. Parse `$ARGUMENTS`: an optional `<effort-slug>` and an optional `chart`
   literal.
2. **Discovery** — `$ARGUMENTS` empty (no slug). Resolve `<PLANS_ROOT>` (step 4),
   then list the active efforts:
   ```bash
   bash ${CLAUDE_PLUGIN_ROOT}/skills/wayfind/scripts/wayfind-status.sh <PLANS_ROOT>
   ```
   Present each entry of its `efforts` JSON — slug, `open` count, `frontier` —
   and let the user pick one; the pick continues into the auto-phase below for
   that slug. Empty list (`{"efforts": []}`) → no live effort; ask for a new
   effort slug to chart. An entry carrying `error` is reported as-is and never
   blocks the rest.
3. **Explicit chart** — if the second argument is `chart`, invoke the
   `wayfind` skill in chart mode for `<effort-slug>` (re-chart / add
   tickets), regardless of whether a map already exists.
4. **Auto-phase** (a slug, no second argument). Resolve `<PLANS_ROOT>` per
   `${CLAUDE_PLUGIN_ROOT}/references/schema.md` §PLANS_ROOT resolution:
   env `SDD_PLANS_DIR` → project git-root `plans/` → global `~/.claude/plans/`.
   - `<PLANS_ROOT>/<effort-slug>/wayfind/map.md` absent → invoke the `wayfind`
     skill in **chart** mode.
   - `<PLANS_ROOT>/<effort-slug>/wayfind/map.md` present → **work** mode (next
     step).
5. **Work mode** — ALWAYS run the frontier script first, before anything
   else:
   ```bash
   bash ${CLAUDE_PLUGIN_ROOT}/skills/wayfind/scripts/wayfind-frontier.sh <PLANS_ROOT>/<effort-slug>
   ```
   Consume its JSON (`frontier`, `blocked`, `claimed`, `stale_claims`,
   `converged`) per the skill's work flow. If `converged: true`, **offer**
   graduate — the user confirms; never auto-graduate (human stays in the
   loop at the chain boundary).

Full flows (chart / work / graduate, ticket dispatch table, gated
graduation sequence): `${CLAUDE_PLUGIN_ROOT}/skills/wayfind/SKILL.md`. This
command never re-implements frontier or graduation logic.
