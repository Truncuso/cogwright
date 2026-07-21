---
route: wave
owned:
  - plans/feature-a/**

off-limits:
  - plans/feature-b/**
---

<!-- Nested-glob collision fixture: this brief owns the whole feature-a tree;
     the sibling brief owns a sub-tree beneath it. Their owned globs are
     DIFFERENT literal strings but cover overlapping path-trees, so a literal
     set-intersection would miss the collision. The ownership check must flag
     it via glob-containment. -->
