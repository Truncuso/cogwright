---
type: wayfind-ticket
ticket_type: research
status: open
depends_on: []
claimed_by: null
claimed_at: null
resolution: null
fan_out: 1
---

## Question

What are the retention guarantees of the vendor's audit log? INVALID for exactly
ONE reason: `fan_out` must be an integer >= 2 and this declares `1` — a single
probe is not a fan-out. Every other field conforms, including the
`ticket_type: research` that makes the field legal at all, so raising the value
to `2` must flip this fixture to exit 0 (the mutate-one-field control).
