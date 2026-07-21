---
name: task-01-router-setup
title: Set up Express router
status: verified
complexity: low
route: api
parallel: false
depends_on: []
verify: "GET /health returns 200; POST /notify returns 202"
checkpoint:
  last_step: 1
  specialist: "general-purpose"
---
<!-- Template: task v4 (frontmatter-first, flat layout) -->

## Goal

Create Express router with /notify and /subscribe endpoints.
