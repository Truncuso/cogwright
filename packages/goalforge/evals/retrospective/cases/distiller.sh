#!/usr/bin/env bash
# evals/retrospective/cases/distiller.sh — WP-15 task-02 distiller gate case.
#
# Deterministic, hermetic, offline (no network, no LLM, no Workflow tool). Drives
# goalforge-retrospect end-to-end over a fixture trace window and asserts the
# contracted behaviour:
#
#   (b) sections present + byte-idempotent (two runs identical)
#   (c) routing table maps kinds to the correct learning-routing targets AND the
#       report CITES rules/common/learning-routing.md as the authority
#   (d) absent/empty log → explicit empty report, exit 0 (zero-breakage)
#   (e) propose-only: a run mutates ONLY improvement-report.md (tree-diff)
#   (f) torn-tail: an unparseable trailing line distills identically
#   plus the distiller's own hermetic --self-test.
#
# Usage: distiller.sh   (exit 0 iff all assertions hold)
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS="$(cd "$HERE/../../../scripts" && pwd)"
RETRO="$SCRIPTS/goalforge-retrospect"
REPORT="improvement-report.md"
LOG="trace-events.jsonl"

fails=0
ok()   { printf '  ok   %s\n' "$1"; }
fail() { printf '  FAIL %s\n' "$1" >&2; fails=$((fails + 1)); }
chk()  { if eval "$2"; then ok "$1"; else fail "$1"; fi; }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# --- fixture: a feature log with grouped issues + a non-issue row --------------
FD="$TMP/feat"
mkdir -p "$FD"
{
  printf '%s\n' '{"seq":0,"ts":"t","type":"issue.recorded","schema_version":1,"kind":"retry-wall","wp":"wp-14","summary":"loop not converging","decision_ref":"findings.md"}'
  printf '%s\n' '{"seq":1,"ts":"t","type":"issue.recorded","schema_version":1,"kind":"retry-wall","wp":"wp-14","summary":"still stuck","decision_ref":"findings.md"}'
  printf '%s\n' '{"seq":2,"ts":"t","type":"issue.recorded","schema_version":1,"kind":"spec-gap","wp":"wp-13","summary":"ambiguous WP"}'
  printf '%s\n' '{"seq":3,"ts":"t","type":"issue.recorded","schema_version":1,"kind":"skill-defect","wp":"wp-14","summary":"mis-triggered","decision_ref":"plans/x/wp-14/task-01.md"}'
  printf '%s\n' '{"seq":4,"ts":"t","type":"gate.result","schema_version":1,"wp":"wp-14","gate":"verify","result":"pass"}'
} > "$FD/$LOG"

"$RETRO" "$FD" ; rc=$?
chk "populated run exits 0" "[ $rc -eq 0 ]"

# (b) sections present
for section in '## Bottlenecks' '## Issues Chased' '## Routed Proposals'; do
  chk "section present: $section" "grep -qF '$section' '$FD/$REPORT'"
done
# GROUP+COUNT: retry-wall/wp-14 count 2
chk "retry-wall/wp-14 counted twice" "grep -qE '\| retry-wall \| wp-14 \| 2 \|' '$FD/$REPORT'"
chk "non-issue events filtered out" "! grep -q 'gate.result' '$FD/$REPORT'"

# (b) byte-idempotent
cp "$FD/$REPORT" "$TMP/first.md"
"$RETRO" "$FD"
chk "byte-idempotent across two runs" "diff -q '$TMP/first.md' '$FD/$REPORT' >/dev/null"

# (c) routing authority cited + per-kind targets
chk "cites learning-routing authority" "grep -qF 'rules/common/learning-routing.md' '$FD/$REPORT'"
chk "skill-defect routes to /skill-improve" "grep -qF '/skill-improve' '$FD/$REPORT'"
chk "spec-gap routes to memory/rule" "grep -qF '.memory/' '$FD/$REPORT'"
chk "retry-wall routes to plans/ideas" "grep -qF 'plans/ideas/' '$FD/$REPORT'"
chk "no absolute home paths in report" "! grep -q '/home/' '$FD/$REPORT'"

# (e) propose-only: only the report was added to the feature dir
before="$(cd "$FD" && ls -1 | sort)"
"$RETRO" "$FD"
after="$(cd "$FD" && ls -1 | sort)"
chk "propose-only: tree unchanged but for the report" "[ \"$before\" = \"$after\" ]"
chk "propose-only: dir holds only log + report" "[ \"$after\" = \"$(printf '%s\n%s' "$REPORT" "$LOG" | sort)\" ]"

# (f) torn-tail: an unparseable trailing line distills identically
FD2="$TMP/feat-torn"
mkdir -p "$FD2"
cp "$FD/$LOG" "$FD2/$LOG"
printf '%s' '{"seq":5,"ts":"t","type":"issue.rec' >> "$FD2/$LOG"   # torn, no LF
"$RETRO" "$FD2"
# bodies match modulo the header feature-name line (line 1)
tail -n +2 "$FD/$REPORT"  > "$TMP/body-clean.md"
tail -n +2 "$FD2/$REPORT" > "$TMP/body-torn.md"
chk "torn-tail distills identically (body)" "diff -q '$TMP/body-clean.md' '$TMP/body-torn.md' >/dev/null"

# (d) absent log → explicit empty report, exit 0
FD3="$TMP/feat-absent"
mkdir -p "$FD3"
"$RETRO" "$FD3" ; rc=$?
chk "absent-log run exits 0" "[ $rc -eq 0 ]"
chk "absent log → explicit empty report" "grep -qF 'No issues recorded in the trace window.' '$FD3/$REPORT'"
chk "empty report keeps contracted sections" "grep -qF '## Routed Proposals' '$FD3/$REPORT'"

# (d) zero-byte log → empty report, exit 0
FD4="$TMP/feat-zero"
mkdir -p "$FD4"
: > "$FD4/$LOG"
"$RETRO" "$FD4" ; rc=$?
chk "zero-byte-log run exits 0" "[ $rc -eq 0 ]"
chk "zero-byte log → empty report" "grep -qF 'No issues recorded' '$FD4/$REPORT'"

# --since windows a lap
"$RETRO" "$FD" --since 3
chk "since=3 keeps skill-defect (seq 3)" "grep -qE '\| 3 \| skill-defect' '$FD/$REPORT'"
chk "since=3 drops retry-wall (seq 0)" "! grep -qE '\| 0 \| retry-wall' '$FD/$REPORT'"

# distiller's own hermetic self-test
"$RETRO" --self-test >/dev/null 2>&1 ; rc=$?
chk "goalforge-retrospect --self-test exits 0" "[ $rc -eq 0 ]"

if [ "$fails" -ne 0 ]; then
  printf 'distiller.sh: FAIL (%d)\n' "$fails" >&2
  exit 1
fi
printf 'distiller.sh: PASS\n'
