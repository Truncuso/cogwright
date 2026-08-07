# SDD → goalforge alias map

A **historical name map**, kept so an old `sdd-*` reference found in a plan, a
handoff, or an archived document can still be resolved. The `sdd-*` names are
retired: nothing in this package answers to them any more. Nothing here is a
plan or a pending action — every rename below has already happened.

Locations are given relative to the plugin root (`${CLAUDE_PLUGIN_ROOT}`).
Conventions: **skills** are referenced by bare name (`goalforge-<name>` — the
plugin registers them); **script invocations** name the concrete path under the
plugin's `scripts/` directory. Directory names inside the plugin drop the
redundant prefix, since the plugin namespace already carries `goalforge`.

## Child skills

`sdd-run` became `goalforge-run` rather than a bare `run` to avoid colliding
with the unrelated `run` skill.

| Old skill | New bare name | Location |
|-----------|---------------|----------|
| `sdd-capture` | `goalforge-capture` | `skills/capture/` |
| `sdd-spec` | `goalforge-spec` | `skills/spec/` |
| `sdd-decompose` | `goalforge-decompose` | `skills/decompose/` |
| `sdd-harden` | `goalforge-harden` | `skills/harden/` |
| `sdd-execute` | `goalforge-execute` | `skills/execute/` |
| `sdd-verify` | `goalforge-verify` | `skills/verify/` |
| `sdd-redecompose` | `goalforge-redecompose` | `skills/redecompose/` |
| `sdd-archive` | `goalforge-archive` | `skills/archive/` |
| `sdd-recap` | `goalforge-recap` | `skills/recap/` |
| `sdd-onboard` | `goalforge-onboard` | `skills/onboard/` |
| `sdd-watchdog` | `goalforge-watchdog` | `skills/watchdog/` |
| `sdd-plan-index` | `goalforge-plan-index` | `skills/plan-index/` |
| `sdd-arbiter` | `goalforge-arbiter` | `skills/arbiter/` |
| `sdd-run` (runner) | `goalforge-run` | `skills/run/` |

### Children with no legacy name

These four were added after the rename and never had an `sdd-*` predecessor —
listed so a search for their history does not go looking for one.

| Old skill | New bare name | Location |
|-----------|---------------|----------|
| *(none)* | `goalforge-brief` | `skills/brief/` |
| *(none)* | `goalforge-interview` | `skills/interview/` |
| *(none)* | `goalforge-prototype` | `skills/prototype/` |
| *(none)* | `goalforge-wayfind` | `skills/wayfind/` |

## Scripts (.sh — plain renames)

Every `sdd-<x>.sh` became `goalforge-<x>.sh` under the plugin's `scripts/`
directory, with one exception to the mechanical rule: `sdd-goal-route.sh`
became **`goalforge-route.sh`**. No forwarding shim was kept under the old
name — the old names simply do not exist.

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

## Scripts (.py — plain renames)

Same rule, same directory. These are imported or loaded by path (for example
`goalforge-goal-eval.py` via `importlib.util.spec_from_file_location`), so a
shell forwarder could not have preserved the import contract even if one had
been wanted; callers name the plugin copy directly.

| Old script | New script |
|------------|------------|
| `sdd-goal-eval.py` | `goalforge-goal-eval.py` |
| `sdd-pick-agent.py` | `goalforge-pick-agent.py` |
| `sdd-plan-index.py` | `goalforge-plan-index.py` |
