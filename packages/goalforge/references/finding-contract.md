# Finding contract v1

One flat JSON object per finding, `schema_version: 1`. Machine form:
`references/schema/finding.schema.json` (JSON Schema draft-07). SARIF 2.1.0 is
the import/export mapping, not the wire format.

## Purpose

A single shape for review and analysis findings, so a router, fixer, baseline,
gates and human triage consume one thing whether a deterministic tool or a
model produced it.

## Fields

det = deterministic producer, model = model producer. M = mandatory, O =
optional, `-` = not emitted.

| Field | Type | det | model | SARIF 2.1.0 | Consumer |
|---|---|---|---|---|---|
| `schema_version` | const `1` | M | M | `properties.schema_version` | all |
| `id` | string (uuid) | M | M | `result.guid` | router, `finding.recorded` |
| `producer` | `{name, kind: deterministic\|model}` | M | M | `run.tool.driver.name`; kind → `properties.producer_kind` | router, eval harness |
| `rule_id` | string | M | O | `result.ruleId` | baseline, fixer acceptance re-run, eval harness |
| `severity` | `CRITICAL\|HIGH\|MEDIUM\|LOW` | M | M | `result.level` (CRITICAL/HIGH→error, MEDIUM→warning, LOW→note); exact value in `properties.severity` | gates, router |
| `confidence` | `high\|medium\|low` | O | O | `properties.confidence` | human triage, false-positive graduation sampling |
| `location` | `{file, start_line, end_line?}` | M | M | `result.locations[0].physicalLocation.{artifactLocation.uri, region.startLine, region.endLine}` | fixer, human, baseline |
| `what` | string, one plain sentence | M | M | `result.message.text` | human, fixer |
| `analysis_kind` | `taint\|path\|pattern\|complexity\|secret\|dep\|intent` | M | M | `properties.analysis_kind` | router, groundedness check |
| `why_it_matters` | string: concrete failure or exploit scenario | O | M | `properties.why_it_matters` | human, fixer |
| `trace` | `location[]`, source → sink | M if kind ∈ {taint, path}, else O | O | `result.codeFlows[0].threadFlows[0].locations[]` | fixer, groundedness check |
| `fix` | string (prose) | O | O | `properties.fix` (SARIF `fixes[]` needs `artifactChanges`; prose does not fit) | fixer, human |
| `fingerprint` | string | M | - | `result.partialFingerprints.<key>`; key and algorithm owned by ticket-03 | baseline |

## Reserved names

Never set by producers; consumers stamp them. The schema admits them as
optional, loosely typed.

- `suppression` → `result.suppressions[]` (ticket-22)
- `baseline_state` → `result.baselineState` (ticket-03)
- `route_to` → `properties.route_to` (ticket-30)

## `finding.recorded` projection

The optional `severity` / `summary` / `category` fields of the
`finding.recorded` trace event are a projection of this contract:

- `severity` ← `severity`
- `summary` ← `what`
- `category` ← `analysis_kind`

Adding `finding_id` to that event is separate work (ticket-30).

## Who may emit

- plan-reviewer findings qualify: `file:line` plus evidence,
  `analysis_kind: intent`.
- goalforge Gate C rubric items do not. They are per-WP verdicts
  `{id, result, evidence}` with no code location.

## Known v1 gap

Model findings carry no `rule_id` or `fingerprint`, so they cannot be
ratcheted in v1. Accepted; ticket-13 and ticket-03 revisit it. The schema does
not reject a `fingerprint` on a model finding.

## Worked examples

### Deterministic taint hit (opengrep)

```json
{
  "schema_version": 1,
  "id": "6f1c2a0e-8a4b-4c1e-9d55-0b7a3e2f91c4",
  "producer": {"name": "opengrep", "kind": "deterministic"},
  "rule_id": "python.sqli.fstring-into-execute",
  "severity": "CRITICAL",
  "confidence": "high",
  "location": {"file": "app/attendees.py", "start_line": 42},
  "what": "The attendee search term is formatted straight into a SQL string.",
  "analysis_kind": "taint",
  "why_it_matters": "A search for `x' OR '1'='1` returns every attendee; a stacked query can drop tables.",
  "trace": [
    {"file": "app/routes.py", "start_line": 18},
    {"file": "app/attendees.py", "start_line": 40},
    {"file": "app/attendees.py", "start_line": 42}
  ],
  "fix": "Use a parameterized query: cursor.execute(\"... WHERE name LIKE ?\", (f\"%{q}%\",)).",
  "fingerprint": "v0:placeholder-algorithm-owned-by-ticket-03"
}
```

### Model-reviewer N+1 hit (goalforge Gate B)

```json
{
  "schema_version": 1,
  "id": "b2d7e9c4-1f3a-4e8b-a6c0-5d9f2e7a8b13",
  "producer": {"name": "goalforge-reviewer", "kind": "model"},
  "severity": "MEDIUM",
  "confidence": "medium",
  "location": {"file": "app/attendees.py", "start_line": 71, "end_line": 76},
  "what": "The roster loads each event's attendees with a separate query inside a loop.",
  "analysis_kind": "pattern",
  "why_it_matters": "100 events cost 101 queries; page latency grows linearly with event count.",
  "fix": "Load attendees in one query (JOIN or selectinload) and group in memory."
}
```

## Vendoring

Consumers outside this plugin copy `finding.schema.json` byte-identical,
pinned to a goalforge release, and keep a CI drift check against that release.
dotfiles agents ingest the field list into their own bodies and cite this file
as provenance, never as a runtime pointer.
