---
type: wayfind-ticket
ticket_type: research
status: open
depends_on: []
claimed_by: null
claimed_at: null
resolution: null
mode: HITL
---

## Question

`mode` is only legal on `ticket_type: task`; here it sits on a `research`
ticket, so the validator rejects on the `mode` field.
