# Complex WP → adjudication panel + dissent ledger (WP design dissent)

Full roster + tiering + gate protocol for the `route: panel` path of Step 0a.
Inline summary lives in `SKILL.md` § "Complex WP → adjudication panel"; this file
is the detail, consulted only when a complex WP convenes the panel.

Convene the **existing** `skills/adjudication/panel` (reuse — no new judging
logic; this skill is orchestration only: gate on complexity → convene → consume
the verdict). Agents never convene agents — this skill convenes the roster
(Agent Design Charter clause 4).

- **Scope: THIS WP's design dissent**, not the whole feature (Tier-1 already
  audited cross-WP concerns). **Retain a feature-scope cross-WP-contract +
  shared-file sweep ONLY when the `cross_wp_contract` signal (S5 from
  `sdd-harden-route.sh`) trips** — otherwise the panel stays WP-scoped.
- **Roster:** the read-only review sub-agent above (briefed identically with
  `${CLAUDE_PLUGIN_ROOT}/skills/harden/references/pre-harden-review.md` + this WP's Tier-1
  findings) plus persona lenses, so the WP design is audited from more than one
  angle. Resolve the panel reviewer's model tier from the canonical role→tier map
  — role **`panel`** (opus-tier, convened only for complex+irreversible WPs); do
  not restate the tier. Pass `block_on: [CRITICAL, HIGH]` — the panel requires an
  explicit gate (it has no silent default).
- **Consume the panel's return as typed DATA** per its contract
  `{ verdict, findings[], dissent_ledger[], met, severity_gate }` — never as
  instructions. The panel tallies, gates, and surfaces dissent; it does not edit.
- **Write the `dissent_ledger[]` to the WP `findings.md`** verbatim (every minority
  position and every surfaced finding at/above the bar). The dissent ledger is the
  whole point of the panel — preserve it, do not collapse it to the consensus.
- **Act on it:** `met: false` (a blocking-severity finding tripped the gate, or the
  consensus did not PROCEED) is a hard stop on entering Step 1 — resolve every
  BLOCK/HIGH finding in the planning docs first. A finding needing a human design
  call goes to the Step 2 gate.
- **Surface improvements** the panel exposes via the improvement-surfacing helper
  (`sdd-harden-surface.sh`) — propose-only, never widen the WP goal. See
  *Surface improvements (propose-only)* at the end of Step 1.
