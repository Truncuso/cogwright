---
name: wp-fx-dominant
schema_version: 6
status: ready
register: production
severity: MEDIUM
task_type: code
owned_files:
  - src/alpha.py
  - src/beta.py
  - references/config.yaml
goal:
  outcome: "fixture: a dominant extension, no tie -> code/py"
  verification:
    strategy: deterministic
    command: "bash fixtures/admission/verify.sh"
---

Fixture WP. `.py` dominates 2-1: `code/py`.
