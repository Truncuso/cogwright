# goalforge-execute — Dispatch resolution detail (Step 4)

Full detail behind Step 4's `pick_agent` call. Consulted when a dispatch does
not resolve cleanly or a non-code / writing WP needs its specialist route.

## Injected callables

- `discover`: a `general-purpose` Sonnet 4.6 subagent. Prompt: "Which specialist
  fits this task? Return one of {known_list} or `none`. Also estimate complexity
  low|medium|high." Pass the task spec and touched-file list as context.
- `ollama_health`: the `ollama-dispatch` health check — returns `True` when
  `http://localhost:11434` is reachable.

## Resolution order (enforced by the module)

1. `by_tag` match on task `tags` → specialist from `specialist-map.yaml`.
2. `by_task_type` match on the WP/task `task_type` → specialist (non-code
   routes: `research → research-analyst`, `ops → devops-engineer`, …). Pass the
   WP's `task_type` to `pick_agent` so a non-code WP dispatches to its
   specialist. A `code` WP has no `by_task_type` entry and falls through to
   `by_extension` — the code path is unchanged. **`writing` is kind-dependent:**
   it resolves via a second-level `by_writing_kind` map keyed on the WP's
   `writing_kind` tag (`scientific → scientific-literature-researcher`,
   `research → research-analyst`, `docs → doc-updater`); an untagged writing WP
   falls through to discovery/escalation so a human (or the dispatching agent)
   picks the kind. Some targets are skills rather than subagents — dispatch a
   skill-invoking agent (general-purpose / other-model per the work-packages
   plan) for those.
3. `by_extension` match on touched file extensions → specialist.
4. `discover` callable → specialist or `"none"`.
5. If `"none"` → `EscalationRequired`; surface via `AskUserQuestion`.
   **No silent hard default.**

The evaluator **strategy** is resolved separately by the WP-02 router
(`default_strategy_for(task_type)` in `goalforge-goal-eval.py`) — `pick_agent` selects
the *specialist*, never the strategy. There is one task_type→strategy map and it
lives in the router.

## Model tier + effort

Resolved from the **canonical role→tier map** (single source of truth —
`goalforge/scripts/goalforge-pick-agent.py`, `resolve_role_tier`). The `implement` role is
**complexity-driven**, so the discovery callable supplies the `complexity`
estimate when frontmatter omits it; **blast radius**
(auth/schema/migration/exported-API/3+ files) deterministically forces the high
tier. **No silent fallback** — missing complexity with no estimate, or an unknown
role/profile, raises `EscalationRequired`. Other dispatched roles (`wp-verify`,
`simplify`, `judge`, `feature-audit`, …) resolve their tier from the same map
under the active autonomy profile (`autonomous-minimal` | `semi-autonomous`).

Every dispatch brief states **model + effort explicitly** — resolve the tier,
then instantiate it via `tier_to_dispatch` (or `resolve_dispatch` role-side):
`low → sonnet@low`, `medium → opus@low`, `high → opus@high`. Never leave model or
effort to the agent's `.md` frontmatter defaults. Pure-mechanical routes (`by_tag
mechanical → __ollama__`) stay on haiku/ollama and never reach this map; blast
radius forces `high` (→ opus@high).

## Dispatch surface (Anthropic in-session)

Pick the surface by which knobs it exposes (Dispatch Routing Matrix,
`references/rules/performance.md`):

- **Agent tool** — the default for a single subagent or a small wave. Sets
  `model` per agent; **effort inherits the session**, so it is correct only when
  the resolved effort equals the session effort (`/effort`) — otherwise switch
  surface, don't dispatch at the wrong effort.
- **Workflow tool** — the only surface with a **per-agent effort knob**
  (`opts.model` + `opts.effort`). Prefer it when a wave mixes efforts (e.g.
  grouped `opus@low` implementers + an `opus@high` verify stage) or for a
  pipeline-shaped fan-out over many tasks/groups.
- **Headless CLI / leaf** — cross-provider routes only (`ollama`, DeepSeek):
  `--model` + settings per the leaf contract.

## Route + map proposals

- **Route:** `api` (default) or `ollama`. Ollama requires a passing health
  check; failure raises `EscalationRequired` — no silent API fallback.
- If `proposed_map_entry` is present in the result, append it to `findings.md`
  for human review (do not auto-merge into `specialist-map.yaml`).
