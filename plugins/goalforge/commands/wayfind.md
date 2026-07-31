---
description: Chart a foggy, multi-session effort into a decision map, then drive a frontier-computed work loop across sessions, and graduate the converged map into goalforge-capture. Auto-phase: no map → chart; map present → work (offers graduate on convergence).
argument-hint: "<effort-slug> [chart]"
---

# /wayfind

<!-- AUTHORITATIVE command file (hand-authored, generator PRESERVE list).
     MIRROR-SYNC OBLIGATION: the dotfiles copy ~/.claude/commands/wayfind.md
     (repo /home/cunger/dotfiles/claude) is the downstream mirror loaded by a
     direct, non-plugin /wayfind through the ~/.claude/skills/wayfind symlink.
     Any contract change here must be propagated there in the same lap; only
     the skill-path form differs (${CLAUDE_PLUGIN_ROOT}/skills/wayfind/ here,
     ~/.claude/skills/wayfind/ there). evals/e2e.sh gates THIS file. -->

Thin dispatch surface into the `wayfind` skill — no logic lives here; the
skill owns chart/work/graduate.

## Steps

1. Parse `$ARGUMENTS`: `<effort-slug>` and an optional `chart` literal.
2. **Explicit chart** — if the second argument is `chart`, invoke the
   `wayfind` skill in chart mode for `<effort-slug>` (re-chart / add
   tickets), regardless of whether a map already exists.
3. **Auto-phase** (no second argument). Resolve `<PLANS_ROOT>` per
   `~/.claude/skills/goalforge/references/schema.md` §PLANS_ROOT resolution:
   env `SDD_PLANS_DIR` → project git-root `plans/` → global `~/.claude/plans/`.
   - `<PLANS_ROOT>/<effort-slug>/wayfind/map.md` absent → invoke the `wayfind`
     skill in **chart** mode.
   - `<PLANS_ROOT>/<effort-slug>/wayfind/map.md` present → **work** mode (next
     step).
4. **Work mode** — ALWAYS run the frontier script first, before anything
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
