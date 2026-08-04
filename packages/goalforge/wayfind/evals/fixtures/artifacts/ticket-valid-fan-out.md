---
type: wayfind-ticket
ticket_type: research
status: open
depends_on: []
claimed_by: null
claimed_at: null
resolution: null
fan_out: 3
---

## Question

What does the vendor's rate limiter actually do under burst — per-key or
per-account, what window, and what does it return when it trips? This is a
`research` ticket, so the optional `fan_out: 3` field is legal here (and only
here): the question splits into three independent, non-overlapping probes.
