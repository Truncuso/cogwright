---
description: "Drive the whole goalforge SDD chain end-to-end via the goalforge-run orchestrator — route-aware over the canonical enum fast|standard|wave, resumes mid-chain from the current status:, and supports --dry-run. Use when the chain should run end-to-end rather than one stage at a time."
argument-hint: "[<feature-or-wp-slug>] [--dry-run]"
---

# /goalforge-run

> `${CLAUDE_PLUGIN_ROOT}` is the goalforge package root — the parent of the
> directory holding this command file. On a direct, non-plugin load the
> variable is unset; resolve it that way.

The PUBLIC pin for `goalforge-run`. The orchestrator is a PRIVATE nested child:
discovery is one level deep, so `Skill(skill: "goalforge-run")` answers "Unknown
skill" — do not retry that call. This command is its only entry.

## Steps

1. Read `${CLAUDE_PLUGIN_ROOT}/skills/run/SKILL.md` by path and follow the
   procedure in-session. Its sibling `chain.yaml` declares the step sequence;
   `goalforge-run` never reorders or extends it.
2. Parse `$ARGUMENTS`: an optional feature or WP slug, and an optional
   `--dry-run` literal. Empty slug → ask the user which feature to drive.
3. **`--dry-run`** — resolve and print the dispatch plan with no side effects
   (no files written, no subagents dispatched). The deterministic gate is:
   ```bash
   bash ${CLAUDE_PLUGIN_ROOT}/skills/run/scripts/goalforge-router.sh --dry-run <feature>
   ```
   It prints one `RESOLVED`/`UNRESOLVED` line per chain step and exits non-zero
   if any step is unresolved. `UNRESOLVED` contains the substring `RESOLVED`, so
   guard any count with `! grep -q UNRESOLVED` — the exit code is authoritative.
4. Otherwise run the chain from the step matching the target's current
   `status:`, honouring each step's `precondition:` and `human_gated:` flag.

## Rules

- `/spec`, `/plan`, `/implement`, `/verify` remain the stage-at-a-time entry
  points; prefer them when only one stage is wanted.
- Human gates are never auto-advanced by this command: the gated transitions
  stop and wait for explicit user approval.
- `<PLANS_ROOT>` resolves per `${CLAUDE_PLUGIN_ROOT}/references/schema.md`
  §PLANS_ROOT resolution.
