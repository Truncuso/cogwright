# goalforge-execute — Dispatch resolution detail

Behind the `goalforge-pick-agent.py --task <wp>/overview.md --role implement`
call in `SKILL.md` §3. Consulted when a dispatch does not resolve cleanly, or
when a non-code WP needs its specialist route.

## Resolution order (enforced by the module)

1. `by_tag` on the WP's `tags:` → specialist from `references/specialist-map.yaml`.
2. `by_task_type` on `task_type:` (`research → research-analyst`,
   `ops → devops-engineer`, `docs → doc-updater`). A `code` WP has no entry and
   falls through to `by_extension`.
3. `by_extension` on the extensions in `owned_files:`.
4. The `discover` callable — a `general-purpose` sonnet subagent that names the
   fitting specialist from the known list, or `none`.
5. `none` → `EscalationRequired`, surfaced via `AskUserQuestion`. **No silent
   hard default.**

`pick_agent` selects the *specialist*. The verification strategy comes from the
WP's own `goal.verification.strategy` and is never inferred here.

## Model + effort

Resolved from the canonical role→tier map (`ROLE_TIER` in
`scripts/goalforge-pick-agent.py`; human-readable projection in
`references/tier-map.md`), then instantiated: `low → sonnet@low`,
`medium → opus@low`, `high → opus@high`. Blast radius (auth, schema, migration,
exported symbol, owned_files > 8) deterministically forces the `high` tier for
every role EXCEPT `implement` — a sensitive change is never silently
downgraded. `implement` is register-driven, not complexity-driven (wp-01/T17
dropped the per-task `complexity` input entirely): `register: spike` →
`low`; `register: production` → `sonnet@medium`, escalating to `opus@low`
(never `opus@high`) on `severity: HIGH` or blast radius, matching the Dispatch
Routing Matrix's "build ... blast radius → opus/low". An unknown role or
profile raises `EscalationRequired`; there is no silent fallback. Every brief
states model AND effort explicitly, never the agent `.md` frontmatter default.

## Dispatch surface

Pick by which knobs the surface exposes (Dispatch Routing Matrix,
`references/rules/performance.md`):

- **Agent tool** — one subagent or a small batch. Sets `model` per agent;
  **effort inherits the session**, so it is correct only when the resolved
  effort equals the session effort.
- **Workflow tool** — the only surface with a per-agent effort knob
  (`opts.model` + `opts.effort`). Use it when a batch mixes efforts.
- **Headless CLI** — cross-provider routes only; `--model` plus settings per the
  provider leaf contract. Foreign and local providers are propose-only.

## Route + map proposals

The dispatch route is `api` (default) or `ollama`; `ollama` requires a passing
health check and a failure raises `EscalationRequired` — no silent API fallback. A
`proposed_map_entry` in the result is appended to `<wp>/findings.md` for human
review, never auto-merged into `specialist-map.yaml`.
