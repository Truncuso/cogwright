---
description: "Execute ONE work package via goalforge-execute: dispatch its checklist to one owning agent, run the WP verification command, land exactly one commit, and leave the WP at `implemented`. Quality sign-off is /verify. With no argument, picks the next ready WP whose dependencies are satisfied. NOT the whole chain — that is /goalforge-run; decomposing a spec is /plan."
---

# /implement

> `${CLAUDE_PLUGIN_ROOT}` is the installed plugin root (`plugins/goalforge/`),
> where each child skill lives at `skills/<child>/SKILL.md`. The variable is
> unset on a direct load from the source package — there read
> `packages/goalforge/<child>/SKILL.md` (the source package has no `skills/`
> directory; `scripts/goalforge-generate.sh` adds it when generating the plugin).

Execute a work package through the full goalforge sub-cycle.

## Arguments

`$ARGUMENTS` = WP identifier (e.g. `wp-03-resolver-core`). If empty, picks the
next `status: ready` WP in the current feature whose `depends_on` are all
satisfied.

## Routing

`goalforge-execute` is a PRIVATE child of the `goalforge` package: it does not
trigger by discovery and has no separate Skill-tool name. Execute it by reading
`${CLAUDE_PLUGIN_ROOT}/skills/execute/SKILL.md` directly and following the
procedure in-session. Delegating through the `goalforge-run` orchestrator
(`${CLAUDE_PLUGIN_ROOT}/skills/run/SKILL.md`) is the alternative when the whole
chain should be driven end-to-end.

Run `goalforge-execute` on the named (or auto-selected) WP:

1. Reads `<wp>/overview.md` — asserts `status: ready` (or resumes an
   `executing` WP); aborts on any other status.
2. Dispatches the `## Checklist` to ONE owning agent at an explicitly resolved
   model + effort, splitting into non-committing batches only under the C5
   conditions (more than 8 owned files, or disjoint `{files:}` + `parallel: true`).
3. Runs the WP's `goal.verification.command`, re-dispatching on failure within
   the stop rule (goal met | 2 attempts | token ceiling | premise-blocked | same
   gate twice).
4. Lands exactly ONE conventional commit and advances the WP to `implemented`.

`/implement` never writes `status: verified` — gates A/B/C in `/verify` do.
One WP at a time. If stuck, ask — don't guess.

## Rules

- The WP is the unit of work; never widen scope mid-execution.
- Feature layout is flat: `<PLANS_ROOT>/<feature>/<wp>/`, resolved per
  `${CLAUDE_PLUGIN_ROOT}/references/schema.md` §PLANS_ROOT resolution.
- Next: `/verify` (runs `goalforge-verify` — `implemented → verified`).
