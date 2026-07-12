---
name: notification-service
title: Notification Service
status: spec
created: 2026-01-01
feature: notification-service
work_packages: []
relationships: []
sources: []
---
<!-- Template: feature-spec v4 (frontmatter-first, flat layout) -->

## Design

Use an event-bus approach: producers publish events, the notification service subscribes and routes to email/SMS adapters.

## Interface Contract

- `POST /notify` — accepts `{channel, recipient, message}`
- `POST /subscribe` — registers a consumer for event type

## Non-Goals

- Push notifications
- In-app messages
- Message scheduling

## Work Packages

| WP | Title | Deps | Parallel |
|---|---|---|---|
| wp-01-api-scaffold | Scaffold API and routing layer | — | false |
| wp-02-delivery-adapters | Email and SMS delivery adapters | wp-01-api-scaffold | false |
