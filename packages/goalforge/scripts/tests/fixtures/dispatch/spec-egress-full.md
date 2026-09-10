---
name: fixture-spec-egress-full
title: "Feature spec fixture — `egress: full` is a widening attempt (b6)"
status: spec
schema_version: 6
egress: full
plan: fixture
---

# Fixture feature spec — widening override, ignored

`full` is WIDER than the stage row's `overview`, and a feature may only
narrow. The value is ignored, a WARN row names it, and the payload stays the
stage row's `overview` class.
