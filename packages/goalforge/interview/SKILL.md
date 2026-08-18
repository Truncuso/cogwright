---
name: goalforge-interview
description: "Fidelity-aware goal-hardening specialization: frames a WP's open questions for a grilling session, delegates the Q&A loop to the interview plugin engine (preset: harden-facets), and implements the discussion-fidelity escape hatch. Invoked only by goalforge-harden Step 1; not a user-facing front door."
metadata:
  skill-kind: preference
  version: 1.0.0
hooks:
  Stop:
    - hooks:
        - type: command
          command: "$HOME/.claude/hooks/skill-trace.sh goalforge-interview:stop"
---

# goalforge-interview

## Visibility

PRIVATE child of the `goalforge` package: skill discovery is one level deep,
so nesting under the parent front door is what keeps this skill out of the
top-level surface. Sole call site is detailed in §Consumed by.

## What this adds over the bare `interview` plugin engine

Sense of the word, pinned here because it collides:
specialization = caller-side framing of the shared engine — this skill wraps
the one shared `interview` plugin instance in goal-hardening context, never a
nested sibling skill forked off that engine, which is the retired sense typed
presets superseded.

The `interview` plugin engine is a domain-agnostic Q&A loop; it knows
nothing about WPs, goal facets, or fidelity. This specialization supplies the
goal-hardening framing the engine needs:

- **Goal-facet completeness target** — the session isn't done until every open
  question in the WP's scope is resolved, recorded as an explicit assumption,
  or risk-accepted (harden Step 1's own exit criteria).
- **Fidelity vocabulary** — a question can outgrow discussion fidelity mid-loop;
  see `~/.claude/skills/goalforge/references/fidelity.md` for the ladder and the trigger criterion this
  specialization applies.

## Procedure (frame -> delegate -> escape hatch -> return)

1. **Frame** the session from the target WP's goal block (`overview.md`) and
   its recorded open questions — this is the context handed to the engine, not
   a restatement of its mechanics.
2. **Delegate** the Q&A loop to the `interview` plugin skill with the literal `preset: harden-facets`. All
   question technique, confidence signaling, and stopping behavior belong to
   the engine; this specialization does not reimplement or shadow it.
3. **Escape hatch** — when a question meets the spike-candidate trigger
   (`~/.claude/skills/goalforge/references/fidelity.md` §Trigger), ask once: *"this is above discussion fidelity — spike it?"*
   Surface this by consuming the engine's existing `HANDOFF_SUGGESTION: high-fidelity`
   token (no parallel signal invented) and route per `~/.claude/skills/goalforge/references/fidelity.md`
   §Per-stage routing — `harden` row — to the `prototype` skill. On routing to
   `prototype`, the spike question is written up as a standalone one-pager at
   `plans/<feature>/spikes/<slug>.md` following the template
   `~/.claude/skills/goalforge/prototype/references/spike-spec.md`; the grill
   checks the one-pager section-by-section. The engine's
   `high-fidelity` token is the signal, the Trigger is the filter — a token whose
   question fails the kind test (Trigger condition 1) goes back to harden Step 1's
   open-question/risk-accept path, not to `prototype`; a Trigger-matching question
   routes even if the engine emits no token.
4. **Return** the engine's structured outputs (resolved terms, ADR candidates,
   handoff suggestions) untouched to the caller; this specialization does not
   post-process or filter them.

## Consumed by

`goalforge-harden` Step 1 — the sole call site. Spec-stage goalfinding is not a
consumer of this specialization (it keeps its own wp-04 spike hook).

## Gotchas

- The engine (the `interview` plugin) stays external and unmodified — do not fork its
  question loop or stopping logic into this file.
- Package-private: no top-level installer symlink for this child skill.
