---
name: wp-fx-admitted
title: "fixture: a code/py WP compiled against an ADMITTED non-native implement row (wp-08)"
schema_version: 6
status: ready
register: production
severity: MEDIUM
task_type: code
parallel: false
owned_files:
  - src/alpha.py
  - src/beta.py
goal:
  outcome: "fixture: a WP whose deterministic task class is code/py"
  verification:
    strategy: deterministic
    command: "bash fixtures/admission/verify.sh"
---

Fixture WP for the wp-08 admitted-execution cases in
`goalforge-workflow-compile.test.sh`. Task class `code/py`.

## Checklist

- [ ] T1 alpha {files: src/alpha.py} [b1]
- [ ] T2 beta {files: src/beta.py} [b1]
