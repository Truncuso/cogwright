---
type: wayfind-ticket
ticket_type: learning
status: open
depends_on: []
claimed_by: null
claimed_at: null
resolution: null
mode: HITL
---

## Question

INVALID on purpose: a `learning` ticket carrying `mode: HITL`. The new enum
value relaxes NOTHING — `mode` stays legal only on `ticket_type: task`, so this
must exit 1 naming `mode`. Learning is HITL by derivation from its type (like
`grilling`), never by an explicit override.
