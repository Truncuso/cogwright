---
name: wp-blocked-stop
title: Goal-loop fixture — not met, drives blocked_stop escalation
status: ready
stage_updated: 2026-06-07
task_type: code
goal:
  outcome: "the deterministic check passes (it never will — escalation path)"
  verification:
    strategy: deterministic
    check: "false"
  blocked_stop: "after outer_max_iter with the check still failing, escalate"
---

<!-- Template: wp-overview v4 (frontmatter-first, flat layout) -->

## Goal

blocked_stop path: `goalforge-goal-eval` returns met=False every outer iteration; after
`outer_max_iter` the agent appends a blocker to findings.md and escalates via
AskUserQuestion (never silent-pass).
