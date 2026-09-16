# goalforge hooks — registration rationale

`hooks.json` registers these hooks. Claude Code's hook schema accepts
`description` only at the **top level** of `hooks.json` — a `description` on an
individual matcher group is an unknown key, is ignored, and makes the harness
print a warning at session start. So the per-group rationale lives here instead,
one section per matcher group, in registration order.

Every hook below obeys the zero-breakage contract: exit 0 on any internal error,
exit 2 only to block deliberately.

## PreToolUse

### `Agent|Workflow` → `goalforge-launch-gate.sh`

Launch gate. Refuses a NEW Agent/Workflow dispatch when the remaining 5h quota is
below the configured threshold (default 10%, see README §Install) — a dispatch
launched below it dies on the rate limit and loses its work.

Quota comes from `goalforge-quota-read.sh`, which is an adapter and is
deliberately NOT registered in `hooks.json`. Unknown quota, or the gate disabled
via its README-documented switch, exits 0 silently; the explanatory WARN prints
once per session.

### `Edit|Write|MultiEdit|mcp__lean-ctx__ctx_patch|mcp__lean-ctx__ctx_call` → `goalforge-single-writer.sh`

Single-writer guard. Blocks tool-surface mutation of `status:` and
`goal_approved_version:` on plan files under a resolved `PLANS_ROOT`.

This is the BLANKET field guard: it simulates Edit, MultiEdit, Write and
`ctx_patch` payloads alike (`ctx_call` unwrapped one level), which is why the two
status-edge guards below can stay narrow. Fast-paths to exit 0 unless the edited
file is under a resolved `PLANS_ROOT`.

### `Edit` → `goalforge-transition-guard.sh`, `goalforge-open-questions-gate.sh`

Status-edge guards. Matcher is `Edit` ONLY because both read an Edit payload's
`old_string`/`new_string` and can evaluate nothing else:

- `transition-guard` blocks an illegal status edge.
- `open-questions-gate` blocks `-> ready` while an open question is unresolved.

A status change arriving via Write or MultiEdit is caught by the single-writer
group above, which blocks the field outright. Each fast-paths to exit 0 unless
the edited file is under a resolved `PLANS_ROOT`.

## SessionStart

### `startup|resume|clear|compact` → `goalforge-context-fill.sh`, `goalforge-session-start.sh`

Session orientation, owned by the plugin so installing or removing it takes the
injection with it:

- `context-fill` prints ONE estimate of how full the window already is.
- `session-start` prints the <=15-line orientation block (active features plus
  frontier WP, ready handoffs, wayfind open/frontier counts, one routing line),
  privacy-scrubbed.

Both exit 0 always and print nothing when there is nothing to say;
`GOALFORGE_SESSION_START=0` disables the orientation block.

## PostToolUse

### `Edit|Write|MultiEdit` → `goalforge-frontmatter-touch.sh`

Bumps `stage_updated:` to today on an edited `plans/**` `.md`. Reads only the
payload's `file_path`, so all three tools are in scope. Fast-paths to exit 0
unless the edited file is under a resolved `PLANS_ROOT`.

## Not registered here

- `goalforge-plans-root.sh` — shared library sourced by the hooks above, not a
  hook itself.
- `goalforge-quota-read.sh` — quota adapter for the launch gate.
- `goalforge-pre-commit.sh` — git hook, installed into `.git/hooks/`, not a
  Claude Code hook.

Regression tests for each hook live in `tests/`.
