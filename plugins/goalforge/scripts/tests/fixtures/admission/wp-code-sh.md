---
name: wp-fx-code-sh
schema_version: 6
status: ready
register: production
severity: MEDIUM
task_type: code
owned_files:
  - scripts/alpha.sh
  - scripts/beta.sh
  - scripts/gamma.sh
goal:
  outcome: "fixture: a WP whose deterministic task class is code/sh"
  verification:
    strategy: deterministic
    command: "bash fixtures/admission/verify.sh"
---

Fixture WP. Task class `code/sh`.
