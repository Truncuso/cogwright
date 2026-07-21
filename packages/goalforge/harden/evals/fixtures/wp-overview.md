---
name: wp-01-api-scaffold
title: Scaffold API and routing layer
status: spec
stage_updated: 2026-01-01
severity: MEDIUM
parallel: false
depends_on: []
plan: notification-service
tags: []
relationships: []
sources: []
---
<!-- Template: wp-overview v4 (frontmatter-first, flat layout) -->

## Goal

Stand up the HTTP API layer with routing for /notify and /subscribe endpoints.

## Scope

**In**: Express router setup, request validation, error middleware.
**Out**: Authentication, rate limiting.

## Open Questions

- Should we use Fastify or Express?
- What format should error responses take?
