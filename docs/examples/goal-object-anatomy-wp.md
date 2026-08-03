<!--
Source: plans/goalforge/wp-08-single-writer-hook/overview.md (untracked, local-only work package)
Scrubbed: absolute personal paths ($HOME/... -> ~), no other changes to content.
-->

# Example: goal-object anatomy (work package)

Where this sits in the chain: `/plan` output — a hardened work package (WP)
produced by decomposing a feature spec, ready for `/implement`. This is a
**real, verified** WP from cogwright's own goalforge build-out, lightly
scrubbed (absolute paths only) for public reading.

What to notice:

- The `goal:` block is the goal-object anatomy itself: `outcome` (what "done"
  means, stated as a falsifiable claim), `verification.strategy` +
  `verification.check` (an exact, runnable command with enumerated cases —
  this is what makes the WP a *verifiable* goal, not a to-do item),
  `constraints` (things the implementation must not violate), and
  `boundaries` (files/paths in scope, and an explicit NOT-in-scope note).
- `## Open Questions` shows a question raised and resolved *by a human* at
  interview, with the resolution recorded inline — not lost in chat history.
- `## Decisions` records the same resolutions in the append-only decision log
  that feeds the WP's complexity signal.
- `## Goal Changelog` is append-only: every revision to the goal's outcome or
  verification is versioned with a reason, so the goal's history survives
  redecomposition (visible here across a panel review and a later tier-1
  path-convention pass).

---

