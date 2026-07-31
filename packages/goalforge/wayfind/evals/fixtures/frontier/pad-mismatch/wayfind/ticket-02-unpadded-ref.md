---
type: wayfind-ticket
ticket_type: task
status: open
depends_on: [ticket-1]
claimed_by: null
claimed_at: null
resolution: null
---

## Question

depends_on says `ticket-1`, but the dependency's file is `ticket-01-base.md`,
whose derived ID is `ticket-01`. The zero-padding rule was violated in the
reference, so the two never match and this ticket is blocked forever. Must
fail-close exit 2 naming this file and the token, not silently deadlock.
