# Trace-Event Schema — goalforge trace substrate (wp-14)

The versioned, append-only trace-event contract for goalforge. This is the
single schema home: a human-readable spec plus a machine-checkable JSON Schema
**embedded** as the first fenced ` ```json ` block below (there is NO separate
`.schema.json` file). Consumers — goalforge-viz, the wp-15 retrospective stage,
and wp-12 workflow-authoring — read `plans/<feature>/trace-events.jsonl` against
this contract without scraping markdown.

## Artifact & write model

- **Artifact:** `plans/<feature>/trace-events.jsonl` — one JSON object per line,
  UTF-8, LF-terminated. Generated/appended only.
- **Single writer:** every producer appends through the validating emitter
  (`goalforge-trace-emit`) — never a raw `echo`/redirect. A malformed emission is
  rejected (exit 2) with the log left **byte-unchanged**.
- **Append-only:** rows are never rewritten, compacted, or migrated in this WP.
  Schema evolution rides `schema_version`; a new schema version adds a row shape,
  it never rewrites emitted rows.
- **Emitter is the sole `seq` authority** on `--write`: any `seq` a caller or the
  derivation supplies is a provisional ledger-order ordinal; the emitter assigns
  the authoritative value from the **last line** of the log (not a full-file scan).
- **Concurrency:** read-max-`seq` + append is one RMW under the emitter's own
  `flock` on `plans/<feature>/trace-events.lock`; one `write()` per row. This lock
  is independent of `goalforge-transition.sh`'s `flock -9` on
  `.sdd-transitions.lock` — the transition emit call sits OUTSIDE that critical
  section (after `flock -u 9`) so the two locks never nest.

## Envelope (every event)

| Field | Type | Required | Semantics |
|---|---|---|---|
| `seq` | integer ≥ 0 | yes | Strictly monotonic per feature log; emitter-assigned; enables O(1) since-offset tail reads. |
| `ts` | string (RFC3339 UTC, `…Z`) | yes | Emission timestamp. |
| `type` | string (enum, see below) | yes | Event type discriminator. |
| `schema_version` | integer ≥ 1 | yes | Row-level schema version. A consumer keys parsing off this; a future bump adds a `oneOf`/const branch (see below), never rewrites old rows. |

### Monotonic-`seq` rules

- `seq` starts at `0` for the first row of a feature log and increments by exactly
  the emitter's assignment order. Consumers MUST NOT assume `seq` equals the line
  index across a derive+live-emit cutover, only that it is strictly increasing.
- **Torn-tail read contract:** consumers skip an unparseable *trailing* line.
  Because the emitter issues one atomic append per row, at most the last line can
  be torn; all prior lines are complete.

### Attribution fields (reused verbatim from the attribution stamp)

Status/commit/gate events carry the attribution stamp exactly as
`goalforge-transition.sh` writes it into `.sdd-transitions.jsonl` — **no parallel
naming**:

| Field | Type | Semantics |
|---|---|---|
| `actor` | string | Who/what drove the transition (e.g. `goalforge-harden`, `auto`). |
| `mode` | string (`human`\|`auto`\|`evidence`) | Human-gated, autonomous, or evidence-gated (`evidence` = the re-harden `ready→hardened` revert, `--mode evidence`). Kept alongside `override` so a gate-rejected-vs-forced transition stays distinguishable. |
| `override` | boolean | `--override` was used (forced past a gate). |
| `session` | string | Origin session id (`unknown` on degrade). |
| `model` | string | Driving model (`unknown` on degrade). |
| `provider` | string | Model provider (`unknown` on degrade). |
| `agent` | string | Dispatched agent id, or `""`. |
| `decision_ref` | string | Pointer to the decision record (e.g. `findings.md`), or `""`. |

Degrade-not-block: any attribution lookup failure resolves to `"unknown"`/`""`;
it never blocks the emit, and the emitter warns to stderr + exits 0 on emission
failure so it never blocks the underlying chain operation.

## Event types (11)

All eleven are schema-defined here (single schema home). Producer coverage this WP:
`wp.status_changed`, `feature.status_changed`, `commit.linked`, `gate.result`
have live producers (transition wiring + legacy derivation). `issue.recorded`'s
producer is wp-15. `task.status_changed`, `finding.recorded`,
`dispatch.launched`, `dispatch.completed` are **schema-only** this lap (no
producer) — consumers treat those streams as **best-effort-empty** (D-OQ1).
`reharden.proposed`/`reharden.accepted` are added by the prototype-native
re-harden edge (this feature): their designated producer is the re-harden
transition (`goalforge-transition.sh` on the evidence-gated `ready→hardened`
edge), described here per the pinned contract even where that producer lands in a
sibling task — they are NOT schema-only.

### `wp.status_changed`

A work-package status transition. Envelope + attribution, plus:

| Field | Type | Required | Semantics |
|---|---|---|---|
| `wp` | string | yes | WP id (e.g. `wp-14-trace-substrate`). |
| `task` | string | no | Task id if the transition is task-scoped (usually absent at WP level). |
| `from` | string | yes | Prior status. |
| `to` | string | yes | New status. |
| `reason` | string | no | Free-text rationale (reverse edges require it upstream). |
| `commit` | string | no | Short commit hash at transition time. |

### `feature.status_changed`

A **feature-level** status transition (9th event type; added at harden
2026-07-19). Identical shape to `wp.status_changed`, but the `wp` field carries
the **feature** id. Distinct type because the legacy `.sdd-transitions.jsonl`
ledger **interleaves** WP-level and feature-level rows in one file, so lossless
derivation (task-04) requires a distinct feature-level event.

| Field | Type | Required | Semantics |
|---|---|---|---|
| `wp` | string | yes | Feature id (the feature dir basename). |
| `from` | string | yes | Prior feature status. |
| `to` | string | yes | New feature status. |
| `reason` | string | no | Rationale. |
| `commit` | string | no | Short commit hash. |

### `task.status_changed`

A task-level status transition. **Schema-only** this WP — no live producer and no
ledger derivation source (the ledger is WP/feature-level only, D-OQ1). Same shape
as `wp.status_changed` with `task` required.

| Field | Type | Required | Semantics |
|---|---|---|---|
| `wp` | string | yes | Parent WP id. |
| `task` | string | yes | Task id. |
| `from` | string | yes | Prior status. |
| `to` | string | yes | New status. |
| `reason` | string | no | Rationale. |

### `commit.linked`

A first-class emitted edge linking a commit to a WP — never a scraped git join.

| Field | Type | Required | Semantics |
|---|---|---|---|
| `wp` | string | yes | WP the commit belongs to. |
| `commit` | string | yes | Short (or full) commit hash. |
| `task` | string | no | Task the commit backfills, if known. |

Plus attribution fields (as above).

### `gate.result`

A machine-readable gate outcome (verification/review/hash gate, etc.).

| Field | Type | Required | Semantics |
|---|---|---|---|
| `wp` | string | yes | WP the gate ran against. |
| `gate` | string | yes | Gate name (e.g. `ready-hash`, `verify`, `review`). |
| `result` | string (`pass`\|`fail`) | yes | Outcome. |
| `reason` | string | no | Detail. |

Plus attribution fields. A gate-FAIL (rejected transition) writes NO ledger row,
so `gate.result` is only recoverable via the live emitter — one of the reasons
the emitter must exist regardless of derivation (D-OQ3).

### `finding.recorded`

A structured review/verify finding. **Schema-only** this WP — no viable owner
until a structured findings-capture helper exists (D-OQ1).

| Field | Type | Required | Semantics |
|---|---|---|---|
| `wp` | string | yes | WP the finding belongs to. |
| `severity` | string | no | e.g. `CRITICAL`\|`HIGH`\|`MEDIUM`\|`LOW`. |
| `summary` | string | no | One-line finding statement. |
| `category` | string | no | Finding category slug. |

### `dispatch.launched`

A subagent/workflow dispatch start. **Schema-only** this WP — deferred to wp-08
(needs feature-context resolver, Workflow-tool interception, registry fan-out).

| Field | Type | Required | Semantics |
|---|---|---|---|
| `wp` | string | no | WP the dispatch serves, if known. |
| `model` | string | no | Dispatched model. |
| `provider` | string | no | Provider. |
| `agent` | string | no | Agent id. |
| `effort` | string | no | Effort tier. |
| `task` | string | no | Task the dispatch serves. |

### `dispatch.completed`

A dispatch completion. **Schema-only** this WP (wp-08, as above).

| Field | Type | Required | Semantics |
|---|---|---|---|
| `wp` | string | no | WP the dispatch served. |
| `agent` | string | no | Agent id. |
| `outcome` | string | no | e.g. `success`\|`failure`\|`parked`. |
| `exit_code` | integer | no | Process exit code, if applicable. |

### `issue.recorded`

An issue/bottleneck event. Schema-owned HERE (single schema home); its capture
helper and kind-vocabulary semantics are **wp-15's** (consumer side of the pinned
contract).

| Field | Type | Required | Semantics |
|---|---|---|---|
| `kind` | string | yes | Issue kind (vocabulary owned by wp-15). |
| `summary` | string | no | One-line description. |
| `wp` | string | no | WP the issue attaches to, if any. |

### `reharden.proposed`

A proposal to re-open a `ready` WP back to `hardened` for goal re-development,
carrying the typed evidence that triggered it. Emitted when a stage proposes the
evidence-gated `ready→hardened` revert (see `references/state-machine.md`
§Policy — Evidence-gated revert exception). Producer: the re-harden transition
(`goalforge-transition.sh` on the `--mode evidence` `ready→hardened` edge).

| Field | Type | Required | Semantics |
|---|---|---|---|
| `wp` | string | yes | WP proposed for re-harden. |
| `evidence` | string | yes | Path to the re-harden evidence file (`plans/<feature>/<wp>/reharden/<YYYY-MM-DD>-<slug>.md`). |
| `kind` | string | no | Evidence kind — the SAME value as the evidence file's frontmatter `kind` (`prototype-findings`\|`execution-learning`\|`issue`); distinct vocabulary from `issue.recorded`'s `kind`. |
| `locator` | string | no | Evidence locator (path-or-url) — mirrors the evidence file's `locator`. |
| `summary` | string | no | One-line evidence summary — mirrors the evidence file's `summary`. |

Plus attribution fields (as above), with `mode: evidence` on the re-harden revert.

### `reharden.accepted`

The acceptance record for a proposed re-harden: emitted when the evidence-gated
`ready→hardened` revert is written (the WP moves back to `hardened`). Same
payload shape as `reharden.proposed`, pointing at the same evidence file.

| Field | Type | Required | Semantics |
|---|---|---|---|
| `wp` | string | yes | WP reverted to `hardened`. |
| `evidence` | string | yes | Path to the re-harden evidence file (as in `reharden.proposed`). |
| `kind` | string | no | Evidence kind — same value as the evidence file's frontmatter `kind`. |
| `locator` | string | no | Evidence locator (path-or-url) — mirrors the evidence file's `locator`. |
| `summary` | string | no | One-line evidence summary — mirrors the evidence file's `summary`. |

Plus attribution fields (as above), with `mode: evidence`.

## Legacy `.sdd-transitions.jsonl` derivation cross-check (task-04)

The legacy ledger row shape (from `goalforge-transition.sh` `do_write`) is:

```text
{ts, wp, from, to, reason, actor, override, commit, mode, session, model, provider, agent, decision_ref}
```

Every one of these field names maps **verbatim** into the trace envelope +
attribution + status-event fields above — the derivation is a lossless read-only
projection (no field renames). Mapping:

| Ledger field | Trace field | Notes |
|---|---|---|
| `ts` | `ts` | verbatim |
| `wp` | `wp` | WP id for WP rows; feature id for feature rows |
| `from` | `from` | verbatim |
| `to` | `to` | verbatim |
| `reason` | `reason` | verbatim |
| `actor` | `actor` | verbatim |
| `override` | `override` | verbatim (boolean) |
| `commit` | `commit` | verbatim |
| `mode` | `mode` | verbatim |
| `session` | `session` | verbatim |
| `model` | `model` | verbatim |
| `provider` | `provider` | verbatim |
| `agent` | `agent` | verbatim |
| `decision_ref` | `decision_ref` | verbatim |
| — | `seq` | emitter-assigned (derivation feeds rows THROUGH the emitter in ledger order; never self-assigns) |
| — | `type` | derived by row classification (below) |
| — | `schema_version` | stamped by the emitter |

**Row classification (WP-level vs feature-level).** The ledger has NO
discriminator field: both WP and feature rows share the shape above. A row is:

- a **`feature.status_changed`** source when its `wp` value is the **feature dir
  basename** itself (a feature transition targets its own dir, so `WP_NAME =
  basename(FEATURE_DIR)`), i.e. the `wp` value names a feature, not a child WP;
- a **`wp.status_changed`** source otherwise (the `wp` value names a child WP dir
  under the feature).

The ledger interleaves both, so task-04 MUST enumerate feature rows explicitly
and classify per-row — a single-type derivation would be lossy.

**No task-level source.** The ledger has NO task-level rows, so
`task.status_changed` has no derivation source (schema-only, D-OQ1). Task-04
fabricates no task-level rows.

**Cutover contract (D-OQ3, dual-emit ON).** Derivation covers ONLY pre-emitter
rows behind a recorded flag-day boundary; the live emitter is always present.
Derivation feeds rows through the emitter **in ledger order** so the emitter
remains the single `seq` authority — it never self-assigns `seq`. Eval case (g)
proves derive + live-emit on one workspace yields no duplicate and no mis-ordered
`seq` rows.

## Letter → eval-case-name mapping (for `evals/trace-substrate/run.sh`)

| Letter | Case name | What it proves |
|---|---|---|
| (a) | `emit-valid-reject` | Emitter appends a schema-valid typed event; an unknown type or missing required field is rejected exit 2, log byte-unchanged. |
| (b) | `seq-monotonic-append-only` | `seq` is strictly monotonic across appends; existing bytes are never rewritten. |
| (c) | `derive-deterministic` | A legacy ledger fixture (WP- and feature-level rows only) derives into schema-conformant events; run twice → byte-identical. |
| (d) | `transition-integration` | A transition-script fixture emits `wp.status_changed`, `feature.status_changed`, and `commit.linked` rows that validate. |
| (e) | `schema-validates-all` | Every fixture event of every type validates against the JSON Schema embedded in this doc. |
| (f) | `self-test` | `run.sh --self-test` exits 0. |
| (g) | `combined-derive-live` | Derive + live-emit on one feature yields no duplicate and no mis-ordered `seq` rows (OQ3 cutover contract holds). |

## Embedded JSON Schema (draft-07)

The machine-checkable contract. This is the **first** ` ```json ` block in the
doc — the single schema home. A `schema_version` bump adds a branch here (a
`oneOf` const branch note): a future row with `schema_version: 2` would be
validated by a version-2 branch set added alongside these, never by rewriting
these; validators select the branch set by the row's `schema_version`.

