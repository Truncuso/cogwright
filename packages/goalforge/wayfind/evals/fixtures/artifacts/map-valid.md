---
type: wayfind-map
status: working
destination: "A multi-session pre-spec decision map for the payments-rearchitecture effort"
created: 2026-07-16
context_pointers:
  - src/payments/**
  - docs/adr/000*-payments*.md
references:
  - id: payments-idea
    type: file
    locator: plans/ideas/payments-rearchitecture.md
    note: originating idea stub
    retrieved: 2026-07-16
  - docs/adr/0004-payments-provider.md
---

## Destination

Chart the open decisions blocking a clean spec for re-architecting the payments
subsystem: settlement model, idempotency boundary, and provider abstraction.

## Decisions so far

- [ticket-01](./ticket-01-settlement-model.md) — settlement model (resolved)

## Not yet specified

- Idempotency key ownership across retries.
- Provider abstraction seam vs direct integration.

## Out of scope

- Multi-currency ledger (deferred to a later effort).

## Notes

| ticket_type | machinery | model | effort |
|---|---|---|---|
| research | topic-research | sonnet | low |