```markdown
---
name: wp-08-single-writer-hook
title: "PreToolUse hook: block direct status:/goal_approved_version edits outside sanctioned writers + regression tests"
status: verified
stage_updated: 2026-07-08
severity: MEDIUM
cross_wp_contract: false
parallel: true
depends_on:
  - wp-01-schema-v5
plan: goalforge
tags: []
task_type: code
goal:
  outcome: "a PreToolUse hook — authored in dotfiles at ~/.claude/hooks/goalforge-single-writer.sh (this WP depends only on wp-01, so it runs BEFORE the wp-02 migration; it is developed dotfiles-side, not authored directly into a plugin that doesn't exist yet at this point in the DAG) — is honestly scoped as a tool-surface write-guard: it blocks any Edit/Write/MultiEdit mutation of an EXISTING status: or goal_approved_version: frontmatter field in a plan/WP file. Bash-path mutations are exempt BY DESIGN — that is the sanctioned-writer mechanism, documented, with no caller-attribution pretence (a PreToolUse payload carries only the tool call itself, never a call-stack trace). Sanctioned writers are named by their CURRENT pre-migration names — sdd-transition.sh, sdd-goal-hash.sh (renamed goalforge-transition.sh/goalforge-goal-hash.sh at wp-02) — proven by a block+allow regression suite under hooks/tests/. Separately, sdd-transition.sh's ready-gate learns the schema_version>=5 goal-mandatory rule: it refuses a WP's →ready transition when the WP is schema_version:5+ and carries no goal: block, closing the transition-vs-validate gate mismatch the wp-01 verify pass found (a goal-less v5 WP could reach `ready` via the transition path and then be immediately rejected as fatal by sdd-validate.sh). **Handover to wp-02**: once authored and wired here, wp-02's migration (its script/hook rename sweep) picks up this hook and moves it into the plugin's own $COGWRIGHT_ROOT/plugins/goalforge/hooks/hooks.json — that move is wp-02's scope, not re-done here."
  verification:
    strategy: deterministic
    check: "bash ~/.claude/hooks/tests/goalforge-single-writer.test.sh — cases: (a) an Edit tool_input changing an existing status: → BLOCK (exit 2) with a message naming the sanctioned writer; (b) the same mutation performed by the sanctioned writer via Bash/sed → NOT intercepted (exemption by construction; test asserts the hook only matches Edit/Write/MultiEdit tool payloads); (c) a goal_approved_version: Edit → BLOCK; (d) an edit to an unrelated frontmatter field (e.g. title:) → ALLOW (out of scope); (e) a fresh-file creation stamping an initial status: (template scaffolding) → ALLOW (not a mutation of an existing field); (f) a repo-scoped plan file (<repo>/plans/…) → protected same as ~/.claude/plans/ (dual plans-root fixture); (g) a MultiEdit tool_input batching multiple edits, one of which mutates an existing status: → BLOCK (the batch-edit path must not evade the single-edit check); (h) hook --self-test → exit 0; (i) transition ready-gate — a goal-less schema_version:5 WP fixture at `hardened` is REFUSED by sdd-transition.sh's →ready transition, plus sdd-transition.sh --self-test exits 0. Live wiring into ~/.claude/settings.json PreToolUse is asserted by task-04's own verify (grep), not re-asserted in this hermetic suite. The plugin's hooks/hooks.json registration is wp-02's gate (its dependency-audit task), not asserted here — this WP's dotfiles-side wiring is what this gate checks."
  constraints:
    - "false-positive risk on template scaffolding (creating a new file with a fresh status: field) must not be blocked — the hook targets edits to an EXISTING status:/goal_approved_version:, not initial authoring"
    - "no caller-attribution pretence: a PreToolUse payload carries only the tool call itself; the sanctioned-writer exemption is by construction (Bash mutations are not Edit/Write tool calls), never a claimed call-stack trace"
    - "plans-root resolved per the dual convention (git-root <repo>/plans/ first, else ~/.claude/plans/) — do not copy sdd-frontmatter-touch.sh's hardcoded home-directory path (known precedent bug)"
    - "division of labor with hooks/sdd-transition-guard.sh (resolved 2026-07-08, human): sdd-transition-guard.sh stays a SEPARATE, unwired advisory guard scoped to edge-legality (is this status: transition a legal edge in the state machine); this single-writer hook owns field-mutation protection (who/how a status:/goal_approved_version: field gets written) and is a HARD wired PreToolUse block. The two do not merge or supersede one another; the split is documented in both hook files' headers."
  boundaries:
    - "~/.claude/hooks/goalforge-single-writer.sh (authored here, dotfiles-side — this WP runs pre-migration per depends_on: [wp-01] only)"
    - "~/.claude/hooks/tests/goalforge-single-writer.test.sh"
    - "~/.claude/settings.json (PreToolUse wiring only)"
    - "NOT in scope: $COGWRIGHT_ROOT/plugins/goalforge/hooks/hooks.json — the plugin-side registration is wp-02's handover (its dependency-audit/hook-wiring task), not authored by this WP"
inherits_from: goalforge
goal_approved_version: "90352e54b01a"
relationships:
  - depends_on: [[wp-01-schema-v5]]
sources: []
---

<!-- Template: wp-overview v4 (frontmatter-first, flat layout) -->

## Goal

A PreToolUse hook, authored dotfiles-side at ~/.claude/hooks/goalforge-single-writer.sh
(this WP runs pre-migration — it depends only on wp-01), is honestly scoped
as a tool-surface write-guard: it blocks direct Edit/Write/MultiEdit
mutation of an EXISTING status:/goal_approved_version: frontmatter field
outside the sanctioned writers (sdd-transition.sh, sdd-goal-hash.sh — the
CURRENT pre-migration names; renamed goalforge-transition.sh/
goalforge-goal-hash.sh at wp-02), which are exempt BY DESIGN because they
mutate via Bash and never trip the Edit/Write/MultiEdit tool matcher — no
caller-attribution pretence. A block+allow regression suite proves it, with
a scaffolding false-positive exemption. Separately, sdd-transition.sh's
ready-gate learns the schema_version>=5 goal-mandatory rule: it refuses a
goal-less v5 WP's →ready transition, closing the transition-vs-validate gate
mismatch found at wp-01 verify. wp-02's migration later hands this hook over
into the plugin's own hooks/hooks.json — that move is wp-02's scope, not
this WP's.

## Verification

```
bash ~/.claude/hooks/tests/goalforge-single-writer.test.sh
```

## Tasks

| Task | Title | Status | Complexity |
|---|---|---|---|
| task-01 | single-writer-hook-script | verified | high |
| task-02 | scaffolding-false-positive-guard | verified | medium |
| task-03 | regression-test-suite | verified | medium |
| task-04 | settings-wiring | verified | low |
| task-05 | transition-ready-gate-v5 | verified | medium |

## Open Questions

- [resolved] OQ1: single-writer hook — soft (validator-only) vs hard PreToolUse backstop; false-positive risk on template scaffolding (from sdd-status-stamp idea). Resolved 2026-07-08 (human, at interview): HARD PreToolUse block (exit 2), scoped honestly as a tool-surface write-guard.
- [resolved] OQ1b: coexistence with hooks/sdd-transition-guard.sh (edge-legality guard, advisory, currently unwired) — wire alongside, merge into the single-writer hook, or supersede. Resolved 2026-07-08 (human, at interview): keep sdd-transition-guard.sh separate, unwired, advisory (edge-legality concern only); this hook owns field-mutation protection and is hard-wired — division of labor documented in both hook files.

## Decisions

<!-- Resolved design decisions (one `- ` item each). Count feeds complexity signal S2
     (decision_count). A decision usually starts as an Open Question that got answered. -->
- OQ1 resolved hard: the single-writer hook is a HARD PreToolUse block (exit 2), not a soft validator-only check — honest scoping as a tool-surface write-guard per guardrails doctrine (hard backstops soft; a conflicting instruction can't override a PreToolUse block). Resolved-by: human · session:82a44b76.
- OQ1b resolved separate: hooks/sdd-transition-guard.sh remains a separate, unwired, advisory edge-legality guard; this single-writer hook remains the sole hard field-mutation backstop. No merge, no supersede — the division is documented in both hook files' headers. Resolved-by: human · session:82a44b76.

## Goal Changelog

<!-- Append-only. Each row: - v<N> <date> facet=<facet> <old>→<new>; reason: <text> -->
- v1 2026-07-08 facet=outcome a PreToolUse hook blocks any direct Edit/Write/MultiEdit to a plan/WP file's status: or goal_approved_version: frontmatter fields; the sanctioned writers (goalforge-transition.sh, goalforge-goal-hash.sh) are exempt by construction because they mutate via Bash and never trip the Edit/Write tool matcher — proven by a block+allow regression suite under hooks/tests/.→a PreToolUse hook (shipped in the plugin's hooks/hooks.json) blocks any direct Edit/Write/MultiEdit to a plan/WP file's status: or goal_approved_version: frontmatter fields — sanctioned writers (goalforge-transition.sh, goalforge-goal-hash.sh) exempt by construction because they mutate via Bash and never trip the Edit/Write tool matcher — and the hook layer additionally emits subagent/skill lifecycle observability events (dispatch, start, stop, verdict) onto the wp-11 data-contract event log, both proven by a block+allow+emit regression suite under hooks/tests/.; reason: redecompose 2026-07-08: cogwright marketplace packaging — goalforge ships as self-contained plugin in the cogwright monorepo
- v2 2026-07-08 facet=verification bash ~/.claude/hooks/tests/goalforge-single-writer.test.sh — cases: (a) an Edit tool_input changing an existing status: → BLOCK (exit 2) with a message naming the sanctioned writer; (b) the same mutation performed by goalforge-transition.sh via Bash/sed → NOT intercepted (exemption by construction; test asserts the hook only matches Edit/Write/MultiEdit tool payloads); (c) a goal_approved_version: Edit → BLOCK; (d) an edit to an unrelated frontmatter field (e.g. title:) → ALLOW (out of scope); (e) a fresh-file creation stamping an initial status: (template scaffolding) → ALLOW (not a mutation of an existing field); (f) a repo-scoped plan file (<repo>/plans/…) → protected same as ~/.claude/plans/ (dual plans-root fixture); (g) --self-test → exit 0; hook wired into settings.json PreToolUse confirmed via grep→bash ~/.claude/hooks/tests/goalforge-single-writer.test.sh — cases: (a) an Edit tool_input changing an existing status: → BLOCK (exit 2) with a message naming the sanctioned writer; (b) the same mutation performed by goalforge-transition.sh via Bash/sed → NOT intercepted (exemption by construction; test asserts the hook only matches Edit/Write/MultiEdit tool payloads); (c) a goal_approved_version: Edit → BLOCK; (d) an edit to an unrelated frontmatter field (e.g. title:) → ALLOW (out of scope); (e) a fresh-file creation stamping an initial status: (template scaffolding) → ALLOW (not a mutation of an existing field); (f) a repo-scoped plan file (<repo>/plans/…) → protected same as ~/.claude/plans/ (dual plans-root fixture); (g) hooked lifecycle event (dispatch/start/stop/verdict) → appends a well-formed row to the wp-11 event log with a timestamp and event type (emit case); (h) --self-test → exit 0; hook wired into settings.json PreToolUse confirmed via grep; hooks/hooks.json in the plugin skeleton confirmed via grep; reason: redecompose 2026-07-08: cogwright marketplace packaging — goalforge ships as self-contained plugin in the cogwright monorepo
- v3 2026-07-08 facet=outcome a PreToolUse hook (shipped in the plugin's hooks/hooks.json) blocks any direct Edit/Write/MultiEdit ... [claimed plugin authorship despite depends_on: [wp-01] only, i.e. pre-migration]→a PreToolUse hook authored in dotfiles ~/.claude/hooks/goalforge-single-writer.sh (this WP runs pre-migration per its depends_on) blocks the same edits; wp-02's migration later hands the hook over into $COGWRIGHT_ROOT/plugins/goalforge/hooks/hooks.json — that move is wp-02's scope, not this WP's; reason: tier1 2026-07-08: cogwright path-convention propagation (WP depends_on: [wp-01] only, so it executes pre-migration in dotfiles — the outcome/check text was pretending plugin-side authorship; split made explicit, handover noted for wp-02)
- v4 2026-07-08 facet=boundaries ~/.claude/hooks/goalforge-single-writer.sh; ~/.claude/hooks/tests/goalforge-single-writer.test.sh; ~/.claude/settings.json (PreToolUse wiring only)→same, with explicit dotfiles-side authorship note on the hook path, plus an explicit NOT-in-scope line for $COGWRIGHT_ROOT/plugins/goalforge/hooks/hooks.json (that plugin-side registration is wp-02's handover); reason: tier1 2026-07-08: cogwright path-convention propagation
- v5 2026-07-08 facet=outcome a PreToolUse hook — authored in dotfiles at ~/.claude/hooks/goalforge-single-writer.sh (this WP depends only on wp-01, so it runs BEFORE the wp-02 migration; it is developed dotfiles-side, not authored directly into a plugin that does not exist yet at this point in the DAG) — blocks any direct Edit/Write/MultiEdit to a plan/WP file's status: or goal_approved_version: frontmatter fields — sanctioned writers (goalforge-transition.sh, goalforge-goal-hash.sh) exempt by construction because they mutate via Bash and never trip the Edit/Write tool matcher — and the hook layer additionally emits subagent/skill lifecycle observability events (dispatch, start, stop, verdict) onto the wp-11 data-contract event log, both proven by a block+allow+emit regression suite under hooks/tests/. Handover to wp-02: once authored and wired here, wp-02's migration (its script/hook rename sweep) picks up this hook and moves it into the plugin's own $COGWRIGHT_ROOT/plugins/goalforge/hooks/hooks.json — that move is wp-02's scope, not re-done here.→a PreToolUse hook — authored in dotfiles at ~/.claude/hooks/goalforge-single-writer.sh (this WP depends only on wp-01, so it runs BEFORE the wp-02 migration; it is developed dotfiles-side, not authored directly into a plugin that does not exist yet at this point in the DAG) — is honestly scoped as a tool-surface write-guard: it blocks any Edit/Write/MultiEdit mutation of an EXISTING status: or goal_approved_version: frontmatter field in a plan/WP file. Bash-path mutations are exempt BY DESIGN — that is the sanctioned-writer mechanism, documented, with no caller-attribution pretence (a PreToolUse payload carries only the tool call itself, never a call-stack trace). Sanctioned writers are named by their CURRENT pre-migration names — sdd-transition.sh, sdd-goal-hash.sh (renamed goalforge-transition.sh/goalforge-goal-hash.sh at wp-02) — proven by a block+allow regression suite under hooks/tests/. Separately, sdd-transition.sh's ready-gate learns the schema_version>=5 goal-mandatory rule: it refuses a WP's →ready transition when the WP is schema_version:5+ and carries no goal: block, closing the transition-vs-validate gate mismatch the wp-01 verify pass found. Handover to wp-02: once authored and wired here, wp-02's migration (its script/hook rename sweep) picks up this hook and moves it into the plugin's own $COGWRIGHT_ROOT/plugins/goalforge/hooks/hooks.json — that move is wp-02's scope, not re-done here.; reason: panel 2026-07-08: emission re-homed to wp-11, OQ1=hard OQ1b=separate (human-resolved), task-05 folded into goal
- v6 2026-07-08 facet=verification bash ~/.claude/hooks/tests/goalforge-single-writer.test.sh — cases: (a) an Edit tool_input changing an existing status: → BLOCK (exit 2) with a message naming the sanctioned writer; (b) the same mutation performed by goalforge-transition.sh via Bash/sed → NOT intercepted (exemption by construction; test asserts the hook only matches Edit/Write/MultiEdit tool payloads); (c) a goal_approved_version: Edit → BLOCK; (d) an edit to an unrelated frontmatter field (e.g. title:) → ALLOW (out of scope); (e) a fresh-file creation stamping an initial status: (template scaffolding) → ALLOW (not a mutation of an existing field); (f) a repo-scoped plan file (<repo>/plans/…) → protected same as ~/.claude/plans/ (dual plans-root fixture); (g) hooked lifecycle event (dispatch/start/stop/verdict) → appends a well-formed row to the wp-11 event log with a timestamp and event type (emit case); (h) --self-test → exit 0; hook wired into ~/.claude/settings.json PreToolUse confirmed via grep. The plugin's hooks/hooks.json registration is wp-02's gate (its dependency-audit task), not asserted here — this WP's dotfiles-side wiring is what this gate checks.→bash ~/.claude/hooks/tests/goalforge-single-writer.test.sh — cases: (a) an Edit tool_input changing an existing status: → BLOCK (exit 2) with a message naming the sanctioned writer; (b) the same mutation performed by the sanctioned writer via Bash/sed → NOT intercepted (exemption by construction; test asserts the hook only matches Edit/Write/MultiEdit tool payloads); (c) a goal_approved_version: Edit → BLOCK; (d) an edit to an unrelated frontmatter field (e.g. title:) → ALLOW (out of scope); (e) a fresh-file creation stamping an initial status: (template scaffolding) → ALLOW (not a mutation of an existing field); (f) a repo-scoped plan file (<repo>/plans/…) → protected same as ~/.claude/plans/ (dual plans-root fixture); (g) a MultiEdit tool_input batching multiple edits, one of which mutates an existing status: → BLOCK (the batch-edit path must not evade the single-edit check); (h) hook --self-test → exit 0; (i) transition ready-gate — a goal-less schema_version:5 WP fixture at hardened is REFUSED by sdd-transition.sh's →ready transition, plus sdd-transition.sh --self-test exits 0. Live wiring into ~/.claude/settings.json PreToolUse is asserted by task-04's own verify (grep), not re-asserted in this hermetic suite. The plugin's hooks/hooks.json registration is wp-02's gate (its dependency-audit task), not asserted here — this WP's dotfiles-side wiring is what this gate checks.; reason: panel 2026-07-08: emission re-homed to wp-11, OQ1=hard OQ1b=separate (human-resolved), task-05 folded into goal
- v7 2026-07-08 facet=constraints coexistence with the existing hooks/sdd-transition-guard.sh (advisory, currently-unwired edge-legality guard, renamed goalforge-transition-guard.sh in wp-02) must be decided at harden: wire alongside, merge, or supersede — the two must not independently intercept the same edits undocumented→division of labor with hooks/sdd-transition-guard.sh (resolved 2026-07-08, human): sdd-transition-guard.sh stays a SEPARATE, unwired advisory guard scoped to edge-legality (is this status: transition a legal edge in the state machine); this single-writer hook owns field-mutation protection (who/how a status:/goal_approved_version: field gets written) and is a HARD wired PreToolUse block. The two do not merge or supersede one another; the split is documented in both hook files' headers.; reason: panel 2026-07-08: emission re-homed to wp-11, OQ1=hard OQ1b=separate (human-resolved), task-05 folded into goal
```

---

Note: this is the WP's own goal-object history, unedited except for path
scrubbing (absolute personal paths replaced with `~` or a generic env var) —
including a changelog entry (v3) that records the authors catching and
correcting their own scope error mid-flight (a claimed plugin-side authorship
that turned out to be premature, given the WP's own `depends_on`), fixed via
a versioned outcome facet rather than silently rewritten. That self-correcting,
append-only changelog is the point of the pattern.
