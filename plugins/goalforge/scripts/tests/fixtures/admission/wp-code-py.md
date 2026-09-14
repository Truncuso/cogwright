---
name: wp-fx-code-py
schema_version: 6
status: ready
register: production
severity: MEDIUM
task_type: code
owned_files:
  - src/alpha.py
  - src/beta.py
  - src/gamma.py
goal:
  outcome: "fixture: a WP whose deterministic task class is code/py"
  verification:
    strategy: deterministic
    command: "bash fixtures/admission/verify.sh"
---

Fixture WP. Task class `code/py`.
