---
description: "Verify a work package via goalforge-verify — gate A deterministic (lint, typecheck, verification command, diff within owned files), gate B one fresh-context review of the WP diff, gate C goal judge plus one foreign second opinion, then advances the WP from implemented to verified. Fourth step of the goalforge chain."
---

# /verify

> `${CLAUDE_PLUGIN_ROOT}` is the installed plugin root (`plugins/goalforge/`),
> where each child skill lives at `skills/<child>/SKILL.md`. The variable is
> unset on a direct load from the source package — there read
> `packages/goalforge/<child>/SKILL.md` (the source package has no `skills/`
> directory; `scripts/goalforge-generate.sh` adds it when generating the plugin).

Verify a work package in the goalforge chain.

## Arguments

`$ARGUMENTS` = WP identifier (e.g. `wp-03-resolver-core`). If empty, verifies
the current or most-recently-executed WP.

## Routing

`goalforge-verify` is a PRIVATE child of the `goalforge` package: it does not
trigger by discovery and has no separate Skill-tool name. Execute it by reading
`${CLAUDE_PLUGIN_ROOT}/skills/verify/SKILL.md` directly and following the
procedure in-session. Delegating through the `goalforge-run` orchestrator
(`${CLAUDE_PLUGIN_ROOT}/skills/run/SKILL.md`) is the alternative when the whole
chain should be driven end-to-end.

Run `goalforge-verify` on the named WP:

1. Checks the precondition: the WP is at `status: implemented` (one commit
   landed, its verification command green). Any other status is refused.
2. Runs the three gates over the WP's cumulative diff — A deterministic (lint,
   type-check, `goal.verification.command`, every diff path inside
   `owned_files:`), B one review in a fresh context on a model other than the
   executor's, C the goal judge plus one foreign second opinion. Each gate
   emits a `gate.result` row; judge/second-opinion disagreement goes to you.
3. On PASS: advances WP `status:` to `verified` and emits `wp.verified`. If this
   was the last WP, runs the whole-feature integration review first.
4. On FAIL: records the blocking findings in `<wp>/findings.md` and outputs a
   `goalforge-verify REFUSED` report; does not advance status.

## Rules

- No success claim without evidence. A WP reaches `status: verified` only
  through this command, on PASS.
- Feature layout is flat: `<PLANS_ROOT>/<feature>/<wp>/`, resolved per
  `${CLAUDE_PLUGIN_ROOT}/references/schema.md` §PLANS_ROOT resolution.
- Next (on PASS): commit and review the WP's diff.
