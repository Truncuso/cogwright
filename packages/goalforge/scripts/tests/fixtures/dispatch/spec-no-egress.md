---
name: fixture-spec-no-egress
title: "Feature spec fixture — no `egress:` override (b6)"
status: spec
schema_version: 6
plan: fixture
---

# Fixture feature spec — no egress override

The frontmatter carries no `egress:` key, so the second-opinion leg keeps the
stage row's class from `dispatch.yaml` verbatim (`overview` in the shipped
default).
