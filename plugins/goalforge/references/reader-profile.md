# Reader profile — C8

Per reader, per project state that lets a stage report say "you have seen this"
instead of explaining it again. Written and read only by
`scripts/goalforge-reader.sh` and `scripts/goalforge-stage-report.sh`.

## It is machine state, not a memory fact

Ruled 2026-09-17 (user, wp-07 R2), and `spec.md` C8 amended to match. The
profile:

- takes **no** `~/.claude/references/rules/memory.md` frontmatter — it is not a typed fact;
- earns **no** `MEMORY.md` pointer;
- triggers **no** QMD re-index, and vault curate/index sweeps skip the subtree.

It lives under `.memory/` for locality and gitignore scope only. The cogwright
repo's own `.gitignore` names `.memory/user/`, so reader data cannot be
committed from a clean clone — a machine-global ignore file is not the
guarantee.

## Location

```text
<repo>/.memory/user/<slug>/goalforge-communication-profile.md
```

Project scope only. There is **no global fallback**: a reader has one profile
per project, and nothing reads `~/.claude/.memory/`.

## Slug resolution ladder

| Rung | Source | On a bad value |
|---|---|---|
| 1 | `GOALFORGE_READER` | REFUSED, exit 2. Present-but-empty is an assertion, so it is refused too; only an UNSET variable falls through. |
| 2 | `reader:` in `<repo-root>/goalforge.yaml` | REFUSED, exit 2. The file itself is OPTIONAL — absent is a skip, never an error. |
| 3 | local-part of `git config user.email`, lowercased | degrades to rung 4 (derived, not asserted) |
| 4 | `anonymous` | one WARN, profile disabled for the run, the chain never blocks |

Every slug is anchored to `^[a-z0-9][a-z0-9._-]*$`, so `.`, `..`, `../../etc`,
`a/b`, the empty string and `Mixed@Case` never reach a path join. The resolved
path is then checked for containment under `<repo>/.memory/user/` with
`Path.resolve()` — a real containment test, not a string prefix check.

**The full email is never stored.** Only the local-part becomes a slug, and the
slug pattern admits no `@`, so no address can reach the profile file, the
emitted `stage.report` row, or the rendered report.

## Fields

| Field | Shape | Meaning |
|---|---|---|
| `seen[]` | `- <id> (<YYYY-MM-DD>)` | WP, ticket and decision ids the reader has been shown. An issue whose `id` is here moves to `assumed_known[]`. |
| `explained_terms[]` | `- <term>` | Terms already expanded for this reader. |
| `depth` | `- <stage>: brief\|standard\|full` | How much context a stage's report carries. |
| `register` | one value | Prose register for the render. |

## Write rule

The profile is written **only at a C7 touchpoint, from the human's own answer**,
through `goalforge-reader.sh mark-seen <id>` — never by an agent inferring what
a reader probably knows, and never in an unattended run. It is read at every
`stage.report` render to fill `assumed_known[]`.

`assumed_known[]` shrinks a gate's context; it never suppresses the gate itself
(wp-07 OQ1, C7).

## Example

```text
# goalforge communication profile — chris
# Machine state (spec.md C8). Not a typed memory fact.

seen:
- wp-02-schema-v6 (2026-09-14)
- ticket-48 (2026-09-14)

explained_terms:
- goal facet
- narrow hash

depth:
- spec: full
- harden: standard
- verify: brief

register: concise-technical
```
