---
type: wayfind-map
status: working
destination: "Effort whose ## Notes override table is not the pinned shape"
created: 2026-07-16
context_pointers: []
references: []
---

## Destination

The per-effort `## Notes` override is a FIXED-SHAPE table
(`| ticket_type | machinery | model | effort |`) — a FULL-ROW override including
machinery. This fixture is invalid on `## Notes`: the table drops the `machinery`
column, so the override could never reroute the machinery and would fail
silently back to the SKILL.md default.

## Notes

| ticket_type | model | effort |
|---|---|---|
| research | opus | medium |