```json
{
  "$schema": "http://json-schema.org/draft-07/schema#",
  "$id": "https://goalforge/trace-events.schema.json",
  "title": "goalforge trace event",
  "type": "object",
  "required": ["seq", "ts", "type", "schema_version"],
  "properties": {
    "seq": { "type": "integer", "minimum": 0 },
    "ts": { "type": "string" },
    "type": {
      "type": "string",
      "enum": [
        "wp.status_changed",
        "feature.status_changed",
        "task.status_changed",
        "commit.linked",
        "gate.result",
        "finding.recorded",
        "dispatch.launched",
        "dispatch.completed",
        "issue.recorded",
        "reharden.proposed",
        "reharden.accepted"
      ]
    },
    "schema_version": { "type": "integer", "minimum": 1 }
  },
  "oneOf": [
    {
      "properties": {
        "type": { "const": "wp.status_changed" },
        "seq": {}, "ts": {}, "schema_version": {},
        "wp": { "type": "string" },
        "task": { "type": "string" },
        "from": { "type": "string" },
        "to": { "type": "string" },
        "reason": { "type": "string" },
        "commit": { "type": "string" },
        "actor": { "type": "string" },
        "mode": { "type": "string" },
        "override": { "type": "boolean" },
        "session": { "type": "string" },
        "model": { "type": "string" },
        "provider": { "type": "string" },
        "agent": { "type": "string" },
        "decision_ref": { "type": "string" }
      },
      "required": ["type", "wp", "from", "to"],
      "additionalProperties": false
    },
    {
      "properties": {
        "type": { "const": "feature.status_changed" },
        "seq": {}, "ts": {}, "schema_version": {},
        "wp": { "type": "string" },
        "from": { "type": "string" },
        "to": { "type": "string" },
        "reason": { "type": "string" },
        "commit": { "type": "string" },
        "actor": { "type": "string" },
        "mode": { "type": "string" },
        "override": { "type": "boolean" },
        "session": { "type": "string" },
        "model": { "type": "string" },
        "provider": { "type": "string" },
        "agent": { "type": "string" },
        "decision_ref": { "type": "string" }
      },
      "required": ["type", "wp", "from", "to"],
      "additionalProperties": false
    },
    {
      "properties": {
        "type": { "const": "task.status_changed" },
        "seq": {}, "ts": {}, "schema_version": {},
        "wp": { "type": "string" },
        "task": { "type": "string" },
        "from": { "type": "string" },
        "to": { "type": "string" },
        "reason": { "type": "string" },
        "commit": { "type": "string" },
        "actor": { "type": "string" },
        "mode": { "type": "string" },
        "override": { "type": "boolean" },
        "session": { "type": "string" },
        "model": { "type": "string" },
        "provider": { "type": "string" },
        "agent": { "type": "string" },
        "decision_ref": { "type": "string" }
      },
      "required": ["type", "wp", "task", "from", "to"],
      "additionalProperties": false
    },
    {
      "properties": {
        "type": { "const": "commit.linked" },
        "seq": {}, "ts": {}, "schema_version": {},
        "wp": { "type": "string" },
        "commit": { "type": "string" },
        "task": { "type": "string" },
        "actor": { "type": "string" },
        "mode": { "type": "string" },
        "override": { "type": "boolean" },
        "session": { "type": "string" },
        "model": { "type": "string" },
        "provider": { "type": "string" },
        "agent": { "type": "string" },
        "decision_ref": { "type": "string" }
      },
      "required": ["type", "wp", "commit"],
      "additionalProperties": false
    },
    {
      "properties": {
        "type": { "const": "gate.result" },
        "seq": {}, "ts": {}, "schema_version": {},
        "wp": { "type": "string" },
        "gate": { "type": "string" },
        "result": { "type": "string", "enum": ["pass", "fail"] },
        "reason": { "type": "string" },
        "actor": { "type": "string" },
        "mode": { "type": "string" },
        "override": { "type": "boolean" },
        "session": { "type": "string" },
        "model": { "type": "string" },
        "provider": { "type": "string" },
        "agent": { "type": "string" },
        "decision_ref": { "type": "string" }
      },
      "required": ["type", "wp", "gate", "result"],
      "additionalProperties": false
    },
    {
      "properties": {
        "type": { "const": "finding.recorded" },
        "seq": {}, "ts": {}, "schema_version": {},
        "wp": { "type": "string" },
        "severity": { "type": "string" },
        "summary": { "type": "string" },
        "category": { "type": "string" },
        "actor": { "type": "string" },
        "session": { "type": "string" },
        "model": { "type": "string" },
        "provider": { "type": "string" },
        "agent": { "type": "string" },
        "decision_ref": { "type": "string" }
      },
      "required": ["type", "wp"],
      "additionalProperties": false
    },
    {
      "properties": {
        "type": { "const": "dispatch.launched" },
        "seq": {}, "ts": {}, "schema_version": {},
        "wp": { "type": "string" },
        "model": { "type": "string" },
        "provider": { "type": "string" },
        "agent": { "type": "string" },
        "effort": { "type": "string" },
        "task": { "type": "string" },
        "session": { "type": "string" },
        "decision_ref": { "type": "string" }
      },
      "required": ["type"],
      "additionalProperties": false
    },
    {
      "properties": {
        "type": { "const": "dispatch.completed" },
        "seq": {}, "ts": {}, "schema_version": {},
        "wp": { "type": "string" },
        "agent": { "type": "string" },
        "outcome": { "type": "string" },
        "exit_code": { "type": "integer" },
        "session": { "type": "string" },
        "decision_ref": { "type": "string" }
      },
      "required": ["type"],
      "additionalProperties": false
    },
    {
      "properties": {
        "type": { "const": "issue.recorded" },
        "seq": {}, "ts": {}, "schema_version": {},
        "kind": { "type": "string" },
        "summary": { "type": "string" },
        "wp": { "type": "string" },
        "actor": { "type": "string" },
        "session": { "type": "string" },
        "decision_ref": { "type": "string" }
      },
      "required": ["type", "kind"],
      "additionalProperties": false
    },
    {
      "properties": {
        "type": { "const": "reharden.proposed" },
        "seq": {}, "ts": {}, "schema_version": {},
        "wp": { "type": "string" },
        "evidence": { "type": "string" },
        "kind": { "type": "string" },
        "locator": { "type": "string" },
        "summary": { "type": "string" },
        "actor": { "type": "string" },
        "mode": { "type": "string" },
        "override": { "type": "boolean" },
        "session": { "type": "string" },
        "model": { "type": "string" },
        "provider": { "type": "string" },
        "agent": { "type": "string" },
        "decision_ref": { "type": "string" }
      },
      "required": ["type", "wp", "evidence"],
      "additionalProperties": false
    },
    {
      "properties": {
        "type": { "const": "reharden.accepted" },
        "seq": {}, "ts": {}, "schema_version": {},
        "wp": { "type": "string" },
        "evidence": { "type": "string" },
        "kind": { "type": "string" },
        "locator": { "type": "string" },
        "summary": { "type": "string" },
        "actor": { "type": "string" },
        "mode": { "type": "string" },
        "override": { "type": "boolean" },
        "session": { "type": "string" },
        "model": { "type": "string" },
        "provider": { "type": "string" },
        "agent": { "type": "string" },
        "decision_ref": { "type": "string" }
      },
      "required": ["type", "wp", "evidence"],
      "additionalProperties": false
    }
  ]
}
```

