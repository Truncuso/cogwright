---
type: wayfind-ticket
ticket_type: research
status: open
depends_on: [ticket-99]
claimed_by: null
claimed_at: null
resolution: null
---

## Question

depends_on names ticket-99, which does not exist in this map. The token is
shape-valid, so it survives frontmatter parsing — but it can never be satisfied,
so before the fix this map deadlocked at exit 0 forever. Must fail-close exit 2.
