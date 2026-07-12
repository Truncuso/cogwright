# goalforge-decompose — edge-case gotchas (load-on-demand)

Consulted when debugging a decompose/harden interaction — not every run. The
frequently-hit gotchas stay inline in `SKILL.md`; these are the rarer edge cases.

- **Empty `goal.outcome` fails late, not now.** `goal.outcome` is always
  WP-authored and can never be blank; leaving it empty is a schema violation
  caught by `goalforge-validate.sh` at *hardening*, not at decompose — the error surface
  is delayed and can surprise operators expecting immediate feedback.
- **Cascade scalars can silently resolve to nothing.** `iteration_policy` and
  `blocked_stop` inherit from the feature spec only when the WP leaves them unset
  AND the spec has them set. If the spec also omits them, the resolved WP goal has
  no value for these fields — this does NOT error at decompose time, but
  `goalforge-harden` will grill them as incomplete facets. Set them at the spec level to
  avoid the later round-trip.
