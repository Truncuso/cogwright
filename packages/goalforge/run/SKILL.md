---
name: run
description: "Chain driver for the goalforge stages: capture → spec → decompose → harden → execute → verify. Reads the target's on-disk `status:` and enters the one step that status admits; supports --dry-run. Use it to drive a feature end-to-end; for a single stage, use the entry command for that stage."
metadata:
  skill-kind: preference
  version: 2.0.0
hooks:
  Stop:
    - hooks:
        - type: command
          command: "$HOME/.claude/hooks/skill-trace.sh goalforge-run:stop"
---

# goalforge-run

Sibling `chain.yaml` declares the step sequence; never reorder or extend it here
(that is `/skill-improve`). `<PLANS_ROOT>` resolves per
`${CLAUDE_PLUGIN_ROOT}/references/schema.md`.

## Steps

1. Resolve the target: a feature slug (chain entry) or a WP slug (mid-chain).
2. Read its on-disk `status:` and enter the single step that status admits:

   | `status:` | target | next step | child skill | gate |
   |---|---|---|---|---|
   | *(none yet)* | feature | capture | `goalforge-capture` | — |
   | `draft` | feature | spec | `goalforge-spec` | human |
   | `spec` | feature | spec (ratify) | `goalforge-spec` | human at `spec → ready` |
   | `ready` | feature | decompose | `goalforge-decompose` | auto |
   | `spec` | WP | harden | `goalforge-harden` | human at `hardened → ready` |
   | `ready` / `executing` | WP | execute (resume) | `goalforge-execute` | auto |
   | `implemented` | WP | verify | `goalforge-verify` | auto |
   | `verified` / `abandoned` / `archived` | WP | — | — | complete |

3. Run that step by reading `${CLAUDE_PLUGIN_ROOT}/skills/<child>/SKILL.md` and
   following it in-session. At a human gate stop and ask; under
   `SDD_AUTONOMY=unattended`, park.
4. On return, re-read `status:` and repeat until `verified` or a step parks.
5. `--dry-run`: print each step, its resolved skill path, its precondition, and
   whether the target satisfies it. Zero side effects — no files written, no
   subagents dispatched, no status mutated.
   ```bash
   bash ${CLAUDE_PLUGIN_ROOT}/skills/run/scripts/goalforge-router.sh --dry-run <feature>
   ```

## Workflows

`run/workflows/` holds the compiled Workflow scripts — the output of
`scripts/goalforge-workflow-compile.py`, one `run/workflows/<wp>.js` per work
package. `goalforge-execute` compiles the WP checklist into that file and
launches it through the Workflow tool; nothing in this directory is
hand-edited.

## Gotchas

- Routing keys entirely off the on-disk `status:` — a hand-edited or drifted
  value matches no step and the driver halts rather than guessing. Fix the
  status, do not force re-entry.
- The status is re-read at every resume: a parallel session that advanced the WP
  moves the entry point under you. Re-check before resuming a suspended chain.
