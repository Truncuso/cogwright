---
type: wayfind-ticket
ticket_type: grilling
status: open
depends_on: []
claimed_by: sess-7f3a
claimed_at: null
resolution: null
---

## Question

Half a claim: `claimed_by` set with `claimed_at` null — a claim with no age,
which can never go stale. run.sh mirrors this fixture (claimed_at set,
claimed_by null) inline to cover the other direction.
