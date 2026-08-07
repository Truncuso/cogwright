---
description: "Execute a work package via goalforge-execute — read the WP, dispatch tasks, verify, advance status to verified. With no argument, picks the next ready WP whose depends_on are satisfied."
---

# /implement

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

1. Reads `<wp>/overview.md` — asserts `status: ready`; aborts if not.
2. Dispatches tasks (sequential or parallel wave) using the specialist and
   model routing from the WP frontmatter.
3. Loops: implement → verify → fix → re-verify until clean.
4. Advances the WP `status:` to `verified` on pass.

One WP at a time. If stuck, ask — don't guess.

## Rules

- The WP is the unit of work; never widen scope mid-execution.
- Feature layout is flat: `<PLANS_ROOT>/<feature>/<wp>/`, resolved per
  `${CLAUDE_PLUGIN_ROOT}/references/schema.md` §PLANS_ROOT resolution.
- Next: `/verify` (runs `goalforge-verify`).
