---
name: wp-fx-tie-a
schema_version: 6
status: ready
register: production
severity: MEDIUM
task_type: code
owned_files:
  - src/alpha.py
  - src/beta.py
  - src/gamma.py
  - scripts/alpha.sh
  - scripts/beta.sh
  - scripts/gamma.sh
goal:
  outcome: "fixture: a 3/3 extension tie, .py entries FIRST"
  verification:
    strategy: deterministic
    command: "bash fixtures/admission/verify.sh"
---

Fixture WP. A 3-3 tie; the tie breaks on the lexicographically smallest
extension, never on entry order — `code/py`.
