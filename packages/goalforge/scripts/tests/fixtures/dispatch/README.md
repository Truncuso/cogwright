# scripts/tests/fixtures/dispatch/ — wp-03 fixture set

Shipped by wp-03/T2. Every wp-03 oracle runs against these files through a
`--dispatch <path>` flag, never against `references/dispatch.yaml` or a live
`plans/` tree. No fixture here is ever mutated in place: a test that needs a
writable copy `cp -r`s it into its own `mktemp -d` root.

| File | Used by | Why |
|------|---------|-----|
| `dispatch-default.yaml` | b1, b3, b5, b6, b7 | mirror of the package file with providers replaced by `anthropic` (native) → `stub-a` (local) → `stub-b` (foreign); the fall-through, row-equality, and propose-only-ledger cases |
| `dispatch-ceiling-300k.yaml` | b7 | `harden.token_ceiling: 300000` — a CONFIGURED hard ceiling (park above it) |
| `dispatch-egress-none.yaml` | b6 | `second_opinion` row at `egress: none` — skip with reason `egress-none`, no leaf call |
| `dispatch-egress-full.yaml` | b6 | `second_opinion` row at `egress: full` — diff + overview.md + spec.md + findings.md |
| `wp-compile.md` | b3 | WP overview with 11 checklist items in three `{files:}` groups (A 4, B 4 disjoint from A, C 3 overlapping A), `parallel: true` |
| `spec-no-egress.md` | b6 | feature spec with no `egress:` — the stage row's class stands |
| `spec-egress-diff-only.md` | b6 | narrowing override, applied |
| `spec-egress-full.md` | b6 | widening override, ignored with a WARN row |
| `trace-b5.jsonl` | b5 | one `dispatch.launched` + one `dispatch.completed` at `tokens: 260000`, `tool_uses: 12` — above `rollup.token_warn: 250000` |
| `trace-b7-320k.jsonl` | b7 | one `harden.round` at `tokens: 320000`, round 1 |
| `trace-b7-rounds2.jsonl` | b7 | two `harden.round` rows at `tokens: 1000` — the round cap, not the token sensor |
| `wp-harden-high/overview.md` | b7 | WP at `severity: HIGH`, `register: production` (selects the 300k panel soft threshold) |

The three `dispatch-*.yaml` variants are generated from `dispatch-default.yaml`
by mutating one key; edit the default and regenerate rather than hand-patching
a variant.

The stub `leaf:` paths are corpus-relative placeholders. `goalforge-pick-agent.py`
never invokes a leaf — it replays terminations through `--simulate-leaf
"<exit>[:<reason>]"`. A test that needs a real executable leaf (b6) creates a
stub `headless_dispatch` under its own `mktemp -d` root.
