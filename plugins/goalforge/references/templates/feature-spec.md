---
name: <feature>-spec
title: <human title> — spec
status: draft
created: YYYY-MM-DD
feature: <feature>
task_type: code            # code | research | ops | writing | optimization | analysis
goal:                      # parent goal object; WPs may inherit unset fields via inherits_from
  outcome: "<what is true when done — one measurable sentence>"
  verification:
    strategy: deterministic   # deterministic | numeric | judge | human
    check: "<command | metric spec | judge spec | gate prompt>"
  constraints: []
  boundaries: []
  iteration_policy: "<how to choose the next action after each attempt>"
  blocked_stop: "<when to halt and report paths exhausted>"
---

<!-- Template: feature-spec v4 (frontmatter-first, flat layout) -->

## Design

<agreed design: approach, key decisions, constraints>

## Interface Contract

<public API, file contracts, data shapes>

## Non-Goals

<what this design explicitly excludes>

## Open Questions

<unresolved questions — move to findings.md when answered>
