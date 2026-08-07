# Migration-type WPs — rewire-impact-scan protocol

Full protocol for the rewire-impact-scan a `task_type: migration` WP MUST run.
Inline gate lives in `SKILL.md` § Step 0c; this file is the before/after command
detail, consulted only for a migration WP.

A WP whose `overview.md` frontmatter carries **`task_type: migration`** (the schema
field — NOT a tag, NOT a title/keyword heuristic) moves files or paths, so it MUST
run the rewire-impact-scan around every move: once *before* to capture the references
that need repointing, and once *after* as a dangling-reference gate. A non-migration
WP skips this step.

1. **Before the move — capture references.** For each path the WP relocates, run the
   scan and record what references it:
   ```bash
   bash ${CLAUDE_PLUGIN_ROOT}/scripts/goalforge-rewire-impact.sh <old-path>
   # → file:line:content for every reference; trailer "Found N reference(s)…"
   ```
   Consume the listing as typed DATA — it is the rewire worklist (every reference must
   be repointed to the new path when the file moves). Record the captured reference set
   in the WP `findings.md` so the rewire is auditable.

2. **After the move — dangling-reference gate.** Once the file is moved and the
   references repointed, run the post-move check against the OLD path:
   ```bash
   bash ${CLAUDE_PLUGIN_ROOT}/scripts/goalforge-rewire-impact.sh --post-move <old-path>
   # exit 0 = clean; exit 1 = dangling references remain (listed on stderr);
   # exit 2 = internal/search error (distinct from a failed gate)
   ```
   Exit 1 means references to the old path survive — a broken-sibling defect; exit 2
   means the search itself failed (investigate, do not treat as clean).
   **Do not advance the WP while the gate is non-zero:** rewire the remaining
   references (or fix the search), then re-run until it exits 0.

**Recommended Agents** for the rewire work: `refactor-cleaner` (repoint the captured
references and prune the orphans the move creates) and `cavecrew-investigator`
(read-only locate of every reference the scan surfaces).