## Example rows (illustrative — not the schema)

```text
{"seq":0,"ts":"2026-07-19T09:00:00Z","type":"wp.status_changed","schema_version":1,"wp":"wp-14-trace-substrate","from":"spec","to":"hardened","reason":"OQs to zero","actor":"goalforge-harden","override":false,"commit":"016ac03","mode":"auto","session":"80ec009c","model":"opus","provider":"anthropic","agent":"","decision_ref":"findings.md"}
{"seq":1,"ts":"2026-07-19T09:05:00Z","type":"feature.status_changed","schema_version":1,"wp":"goalforge","from":"ready","to":"executing","reason":"execute lap","actor":"goalforge-execute","override":false,"commit":"016ac03","mode":"auto","session":"80ec009c","model":"opus","provider":"anthropic","agent":"","decision_ref":""}
{"seq":2,"ts":"2026-07-19T09:10:00Z","type":"commit.linked","schema_version":1,"wp":"wp-14-trace-substrate","commit":"deadbee","task":"task-01-event-schema","actor":"goalforge-execute","override":false,"session":"80ec009c","model":"opus","provider":"anthropic","agent":"","decision_ref":"","mode":"auto"}
{"seq":3,"ts":"2026-07-19T09:12:00Z","type":"gate.result","schema_version":1,"wp":"wp-14-trace-substrate","gate":"verify","result":"pass","reason":"all tasks verified","actor":"goalforge-verify","override":false,"session":"80ec009c","model":"opus","provider":"anthropic","agent":"","decision_ref":"","mode":"auto"}
```
