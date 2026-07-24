---
type: wayfind-ticket
ticket_type: task
status: open
depends_on: [*]
claimed_by: null
claimed_at: null
resolution: null
---

## Question

depends_on holds a bare glob (*). Splitting it must NOT undergo pathname
expansion (which would fabricate dep tokens from the cwd listing). The token
fails the ^ticket-[0-9]+$ shape check -> malformed frontmatter, exit 2.
