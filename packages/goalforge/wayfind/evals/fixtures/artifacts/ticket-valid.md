---
type: wayfind-ticket
ticket_type: task
status: open
depends_on: [ticket-01]
claimed_by: null
claimed_at: null
resolution: null
mode: HITL
---

## Question

Should the idempotency key be owned by the caller or minted at the gateway
boundary? This is a `task` ticket, so the optional `mode: HITL` override is
legal here (and only here).
