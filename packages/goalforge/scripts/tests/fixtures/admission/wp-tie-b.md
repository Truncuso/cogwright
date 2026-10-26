---
name: wp-fx-tie-b
schema_version: 6
status: ready
register: production
severity: MEDIUM
task_type: code
owned_files:
  - scripts/alpha.sh
  - scripts/beta.sh
  - scripts/gamma.sh
  - src/alpha.py
  - src/beta.py
  - src/gamma.py
goal:
  outcome: "fixture: the SAME entries as wp-tie-a, order reversed"
  verification:
    strategy: deterministic
    command: "bash fixtures/admission/verify.sh"
---

Fixture WP. wp-tie-a's entries in the opposite order: a derivation that takes
the first max-count extension in insertion order resolves this one to
`code/sh` and goes red.
