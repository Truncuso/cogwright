---
name: fixture-spec-egress-diff-only
title: "Feature spec fixture — `egress: diff-only` narrows the stage row (b6)"
status: spec
schema_version: 6
egress: diff-only
plan: fixture
---

# Fixture feature spec — narrowing override

`diff-only` is NARROWER than the stage row's `overview`
(none < diff-only < overview < full), so it is applied: the payload is the
diff alone.
