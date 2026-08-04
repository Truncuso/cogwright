---
type: wayfind-ticket
ticket_type: grilling
status: open
depends_on: []
claimed_by: null
claimed_at: null
resolution: null
fan_out: 3
---

## Question

Should retries be owned by the caller or the gateway? INVALID for exactly ONE
reason: `fan_out` is legal only on `ticket_type: research`, and this is a
`grilling` ticket. Every other field conforms — flipping `ticket_type` to
`research` must flip this fixture to exit 0 (the mutate-one-field control).
