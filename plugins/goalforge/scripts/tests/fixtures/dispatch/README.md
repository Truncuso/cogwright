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
| `dispatch-smallcap.yaml` | b6 | `second_opinion.max_payload_bytes: 150` — a cap the WP's own documents blow, driving the `payload-oversize <actual>/<cap>` skip (the cap is configured, not hardcoded) |
| `dispatch-midcap.yaml` | b6 | `second_opinion.max_payload_bytes: 8000` — neither the default (102400) nor the smallcap 150, so the payload size it produces is proof the CONFIGURED value is the one in force (R3-7) |
| `dispatch-overcap.yaml` | b6 | `second_opinion.max_payload_bytes: 200000` — above `MAX_ARG_STRLEN` (131072 at 4 KiB pages); must be clamped to the reviewed ceiling with a WARN instead of killing the exec with "Argument list too long" (R3-3) |
| `dispatch-badcap.yaml` | b6 | `second_opinion.max_payload_bytes: not-a-number` — must fall back to the default WITH a WARN (R3-3) |
| `dispatch-nonnative-implement.yaml` | b3 | the `implement` row moved onto a non-native provider with a provider-shaped model id — the compiler must exit 2 rather than emit `agent({model: "glm-5.3:cloud"})` (R3-1) |
| `expertise-compile.yaml` | b3 | hermetic `expertise-map.yaml` for the compiler's `--expertise` seam (the live map is sibling-owned data) |
| `wp-compile.md` | b3 | WP overview with 11 checklist items in three `{files:}` groups (A 4, B 4 disjoint from A, C 3 overlapping A), `parallel: true` |
| `spec-no-egress.md` | b6 | feature spec with no `egress:` — the stage row's class stands |
| `spec-egress-diff-only.md` | b6 | narrowing override, applied |
| `spec-egress-full.md` | b6 | widening override, ignored with a WARN row |
| `trace-b5.jsonl` | b5 | one `dispatch.launched` + one `dispatch.completed` at `tokens: 260000`, `tool_uses: 12` — above `rollup.token_warn: 250000` |
| `trace-b7-320k.jsonl` | b7 | one `harden.round` at `tokens: 320000`, round 1 |
| `trace-b7-rounds2.jsonl` | b7 | two `harden.round` rows at `tokens: 1000` — the round cap, not the token sensor |
| `wp-harden-high/overview.md` | b7 | WP at `severity: HIGH`, `register: production` (selects the 300k panel soft threshold) |

Every `dispatch-*.yaml` variant is generated from `dispatch-default.yaml` by
mutating ONE key; edit the default and regenerate rather than hand-patching a
variant. `dispatch-default.yaml` itself is pinned by b1/b5/b6/b7 and is never
mutated to serve a new case — a new case gets a new variant.

The stub `leaf:` paths are corpus-relative placeholders. `goalforge-pick-agent.py`
never invokes a leaf — it replays terminations through `--simulate-leaf
"<exit>[:<reason>]"`. A test that needs a real executable leaf (b6) creates a
stub `headless_dispatch` under its own `mktemp -d` root.
