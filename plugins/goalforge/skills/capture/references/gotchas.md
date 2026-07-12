# sdd-capture — edge-case gotchas (load-on-demand)

Consulted when debugging a capture footgun — not every run. The frequently-hit
gotchas stay inline in `SKILL.md`; these are the rarer footguns/recovery cases.

- **Wrong timestamp key is silently ignored.** `stage_updated:` is a WP-level
  frontmatter field and must NOT appear in a feature `overview.md` — use
  `updated:` instead. Stamping the wrong key leaves a field no downstream skill
  reads (no error, just silently dropped provenance).
- **This skill writes exactly one file (`overview.md`) — anything more means a
  skipped step.** Creating `spec.md`, `todo.md`, or any `wp-*` folder here is a
  sign the wrong entry point was used: **abort and direct the caller to the
  correct chain entry point** (the fast path's WP is authored by
  `sdd-decompose --add-wp`, not by capture).
