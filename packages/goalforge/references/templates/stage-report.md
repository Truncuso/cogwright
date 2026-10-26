<!-- Template: stage-report v1 (wp-07; the ONE human-facing stage format) -->

# Stage report — the human template

The single rendering of a `stage.report` event for a human reader (spec.md C7).
`scripts/goalforge-stage-report.sh` implements this file; chat is the rendering
surface until goalforge-viz ships a `stage.report` panel, after which this stays
the fallback, never a second format. Agent briefs (the WP brief, the judge
prompt) are separate artifacts and never reuse this template.

## Fixed order

Four sections, always in this order, never reordered and never renamed:

1. `## Changed` — what moved since the reader last saw this stage.
2. `## Issues` — one bullet per thing the reader must decide or know:
   text, evidence ref, options (pro / con), recommended, owner.
3. `## Next gate` — the ask and its ref.
4. `## Assumed known` — ids the reader profile marks seen, named not expanded.

A section with no content renders its heading and a single `- (none)` bullet, so
a missing section is always a defect and never an empty one.

## Budget: 40 rendered lines

A report renders in **at most 40 lines**. That is the whole budget, headings and
blanks included — the number exists because a report longer than one screen is
skimmed, and a skimmed gate is an unread gate.

## Overflow rule

Issues are rendered in full, in order, while the running line count leaves room
for the `## Next gate` and `## Assumed known` sections plus one overflow line.
When the budget is reached, every remaining issue collapses into a **single**
line:

```text
- +K more (<id>, <id>, …) — see <trace ref>
```

The collapsed ids are **named**, so nothing disappears silently, and the trace
ref points at the emitted row, which carries every issue in full. `K` is the
count of collapsed issues.

**`## Next gate` is never collapsed.** It is rendered before the issue budget is
computed, so an overflowing report still carries its ask. Likewise
`## Assumed known` never suppresses a gate: shrinking a gate's context is the
point, skipping the gate is not (wp-07 OQ1, C7).

## Rules for the prose inside

- One issue per bullet. Two issues in one bullet is one issue lost.
- No numbering without an id. `1.` tells the reader nothing they can cite back;
  `- [N3] …` does.
- Every `ref` is `<path>:<line>` or `<path>#<heading>` — never a paraphrase like
  "see the harden skill". The schema rejects a paraphrase, so this rule has an
  oracle, not just a preference.
- Contract ids (`C1`..`C8`, `b1`..`bn`) are expanded on first use in a report
  and bare afterwards: `C7 (human touchpoints)`, then `C7`.
- `owner` is `human` or `agent`, stated per issue, because an issue with no
  owner is an issue nobody picks up.

## Rendered shape

```text
# <stage> report — <wp>

## Changed
- <text> — <ref>

## Issues
- [<id>] <text> — <ref>
  evidence: <evidence>
  option <label>: pro <pro> / con <con>
  option <label>: pro <pro> / con <con>
  recommended: <recommended>  |  owner: <owner>
- +K more (<id>, <id>) — see <trace ref>

## Next gate
- <ask> — <ref>

## Assumed known
- <id> — already seen; see <trace ref>
```
