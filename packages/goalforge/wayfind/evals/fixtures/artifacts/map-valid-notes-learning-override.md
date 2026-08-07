---
type: wayfind-map
status: working
destination: "An effort whose ## Notes override table reroutes the learning row"
created: 2026-08-04
context_pointers:
  - src/payments/**
references: []
---

## Destination

The `## Notes` override table may target ANY ticket_type carried by the SKILL.md
dispatch table — `learning` included. This map exercises that widening: the
learning row is rerouted to an `interview` plugin run in the main session, so the
`ticket_type` enum in `validate-map.sh` must accept `learning` alongside the
four original types.

## Learning goals

- rate-limiter-semantics: understand token-bucket vs sliding-window trade-offs (why: blocks the provider choice in ticket-04)

## Notes

| ticket_type | machinery | model | effort |
|---|---|---|---|
| research | topic-research | sonnet | low |
| learning | interview | main | n/a |
