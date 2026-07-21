<!-- GENERATED FILE — do not hand-edit.
     Human-readable projection of the authoritative ROLE_TIER dict in
     scripts/goalforge-pick-agent.py. Regenerate from the dict; the
     `goalforge-pick-agent.py --test-tiers` eval drift-checks this projection
     against ROLE_TIER (no runtime markdown parsing anywhere). -->

# Dispatch Tier Map (role → tier × effort)

Projection of `ROLE_TIER` (scripts/goalforge-pick-agent.py) — the single
authoritative source. Tiers are bare (`haiku`/`sonnet`/`opus`/`fable`); effort is
bare (`low`/`medium`/`high`/`xhigh`/`max`). No pinned vendor model IDs.

- **tier** — the `low`/`medium`/`high` band from `ROLE_TIER[role][profile]`.
- **model** — the concrete model class via `COMPLEXITY_MODEL`
  (`low → sonnet`, `medium → opus`, `high → opus`).
- **effort** — the derived dispatch effort via `tier_to_dispatch`
  (`low → low`, `medium → low`, `high → high`).

Blast radius (auth / schema / migration / exported API / 3+ files) is detected
deterministically and forces the `high` tier (→ `opus` @ `high`) regardless of
role or profile — a sensitive change is never silently downgraded.

## Roles

| role | autonomous-minimal (tier / model / effort) | semi-autonomous (tier / model / effort) |
|------|---------------------------------------------|------------------------------------------|
| implement | by_complexity | by_complexity |
| discovery | low / sonnet / low | low / sonnet / low |
| feature-audit | medium / opus / low | medium / opus / low |
| wp-harden-delta | low / sonnet / low | medium / opus / low |
| wp-verify | medium / opus / low | high / opus / high |
| simplify | medium / opus / low | medium / opus / low |
| judge | medium / opus / low | medium / opus / low |
| panel | high / opus / high | high / opus / high |
| arbiter-grid | low / sonnet / low | medium / opus / low |
| integration-review | medium / opus / low | high / opus / high |

## Complexity-conditioned rows

The `implement` role carries the `by_complexity` sentinel in both autonomy
profiles: it does not fix a tier, it defers to the task's own `complexity`
(`low`/`medium`/`high`), which then resolves to a tier × effort through the same
`tier_to_dispatch` mapping. This preserves per-task tiering for the code-writing
role while every other role reads its fixed band from `ROLE_TIER`.

## Autonomy profiles

- **autonomous-minimal** — cost-lean: the cheapest tier that still does the job,
  escalating only on blast radius. Default for fully-autonomous runs.
- **semi-autonomous** — a human reviews the output, so spend for quality at the
  gates feeding that review (the WP `wp-verify` pass, the `panel`, the
  last-WP `integration-review`).
