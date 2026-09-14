---
name: wp-fx-no-ext
schema_version: 6
status: ready
register: production
severity: MEDIUM
task_type: code
owned_files:
  - src/
  - scripts/
  - scripts/goalforge-issue
goal:
  outcome: "fixture: directory entries and one extensionless file -> code/-"
  verification:
    strategy: deterministic
    command: "bash fixtures/admission/verify.sh"
---

Fixture WP. No file entry carries an extension: `code/-`.
