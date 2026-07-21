---
route: wave
owned:
  - plans/feature-a/sub/**

off-limits:
  - plans/feature-b/**
---

<!-- Sibling of brief-feature-a: owns a sub-tree contained within the other
     brief's owned glob. The pair is a real nested-glob collision. -->
