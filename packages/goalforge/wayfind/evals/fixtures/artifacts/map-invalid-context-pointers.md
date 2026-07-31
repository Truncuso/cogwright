---
type: wayfind-map
status: working
destination: "Effort whose context_pointers list carries an empty entry"
created: 2026-07-16
context_pointers:
  - src/payments/**
  - ""
references: []
---

## Destination

`context_pointers` is a list of NON-EMPTY strings — paths/globs the blind-spot
pass sweeps. This fixture is invalid on `context_pointers`: the second entry is
an empty string, which sweeps nothing and silently widens the pass.
