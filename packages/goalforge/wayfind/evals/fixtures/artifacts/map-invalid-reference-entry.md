---
type: wayfind-map
status: working
destination: "Effort whose typed references[] entry omits a required key"
created: 2026-07-16
context_pointers: []
references:
  - id: upstream-wayfinder
    type: url
    note: "typed entry with NO locator — the required-key set is id/type/locator"
    retrieved: 2026-07-16
---

## Destination

A `references[]` entry group beginning `- id:` is the CANONICAL typed form and
MUST carry `type` and `locator` (`note` / `retrieved` are optional). This fixture
is invalid on `references`: the typed entry drops `locator`.
