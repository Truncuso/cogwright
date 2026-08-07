---
description: "Verify a work package via goalforge-verify — confirms all tasks are verified, findings.md is present, and advances WP status to verified. Fourth step of the goalforge chain."
---

# /verify

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

1. Checks preconditions: all tasks in the WP must be at `status: verified`;
   `findings.md` must exist.
2. Runs the WP's verification and collects evidence (build, tests, lint).
3. On PASS: advances WP `status:` to `verified`.
4. On FAIL: outputs a `goalforge-verify REFUSED` report naming unsatisfied
   preconditions; does not advance status.

## Rules

- No success claim without evidence. A WP reaches `status: verified` only
  through this command, on PASS.
- Feature layout is flat: `<PLANS_ROOT>/<feature>/<wp>/`, resolved per
  `${CLAUDE_PLUGIN_ROOT}/references/schema.md` §PLANS_ROOT resolution.
- Next (on PASS): commit and review the WP's diff.
