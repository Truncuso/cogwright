# Role-exclusive dedup — review-lens ownership (no re-litigation)

Full ownership table + attribution rule for the review lenses harden coordinates.
Inline summary lives in `SKILL.md` § "Role-exclusive dedup"; this file is the
per-lens detail, consulted when a finding's ownership is unclear.

Each lens owns a concern; none re-surfaces another lens's resolved finding — the
same defect is never paid for twice:

- **Tier-1 feature audit** (decompose) owns cross-WP contracts, shared-file
  ownership, WP ordering, and claims-vs-source **at feature scope**.
- **Tier-2 delta** (this step) owns **WP-local** defects + consuming Tier-1.
- **interview-loop** (Step 1) is the **sole resolver** of open questions.
- **goalforge-arbiter** (Step 1) owns **architectural-approach bets only**.
- **panel** (complex path) owns **this WP's design dissent only**.

A finding **RESOLVED upstream is consumed** (cited in `findings.md`, not
re-raised). A finding still **unresolved**, or one that **regressed** (re-tripped
the freshness/hash check), **re-fires**. When in doubt about ownership, attribute
the finding to the *lowest* altitude that fully contains it.
