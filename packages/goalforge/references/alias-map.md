# SDD → goalforge alias map

Old dotfiles `sdd-*` names → new **goalforge** plugin locations. Resolve
`$COGWRIGHT_ROOT` to your cogwright checkout (default `~/10_projects/cogwright`);
the plugin root is `$COGWRIGHT_ROOT/plugins/goalforge/`.

Conventions (interview 2026-07-09, OQ1 hybrid): **skills** are referenced by
bare name (`goalforge-<name>` — the plugin auto-registers them); **script
invocations** pin the concrete `$COGWRIGHT_ROOT/plugins/goalforge/scripts/...`
path. Directory names inside the plugin drop the redundant prefix (the plugin
namespace already carries `goalforge`).

## Child skills

| Old skill | New bare name | New path |
|-----------|---------------|----------|
| `sdd-capture` | `goalforge-capture` | `$COGWRIGHT_ROOT/plugins/goalforge/skills/capture/` |
| `sdd-spec` | `goalforge-spec` | `$COGWRIGHT_ROOT/plugins/goalforge/skills/spec/` |
| `sdd-decompose` | `goalforge-decompose` | `$COGWRIGHT_ROOT/plugins/goalforge/skills/decompose/` |
| `sdd-harden` | `goalforge-harden` | `$COGWRIGHT_ROOT/plugins/goalforge/skills/harden/` |
| `sdd-execute` | `goalforge-execute` | `$COGWRIGHT_ROOT/plugins/goalforge/skills/execute/` |
| `sdd-verify` | `goalforge-verify` | `$COGWRIGHT_ROOT/plugins/goalforge/skills/verify/` |
| `sdd-redecompose` | `goalforge-redecompose` | `$COGWRIGHT_ROOT/plugins/goalforge/skills/redecompose/` |
| `sdd-archive` | `goalforge-archive` | `$COGWRIGHT_ROOT/plugins/goalforge/skills/archive/` |
| `sdd-recap` | `goalforge-recap` | `$COGWRIGHT_ROOT/plugins/goalforge/skills/recap/` |
| `sdd-onboard` | `goalforge-onboard` | `$COGWRIGHT_ROOT/plugins/goalforge/skills/onboard/` |
| `sdd-watchdog` | `goalforge-watchdog` | `$COGWRIGHT_ROOT/plugins/goalforge/skills/watchdog/` |
| `sdd-plan-index` | `goalforge-plan-index` | `$COGWRIGHT_ROOT/plugins/goalforge/skills/plan-index/` |
| `sdd-arbiter` | `goalforge-arbiter` | `$COGWRIGHT_ROOT/plugins/goalforge/skills/arbiter/` |
| `sdd-run` (runner) | `goalforge-run` | `$COGWRIGHT_ROOT/plugins/goalforge/skills/run/` |

> Directory-vs-registered-name and the exact plugin skill registration are
> finalized by the member-move task (task-02); this table records the target
> convention. `sdd-run` is renamed `goalforge-run` (not bare `run`) to avoid
> colliding with the existing `run` skill.

## Scripts (.sh — exec-forward shims live at `../scripts/`)

Every `sdd-<x>.sh` → `goalforge-<x>.sh` under
`$COGWRIGHT_ROOT/plugins/goalforge/scripts/`, with one rename:
`sdd-goal-route.sh` → **`goalforge-route.sh`**.

| Old script | New script |
|------------|------------|
| `sdd-archive-batch.sh` | `goalforge-archive-batch.sh` |
| `sdd-archive.sh` | `goalforge-archive.sh` |
| `sdd-assumption-recheck.sh` | `goalforge-assumption-recheck.sh` |
| `sdd-attribution.sh` | `goalforge-attribution.sh` |
| `sdd-completed.sh` | `goalforge-completed.sh` |
| `sdd-ensure-committed.sh` | `goalforge-ensure-committed.sh` |
| `sdd-feature-hash.sh` | `goalforge-feature-hash.sh` |
| `sdd-frontier.sh` | `goalforge-frontier.sh` |
| `sdd-goal-changelog.sh` | `goalforge-goal-changelog.sh` |
| `sdd-goal-eval.sh` | `goalforge-goal-eval.sh` |
| `sdd-goal-hash.sh` | `goalforge-goal-hash.sh` |
| `sdd-goal-route.sh` | `goalforge-route.sh` *(rename)* |
| `sdd-harden-route.sh` | `goalforge-harden-route.sh` |
| `sdd-harden-surface.sh` | `goalforge-harden-surface.sh` |
| `sdd-hygiene.sh` | `goalforge-hygiene.sh` |
| `sdd-install-hooks.sh` | `goalforge-install-hooks.sh` |
| `sdd-learning-route.sh` | `goalforge-learning-route.sh` |
| `sdd-reconcile-diff.sh` | `goalforge-reconcile-diff.sh` |
| `sdd-rewire-impact.sh` | `goalforge-rewire-impact.sh` |
| `sdd-rollup.sh` | `goalforge-rollup.sh` |
| `sdd-stamp-tables.sh` | `goalforge-stamp-tables.sh` |
| `sdd-status.sh` | `goalforge-status.sh` |
| `sdd-transition.sh` | `goalforge-transition.sh` |
| `sdd-validate.sh` | `goalforge-validate.sh` |
| `sdd-wp-complexity.sh` | `goalforge-wp-complexity.sh` |

## Scripts (.py — copied, NOT shimmed)

Copied into the plugin as `goalforge-*.py`, but the dotfiles originals are left
in place **unshimmed**: they are imported/loaded by path (e.g.
`sdd-goal-eval.py` via `importlib.util.spec_from_file_location`), so a shell
exec-forward would not preserve the import contract. Callers must be repointed
at the plugin copy directly (task-04 rewire).

| Old script | New script |
|------------|------------|
| `sdd-goal-eval.py` | `goalforge-goal-eval.py` |
| `sdd-pick-agent.py` | `goalforge-pick-agent.py` |
| `sdd-plan-index.py` | `goalforge-plan-index.py` |
