# goalforge-execute — Goal-eval directive contract (Step 9b)

Mechanical post-condition contract behind Step 9b's `act_on_directive`.
Consulted when reasoning about the exact `paused`/`met` shape the outer loop
reads; the operative severity + human-gate rules stay inline in SKILL.md.

## `act_on_directive(verdict) -> verdict'`

The outer loop branches on `verdict.paused` then `verdict.met`, so this step
returns a shape both branches can read on **every** path:

| strategy | action | post-condition |
|---|---|---|
| `deterministic` / `numeric` | none (script already decided) | pass through; `met` already concrete, set `paused = False` |
| `judge` | dispatch `judge`, map verdict via severity bar | `met` concrete `True`/`False`; `paused = False`; on not-met, `reason` = blocking findings |
| `human` | write gate to `findings.md` | `paused = True` (leave `met = None`) |

Guarantees: `paused` is **always present** (bool); for every non-human path
`met` is a concrete `True`/`False` (never `None`) before returning to the loop.

`deterministic | numeric` verdicts are already decided by the pure script
(binary) — nothing to dispatch. The `judge` and `human` handling is in SKILL.md
Step 9b.
