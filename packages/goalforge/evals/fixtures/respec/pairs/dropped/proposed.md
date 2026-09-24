---
name: feat-spec
title: Respec fixture feature — spec
status: spec
created: 2026-08-01
updated: 2026-08-01
feature: feat
task_type: code
goal:
  outcome: "Events are delivered within 5 seconds."
  verification:
    strategy: deterministic
    command: "bash run-checks.sh"
---

# Respec fixture feature — spec

## Goal

Events are delivered within 5 seconds.

## Interface Contract

### C1 — event record

Each event is a JSON object with `id`, `kind` and `ts`.

### C2 — delivery queue

The queue file lives at `queue/<id>.json` and holds one event.

## Goal Changelog

- v1 2026-08-01 facet=outcome none→events delivered within 5 seconds; reason: spec authored
