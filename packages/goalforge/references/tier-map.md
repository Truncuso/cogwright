<!-- GENERATED FILE — do not hand-edit.
     Human-readable projection of the authoritative ROLE_TIER dict in
     scripts/goalforge-pick-agent.py. Regenerate from the dict; the
     `goalforge-pick-agent.py --test-tiers` eval drift-checks this projection
     against ROLE_TIER (no runtime markdown parsing anywhere). -->

# Dispatch Tier Map (role → tier × effort)

Projection of `ROLE_TIER` (scripts/goalforge-pick-agent.py) — the single
authoritative source for the BAND. Tiers are bare (`haiku`/`sonnet`/`opus`/
`fable`); effort is bare (`low`/`medium`/`high`/`xhigh`/`max`). No pinned
vendor model IDs. The per-stage `model`/`effort`/`provider`/`endpoint`/
`egress` actually dispatched are configured in `references/dispatch.yaml`,
whose stage keys equal the roles below.

- **tier** — the `low`/`medium`/`high` band from `ROLE_TIER[role][profile]`.
- **model** — the concrete model class via `COMPLEXITY_MODEL`
  (`low → sonnet`, `medium → opus`, `high → opus`).
- **effort** — the derived dispatch effort via `tier_to_dispatch`
  (`low → low`, `medium → low`, `high → high`).

Blast radius (auth / schema / migration / exported API / 3+ files) is detected
deterministically and forces the `high` tier (→ `opus` @ `high`) for every role
EXCEPT `implement`, which caps at `medium` (→ `opus` @ `low` — see
Register-conditioned rows below) — a sensitive change is never silently
downgraded.

`judge` and `wp-verify` are graders: ticket-48 re-bands both to `high`
(opus@high) on BOTH profiles, so every grader resolution differs from every
`implement` resolution in persona AND in model or effort.

## Roles

| role | autonomous-minimal (tier / model / effort) | semi-autonomous (tier / model / effort) |
|------|---------------------------------------------|------------------------------------------|
| implement | by_register | by_register |
| discovery | low / sonnet / low | low / sonnet / low |
| feature-audit | medium / opus / low | medium / opus / low |
| harden-review | low / sonnet / low | medium / opus / low |
| wp-verify | high / opus / high | high / opus / high |
| simplify | medium / opus / low | medium / opus / low |
| judge | high / opus / high | high / opus / high |
| panel | high / opus / high | high / opus / high |
| integration-review | medium / opus / low | high / opus / high |
| second_opinion | low / sonnet / low | low / sonnet / low |

## Register-conditioned rows

The `implement` role carries the `by_register` sentinel in both autonomy
profiles: it does not fix a tier, it defers to the WP's own C2 `register`/
`severity` fields — `register: spike` → `low`; `register: production` →
`sonnet-medium`, escalating to `medium` (opus@low, never opus@high) when
`severity: HIGH` or blast radius fires. This preserves per-WP tiering for the
code-writing role while every other role reads its fixed band from
`ROLE_TIER`.

## Autonomy profiles

- **autonomous-minimal** — cost-lean: the cheapest tier that still does the job,
  escalating only on blast radius.
- **semi-autonomous** — a human reviews the output, so spend for quality at the
  gates feeding that review (the `panel`, the last-WP `integration-review`).
  The resolver and CLI default.
