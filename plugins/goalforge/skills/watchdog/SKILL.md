---
name: sdd-watchdog
description: "Semantic spec-vs-diff gap audit for an SDD work package. Invoked by sdd-verify AFTER acceptance criteria pass: reconstructs the WP goal/contract, reads the changed files plus their neighbors, and reports gaps — claimed-vs-implemented mismatches, missing tests/docs at changed seams, and deviations from the spec constraints/boundaries. Light summary by default (into findings.md; material gaps recorded as recap.md loop-backs via sdd-recap); deep verify-gap.md report on opt-in. Advisory only — never blocks or rewrites sdd-verify's status-advance authority. Trigger: sdd-verify delegates a gap audit for a WP, or a user asks to audit a WP diff against its spec."
metadata:
  version: 1.1.0
hooks:
  Stop:
    - hooks:
        - type: command
          command: "$HOME/.claude/scripts/skill-measure.sh sdd-watchdog"
        - type: command
          command: "$HOME/.claude/hooks/skill-trace.sh sdd-watchdog:stop"
---

# sdd-watchdog

A **semantic** gap auditor for a verified SDD work package. After `sdd-verify`
confirms the WP's acceptance criteria pass (all tasks `verified`, `findings.md`
present, validator green), `sdd-watchdog` asks the question the mechanical gate
cannot: **does the diff actually deliver what the WP goal claimed?**

It is **advisory**. It reads, reconstructs, and reports — it never changes a
status, never blocks the `executing → verified` transition, and never rewrites
any plan file's authority fields. `sdd-verify` remains the sole status authority.

Schema reference: `~/.claude/skills/sdd/references/schema.md`.

## Scope — semantic only (boundary)

`sdd-watchdog` audits **meaning**, not bookkeeping. The mechanical/structural
checks — stale rollup, missing `commit:` hashes, status drift, table-cell
mismatch — are already enforced by `sdd-validate --strict --require-commit`
(run inside `sdd-verify`). A broader mechanical integrity sweep is tracked as
the **separate** `sdd-verification-integrity-gaps` idea. This skill does **not**
duplicate those mechanical checks. Clean split:

| Concern | Owner |
|---|---|
| Stale rollup / drift / missing hash / table-cell mismatch (mechanical) | `sdd-validate` (+ future `sdd-verification-integrity-gaps`) |
| Claimed-vs-implemented / missing tests-docs / spec deviation (semantic) | `sdd-watchdog` (this skill) |

## Inputs

- The WP `overview.md` — goal block (`outcome`, `verification`, `constraints`,
  `boundaries`) and `## Goal` prose. This is the **reconstructed contract**.
- The **WP diff range**: the cumulative diff from the WP's pre-WP baseline (the
  commit before the WP's first task commit) to HEAD — **the same cumulative
  WP-diff range `sdd-verify` already computed** for its semantic gate. Collect the
  files changed in that range **plus their immediate neighbors** (callers, siblings
  in the same module, the test file that should cover a changed seam). Using the
  commit *range* (not per-task `commit:` hashes) is robust to the one-commit-per-WP
  trace cleanup — it does not depend on any per-task commit field.
- The WP `findings.md` (decisions made during execution — a deviation recorded
  here is intentional, not a gap).

## Procedure

1. **Reconstruct the WP contract.** Read the goal block: what `outcome` was
   promised, what `constraints`/`boundaries` were set, what `verification`
   strategy was declared.
2. **Read the diff + neighbors.** Collect the files changed in the **WP diff
   range** (pre-WP baseline → HEAD — the range `sdd-verify` computed, not per-task
   `commit:` hashes) and the neighboring files a reviewer would check — the caller
   of a changed function, the test file for a changed module, the doc that
   describes a changed behavior.
3. **Audit for three gap classes:**
   - **claimed-vs-implemented** — does the diff actually do what `outcome` says?
     Flag claims with no corresponding change, and changes outside the claim.
   - **missing tests/docs** — a changed seam with no test, a new behavior with no
     doc. (Cross-check, do not re-run the mechanical "tests exist" check.)
   - **deviations** — a change that violates a stated `constraint` or strays
     outside a `boundary`, unless `findings.md` records it as intentional.
4. **Report** at the configured depth (below). Then return control to
   `sdd-verify` — the audit is advisory and the WP status is unaffected.

## Output modes

**Light summary (DEFAULT).** A short gap report appended to the WP `findings.md`
under a dated heading. When a gap is material enough to trigger a loop-back,
that loop-back is recorded in the feature's `recap.md` via `sdd-recap`
`append-loopback` (the reason field) — `recap.md` itself is script-maintained
(`do not hand-edit`), so the watchdog never writes it directly. Keeps
`sdd-verify` fast. The report shape:

```
### sdd-watchdog gap audit — <wp-slug>

- claimed-vs-implemented: <findings, or "aligned">
- missing tests/docs: <findings, or "none">
- deviations: <findings, or "none">

Verdict: <aligned | gaps-found> (advisory — does not block)
```

**Deep audit (OPT-IN).** When a WP warrants scrutiny, write a full
`<wp>/verify-gap.md` with per-file findings, the reconstructed contract, and the
neighbor-read evidence. Opt in per WP (e.g. a high-severity WP, or a `deep`
request from `sdd-verify`/the user). Not the default — deep audits cost time.

## Wiring

`sdd-watchdog` is **folded into `sdd-verify`'s single semantic pass** (not a
separate per-task pass): `sdd-verify` invokes it once, after its acceptance gate
passes and before its finalize commit, reusing the cumulative WP-diff range it
already computed, and routing the light summary into `findings.md` (and recording
any material gap as a `recap.md` loop-back via `sdd-recap`).
A `gaps-found` verdict is recorded but does **not** block finalization — it
surfaces for human follow-up (the WP is still verified; the gap is a note).

## Gotchas

- **Advisory, not a gate.** A `gaps-found` verdict NEVER blocks `executing →
  verified`. If you find yourself withholding verification on a watchdog finding,
  that is a bug — record the gap and let `sdd-verify` proceed. Hard blocking is
  the job of the acceptance gate, not the semantic audit.
- **Semantic only.** Do not re-implement `sdd-validate`'s mechanical checks
  (rollup freshness, commit hashes, drift). A finding that "the rollup is stale"
  belongs to the mechanical layer, not here — reporting it is duplication.
- **A recorded deviation is not a gap.** Before flagging a deviation, check
  `findings.md`: an intentional, documented deviation is a decision, not a gap.
- **Read neighbors, not the whole repo.** The audit reads the changed files and
  their immediate neighbors (caller, test, doc). Auditing the entire codebase is
  out of scope and defeats the "keep verify fast" intent.
- **Default is light.** Only write `verify-gap.md` on an explicit deep opt-in;
  defaulting to deep on every WP reintroduces the slowness the light mode avoids.
