---
type: wayfind-ticket
ticket_type: task              # research | grilling | prototype | task
status: open                   # open | resolved | out-of-scope
depends_on: []                 # ticket IDs (ticket-NN), same semantics as WP depends_on
claimed_by: null               # session id — claim stamp; status stays open while claimed
claimed_at: null               # YYYY-MM-DD — set with claimed_by; basis for stale WARN
resolution: null               # ./findings/ticket-NN.md — pointer, set on resolve
mode: HITL                     # OPTIONAL, only on ticket_type: task (AFK default)
---

## Question

The documented spec-template ticket frontmatter carrying its inline `#` comments,
with real values (`ticket_type: task` so the `mode: HITL` override is legal). It
MUST validate (exit 0) — the quote-aware comment strip must yield `mode: HITL`,
`claimed_at: null`, etc., not the corrupted comment-suffixed values.
