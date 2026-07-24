---
name: <YYYY-MM-DD>-<slug>
title: "<one-line re-harden trigger>"
kind: prototype-findings          # prototype-findings | execution-learning | issue
locator: <path-or-url>            # where the evidence lives (findings doc, PR, issue, trace row)
summary: <one line>              # one-line statement of what the evidence shows
plan: <feature>
wp: <wp-id>
created: YYYY-MM-DD
---

<!-- Template: reharden-evidence v4 (frontmatter-first, flat layout) -->
<!-- Path convention: plans/<feature>/<wp>/reharden/<YYYY-MM-DD>-<slug>.md
     This is the typed evidence that gates the `ready → hardened` revert. The
     transition MUST be written with the evidence gate:
       goalforge-transition.sh <wp> hardened --mode evidence --evidence <this-file>
     A bare `--reason` revert on this edge is refused (state-machine.md §Policy —
     Evidence-gated revert exception). Emits trace events reharden.proposed /
     reharden.accepted (references/trace-events.md); `kind`/`locator`/`summary`
     mirror into those event payloads. -->

## Evidence

<what surfaced that invalidates or re-opens the WP's `ready` goals — cite the
`locator` source, do not copy it wholesale>

## Goal Impact

<which goal(s) / verification rows must be re-developed at `hardened`, and why
the current `ready` framing no longer holds>
