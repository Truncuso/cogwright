---
type: wayfind-map
status: working
destination: "A decision map whose operator opted into learning goals"
created: 2026-08-04
context_pointers:
  - src/payments/**
references: []
---

## Destination

Chart the retry/idempotency decisions for the payments effort. The operator
declared two learning goals at chart time — the OPT-IN entry path, never
auto-created.

## Learning goals

- rate-limiter-semantics: understand token-bucket vs sliding-window trade-offs (why: blocks the provider choice in ticket-04)
- pg-isolation-levels: read the actual guarantees of REPEATABLE READ (why: the idempotency decision rests on an unchecked assumption)

## Decisions so far

- [ticket-01](./ticket-01-settlement-model.md) — settlement model (resolved)

## Not yet specified

- Idempotency key ownership across retries.

## Out of scope

- Multi-currency ledger.
