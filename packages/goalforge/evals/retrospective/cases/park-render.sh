#!/usr/bin/env bash
# evals/retrospective/cases/park-render.sh — WP-15 task-03 handoff park-render gate (case (g)).
#
# Deterministic, hermetic, offline (no network, no LLM, no Workflow tool, no
# real handoff write). Exercises the render logic documented in the handoff
# SKILL.md § Retrospective at park/checkpoint and asserts the functional
# acceptance for the single wiring seam (B-15-WIRING):
#
#   * report EXISTS  → the rendered park body CONTAINS the Improvement Report
#                      section (heading + a repo-relative pointer to the report).
#   * trace log ABSENT   → section OMITTED cleanly, exit 0, no error (zero-breakage).
#   * distiller ABSENT   → section OMITTED cleanly, exit 0, no error.
#   * feature dir UNRESOLVED (ad-hoc / multi-feature session, OQ3) → skip WARN, exit 0.
#
# The render_park_section function below mirrors the documented SKILL.md
# procedure verbatim — it IS the acceptance oracle for that prose. The
# top-level `grep goalforge-retrospect SKILL.md` in the task verify block is the
# SMOKE check that the seam is wired; this is the FUNCTIONAL check.
#
# Usage: park-render.sh   (exit 0 iff all assertions hold)
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS="$(cd "$HERE/../../../scripts" && pwd)"
RETRO_DEFAULT="$SCRIPTS/goalforge-retrospect"
LOG="trace-events.jsonl"
REPORT="improvement-report.md"

fails=0
ok()   { printf '  ok   %s\n' "$1"; }
fail() { printf '  FAIL %s\n' "$1" >&2; fails=$((fails + 1)); }
chk()  { if eval "$2"; then ok "$1"; else fail "$1"; fi; }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# --- render_park_section: the documented SKILL.md park/checkpoint procedure ----
# Args: $1 = feature dir (empty = unresolved/ad-hoc), $2 = distiller path.
# Emits the "## Improvement Report" section to stdout when a report exists;
# otherwise emits nothing to stdout (degrade silently) — a WARN goes to stderr.
# Always exits 0: the retrospective render NEVER blocks a park.
render_park_section() {
  local feature_dir="$1" retro="$2"
  if [ -z "$feature_dir" ]; then
    printf 'WARN: no feature dir in chain context — skipping Improvement Report (ad-hoc/multi-feature session)\n' >&2
    return 0
  fi
  if [ ! -x "$retro" ]; then
    printf 'WARN: goalforge-retrospect absent — skipping Improvement Report\n' >&2
    return 0
  fi
  if [ ! -f "$feature_dir/$LOG" ]; then
    printf 'WARN: no trace log at %s — skipping Improvement Report\n' "$feature_dir/$LOG" >&2
    return 0
  fi
  "$retro" "$feature_dir" >/dev/null 2>&1 || {
    printf 'WARN: goalforge-retrospect failed — skipping Improvement Report\n' >&2
    return 0
  }
  [ -f "$feature_dir/$REPORT" ] || return 0
  printf '## Improvement Report\n\n'
  printf 'Retrospective distilled by `goalforge-retrospect` at park. Full report:\n'
  printf '`%s`\n\n' "$feature_dir/$REPORT"
  cat "$feature_dir/$REPORT"
}

# =============================================================================
# case A — report EXISTS → section rendered
FD="$TMP/feat"
mkdir -p "$FD"
{
  printf '%s\n' '{"seq":0,"ts":"t","type":"issue.recorded","schema_version":1,"kind":"retry-wall","wp":"wp-14","summary":"loop not converging","decision_ref":"findings.md"}'
  printf '%s\n' '{"seq":1,"ts":"t","type":"issue.recorded","schema_version":1,"kind":"spec-gap","wp":"wp-13","summary":"ambiguous WP"}'
} > "$FD/$LOG"

BODY="$(render_park_section "$FD" "$RETRO_DEFAULT")" ; rc=$?
chk "populated render exits 0" "[ $rc -eq 0 ]"
chk "render CONTAINS Improvement Report heading" "printf '%s' \"\$BODY\" | grep -qF '## Improvement Report'"
chk "render CONTAINS a pointer to improvement-report.md" "printf '%s' \"\$BODY\" | grep -qF 'improvement-report.md'"
chk "render embeds the distilled Bottlenecks section" "printf '%s' \"\$BODY\" | grep -qF '## Bottlenecks'"
chk "render carries no absolute home path (portable pointer)" "! printf '%s' \"\$BODY\" | grep -q '/home/'"

# =============================================================================
# case B — trace log ABSENT → section OMITTED cleanly, exit 0
FD_NOLOG="$TMP/feat-nolog"
mkdir -p "$FD_NOLOG"
BODY="$(render_park_section "$FD_NOLOG" "$RETRO_DEFAULT")" ; rc=$?
chk "no-trace-log render exits 0" "[ $rc -eq 0 ]"
chk "no-trace-log render OMITS the section (empty body)" "[ -z \"\$BODY\" ]"
chk "no-trace-log render writes no report (no distiller run)" "[ ! -f '$FD_NOLOG/$REPORT' ]"

# =============================================================================
# case C — distiller ABSENT → section OMITTED cleanly, exit 0
BODY="$(render_park_section "$FD" "$TMP/no-such-distiller")" ; rc=$?
chk "absent-distiller render exits 0" "[ $rc -eq 0 ]"
chk "absent-distiller render OMITS the section (empty body)" "[ -z \"\$BODY\" ]"

# =============================================================================
# case D — feature dir UNRESOLVED (ad-hoc/multi-feature, OQ3) → skip WARN, exit 0
BODY="$(render_park_section '' "$RETRO_DEFAULT")" ; rc=$?
chk "unresolved-feature render exits 0" "[ $rc -eq 0 ]"
chk "unresolved-feature render OMITS the section (empty body)" "[ -z \"\$BODY\" ]"

# =============================================================================
# smoke — the seam is wired into the handoff SKILL.md (task verify block half 1)
SKILL="$HOME/.claude/skills/handoff/SKILL.md"
chk "handoff SKILL.md wires goalforge-retrospect" "grep -qF 'goalforge-retrospect' '$SKILL'"
chk "handoff SKILL.md names the resident capture prompt (goalforge-issue)" "grep -qF 'goalforge-issue' '$SKILL'"

if [ "$fails" -ne 0 ]; then
  printf 'park-render.sh: FAIL (%d)\n' "$fails" >&2
  exit 1
fi
printf 'park-render.sh: PASS\n'
