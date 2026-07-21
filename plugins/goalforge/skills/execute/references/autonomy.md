# sdd-execute — Unattended autonomy (`SDD_AUTONOMY=unattended`)

Consulted only when running under the `autopilot` driver. Interactive
(`SDD_AUTONOMY` unset) behaviour is unchanged.

When `SDD_AUTONOMY=unattended` is set (the `autopilot` driver sets it) there is
no human to answer. Everywhere this skill would **escalate via
`AskUserQuestion`** — `outer_max_iter` exhausted (the `blocked_stop` case),
dependency deadlock, the inner retry cap, a failing eval, a fail-closed judge
with no `block_on` — append the blocker to `findings.md` **as it already does**,
then **stop cleanly (PARK) instead of calling `AskUserQuestion`**. Status is
never advanced past a blocker.

The `strategy: human` goal gate already parks (writes the gate to `findings.md`
and exits) — that path is unchanged; the `autopilot` driver elevates it to a
full handoff. Evidence-decidable goal strategies
(`deterministic | numeric | judge`) run unchanged — they are not human gates.

See `~/.claude/skills/autopilot/references/autonomy-policy.md`.
