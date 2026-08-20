---
type: wayfind-ticket
ticket_type: task
status: open
depends_on: [ticket-01]
claimed_by: session-abc123
claimed_at: 2026-07-14
resolution: null
---

## Question

Open + unsatisfied dep + claimed: appears in BOTH `blocked` (waiting_on edge
preserved for diagnostics) and `claimed` — the arrays overlap by design.
