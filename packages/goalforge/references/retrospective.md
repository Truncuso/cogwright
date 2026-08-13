# Retrospective Stage — issue vocabulary, capture guidance, report contract (wp-15)

goalforge's propose-only retrospective layer. Two capabilities:

1. **Capture** (`goalforge-issue`) — a session, when its OWN judgment flags
   friction, records a schema-legal `issue.recorded` trace event via the wp-14
   emitter. Fire-and-forget: it never blocks the run (WARN + exit 0 on
   emitter-absent OR emitter-reject). Judgment-invoked — nothing auto-emits.
   **Run it directly (`scripts/goalforge-issue …`) or with `python3` — never
   `bash`.** It is a Python script; `bash goalforge-issue` dies on the first
   module-level tuple (`line 44: KINDS = (`) and reads as a broken tool. That
   misdiagnosis cost a real capture on 2026-08-11; `--self-test` is the
   one-command way to confirm the tool is healthy before concluding otherwise.
2. **Distill** (`goalforge-retrospect`) — a deterministic projection of a
   feature's trace window into `improvement-report.md` (Bottlenecks, Issues
   Chased, Routed Proposals — all propose-only). Owned by task-02.

This document is the single home for the **issue kind vocabulary**, the
**evidence-pointer convention**, and the **routing authority pointer**.

## Schema boundary (B-15-SCHEMA — do not extend)

The `issue.recorded` event schema is **frozen** by wp-14
(`references/trace-events.md`, single schema home) and is **NOT** extended here.
Schema-legal fields only:

| Field | Required | Semantics |
|---|---|---|
| `type` | yes | const `issue.recorded` |
| `kind` | yes | one of the vocabulary below |
| `summary` | no | one-line description (no logs, no excerpts) |
| `wp` | no | WP the issue attaches to, if any |
| `actor`, `session`, `decision_ref` | no | attribution (reused verbatim) |

There are deliberately **no `--evidence` / `--resolution` emitter flags** — they
would require new schema fields. Evidence, resolution, and chase status are
**REPORT-side**: they live in `improvement-report.md` as prose plus
repo-relative `decision_ref` pointers, never as event fields.

## Issue kind vocabulary

Capture the FIRST kind that fits; `summary` disambiguates. `dispatch-mismatch`
is vocabulary-only until a `dispatch.*` producer lands (wp-14 OQ1) — the
distiller builds no ranking branch for it yet.

| Kind | When to capture |
|---|---|
| `retry-wall` | A step failed and was retried past the point of diminishing returns (≥2 attempts on the same root cause) — the loop is not converging. |
| `tool-failure` | A tool/command/MCP call errored, hung, or returned unusable output and blocked progress (not a logic bug in your own change). |
| `missing-skill` | The task needed a capability no skill covers — a repeated manual procedure that should be a skill. |
| `skill-defect` | An invoked skill misbehaved, mis-triggered, or produced a wrong result (a defect in an existing skill, not its absence). |
| `dispatch-mismatch` | A subagent was dispatched at the wrong model/effort for the work (over- or under-powered), or to the wrong specialist. Vocabulary-only today. |
| `context-bloat` | The context window filled with low-signal material — over-broad reads, unpruned output, redundant reloads — degrading the session. |
| `spec-gap` | The spec/WP was ambiguous, under-specified, or contradictory and forced a guess or a clarification round-trip. |
| `env-friction` | Environment/tooling friction — sandbox denials, missing deps, path/permission issues, policy blocks — that slowed the work. |

## Evidence-pointer convention

Never copy logs, command output, or conversation/thinking excerpts into the
event OR the report. Reference them by **pointer**:

- Use a repo-relative `decision_ref` pointer (a path, optionally with an anchor)
  — e.g. `findings.md`, `plans/<feature>/wp-NN/task-MM.md`, a conv2md export
  path. Never an absolute `/home/<user>/…` path.
- Conversation / thinking-trace excerpts stay **pointer-only** (OQ2): the report
  references a conv2md export path, never a pasted excerpt (size/privacy).
- Evidence and resolution status are written by the **distiller's report**, not
  the capture event (schema boundary above).

## Routing authority

Routed Proposals in `improvement-report.md` map each issue kind to a
learning-routing target. The authority is **`rules/common/learning-routing.md`**
— cited **verbatim**, never a divergent baked copy (including the ≥2×
skill-defect threshold). Indicative mapping (the rule is authoritative):

| Kind | Routing target (per learning-routing.md) |
|---|---|
| `retry-wall`, `context-bloat`, `dispatch-mismatch` | workflow/tooling idea → `plans/ideas/` (tooling tag) |
| `missing-skill` | idea → `plans/ideas/`; if repeated, skill authoring |
| `skill-defect` | `/skill-improve` once it recurs ≥2× (per the rule) |
| `spec-gap` | durable fact → `.memory/` or a rule |
| `tool-failure`, `env-friction` | tooling idea → `plans/ideas/` (tooling tag) |

All proposals are **propose-only** and human-gated + eval-gated per the
Auto-Research / Auto-Improve Contract — the retrospective layer never edits
skills, rules, workflows, or memory.


## Report

`goalforge-retrospect <feature-dir> [--since <seq>]` (task-02) writes exactly one
file — `<feature-dir>/improvement-report.md` — a deterministic, byte-idempotent,
**propose-only** projection of the `issue.recorded` trace window. It CONSUMES the
shared `scripts/goalforge-trace-read` helper (torn-tail skip + `schema_version`
branch select, B-12-SEAM) — never a second parser. No LLM call, no wall-clock,
repo-relative paths only; two runs over the same window are byte-identical. An
absent or empty log yields an explicit empty report and exit 0 (zero-breakage).
`--since <seq>` windows a lap to events with `seq >= since` (default = whole log).

The report carries three contracted sections:

- **Bottlenecks** — ranking v1 (B-15-RANKING): a deterministic GROUP + COUNT per
  `(kind, wp)` with recency (last `seq`). NO thresholds, NO auto-detection, NO
  per-kind branch (`dispatch-mismatch` is counted by the uniform group, never a
  special branch). Row fields: `Rank | Kind | WP | Count | Last seq`, ranked by
  count desc, then recency desc, then kind/wp for a stable tie-break.
- **Issues Chased** — one row per issue event in the window (chronological by
  `seq`). Row fields: `Seq | Kind | WP | Summary | Resolution pointer`. Resolution
  is REPORT-side (B-15-SCHEMA — the event has no resolution field): the pointer is
  the repo-relative `decision_ref`, or `unresolved` when none was captured.
- **Routed Proposals** — one row per distinct kind present: `Kind | Routing
  target`. Targets project the authority `rules/common/learning-routing.md`, which
  the section CITES verbatim (including the ≥2× skill-defect threshold) — never a
  divergent baked copy.

**Propose-only rule:** a distiller run mutates ONLY `improvement-report.md`. It
never edits skills, rules, workflows, or memory — applying any proposal routes
through `/skill-improve` (eval-gated), idea-capture, or `memory-write`, human-gated
per the Auto-Research / Auto-Improve Contract. Judgment enrichment (real
resolution status, evidence prose) happens in the consuming session ON TOP of this
deterministic report, never inside the eval-gated distiller path.
