---
type: wayfind-map
status: working
destination: "A map whose ## Learning goals section carries a malformed row"
created: 2026-08-04
context_pointers:
  - src/payments/**
references: []
---

## Destination

INVALID on purpose: the second `## Learning goals` row uses a non-kebab-case
slug, so the section must exit 1 naming `## Learning goals`. The first row is
well-formed, so the fixture cannot pass by having no rows at all.

## Learning goals

- rate-limiter-semantics: understand token-bucket vs sliding-window trade-offs (why: blocks ticket-04)
- PG_Isolation_Levels: read the actual guarantees of REPEATABLE READ (why: idempotency)

## Out of scope

- Multi-currency ledger.
