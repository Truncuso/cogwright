#!/usr/bin/env bash
# goalforge-lens-ownership.test.sh — wp-12: every review concern class has one
# named owner in both harden's single-pass mode and the verify cluster, and a
# skipped lens's concerns are re-attributed by a written rule.
#
# b1: table names every concern class exactly once per mode, is a superset of
#     the T1-pinned minimum class list (verbatim tokens).
# b2: every owner is a member of the closed owner set (expertise-map.yaml
#     by_extension/by_tag/by_task_type keys for panel mode; literal
#     `harden G3` for single-pass mode; literal `Gate A`/`Gate B`/`Gate C` for
#     the verify cluster, with `owned-files-scope` pinned to `Gate A`).
# b3: harden/SKILL.md and verify/SKILL.md point at the table by path (not a
#     paraphrase), neither restates it, and both stay <= 125 lines.
# b4: a re-attribution rule section exists and no single-pass owner cell uses
#     accepted-risk/deferred/skipped/none vocabulary.
#
# Each check function below returns 0 (structurally valid) or 1 (a violation
# found) and prints its own findings to stdout. Known-good input MUST return 0
# (asserted via `expect_ok`); known-bad fixtures MUST return 1 (asserted via
# `expect_bad` — the SCRIPT passes when the checker correctly goes RED on
# sabotaged input, not when the sabotaged input itself is "clean").
# b3's known-bad copies are generated on the fly from the real SKILL.md files
# so they can never drift from what's actually shipped.
set -uo pipefail

SD="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PKG="$(cd "$SD/../.." && pwd)"
TABLE="$PKG/references/lens-ownership.md"
HARDEN_SKILL="$PKG/harden/SKILL.md"
VERIFY_SKILL="$PKG/verify/SKILL.md"
EXPERTISE_MAP="$PKG/references/expertise-map.yaml"
FIX="$PKG/evals/fixtures/lens-ownership"

PASS=0; FAIL=0
expect_ok()  { if "$@" >/tmp/lo-check-$$.out 2>&1; then PASS=$((PASS+1)); echo "  PASS: $* -> 0 (valid)"; else FAIL=$((FAIL+1)); echo "  FAIL: $* -> nonzero (want 0)"; sed 's/^/        /' /tmp/lo-check-$$.out; fi; rm -f /tmp/lo-check-$$.out; }
expect_bad() { if "$@" >/tmp/lo-check-$$.out 2>&1; then FAIL=$((FAIL+1)); echo "  FAIL: $* -> 0 (want nonzero, i.e. correctly caught as bad)"; else PASS=$((PASS+1)); echo "  PASS: $* -> nonzero (correctly caught as bad)"; sed 's/^/        /' /tmp/lo-check-$$.out; fi; rm -f /tmp/lo-check-$$.out; }

PINNED_CLASSES=(correctness error-handling complexity-delta root-cause-ai-slop \
  goal-measurability verification-coverage owned-files-scope contract-slice \
  depends-on-direction)

# ── shared parsers ──────────────────────────────────────────────────────────

# One TAB-separated "class<TAB>panel<TAB>single<TAB>verify" line per data row.
# Scoped to the literal "## Concern-class ownership table" heading line: the
# first `|` line seen after that heading is the header row, the next is the
# `---` separator (skipped), and scanning stops for good at the first blank
# line after data rows start — so a decoy pipe table whose header row also
# happens to say "Concern class" (but is not preceded by this exact heading)
# is never parsed, and rows are never picked back up from a second table
# later in the file. Counts every `|` data row in that span — backticked or
# not, indented or not — excluding only the header row itself and the `---`
# separator row.
extract_rows() {
  awk -F'|' '
    !active && /^## Concern-class ownership table/ { seen = 1; next }
    seen && !active && /^[ \t]*\|/ { active = 1; next }
    active && /^[ \t]*\| *-/ { next }
    active && /^[ \t]*\|/ {
      for (i = 2; i <= 5; i++) { gsub(/^[ \t]+|[ \t]+$/, "", $i) }
      cls = $2; gsub(/`/, "", cls)
      printf "%s\t%s\t%s\t%s\n", cls, $3, $4, $5
      next
    }
    active && /^[ \t]*$/ { exit }
  ' "$1"
}

# One key per line found under by_extension/by_tag/by_task_type in expertise-map.yaml.
extract_closed_panel_keys() {
  awk '
    /^(by_extension|by_tag|by_task_type):/ { inblock = 1; next }
    /^[A-Za-z_]/ { inblock = 0 }
    inblock && /^  [^ ]/ {
      line = $0
      sub(/^  /, "", line)
      split(line, a, ":")
      print a[1]
    }
  ' "$1"
}

# check_b1 <file>: prints violations, exits 0 iff none.
check_b1() {
  local file="$1" rc=0
  local rows classes
  rows="$(extract_rows "$file")"
  classes="$(cut -f1 <<< "$rows")"

  for c in "${PINNED_CLASSES[@]}"; do
    if ! grep -qxF "$c" <<< "$classes"; then
      echo "missing pinned class: $c"; rc=1
    fi
  done

  local dupes
  dupes="$(awk 'seen[$0]++ {print}' <<< "$classes")"
  if [ -n "$dupes" ]; then
    echo "class owned twice in the same mode: ${dupes//$'\n'/ }"; rc=1
  fi

  local empties
  empties="$(awk -F'\t' '$2=="" || $3=="" || $4=="" {print $1}' <<< "$rows")"
  if [ -n "$empties" ]; then
    echo "class left unowned in some mode: ${empties//$'\n'/ }"; rc=1
  fi
  return "$rc"
}

# check_b2 <file>: prints violations, exits 0 iff every owner is in its closed set.
check_b2() {
  local file="$1" rc=0
  local keys rows
  keys="$(extract_closed_panel_keys "$EXPERTISE_MAP")"
  rows="$(extract_rows "$file")"

  while IFS=$'\t' read -r cls panel single verify; do
    [ -z "$cls" ] && continue
    grep -qxF "$panel" <<< "$keys" || { echo "panel owner outside closed set: $cls=$panel"; rc=1; }
    [ "$single" = "harden G3" ] || { echo "single-pass owner not the literal 'harden G3': $cls=$single"; rc=1; }
    [ "$verify" = "Gate A" ] || [ "$verify" = "Gate B" ] || [ "$verify" = "Gate C" ] || { echo "verify-cluster owner not 'Gate A'/'Gate B'/'Gate C': $cls=$verify"; rc=1; }
    if [ "$cls" = "owned-files-scope" ] && [ "$verify" != "Gate A" ]; then
      echo "owned-files-scope verify-cluster owner must be 'Gate A': got $verify"; rc=1
    fi
  done <<< "$rows"
  return "$rc"
}

# check_b4_vocab <file>: prints violations, exits 0 iff no forbidden vocabulary.
check_b4_vocab() {
  local file="$1" rc=0
  local rows
  rows="$(extract_rows "$file")"
  while IFS=$'\t' read -r cls panel single verify; do
    [ -z "$cls" ] && continue
    local lc="${single,,}"
    if [[ "$lc" == *"accepted risk"* || "$lc" == *"deferred"* || "$lc" == *"skipped"* || "$lc" == "none" ]]; then
      echo "single-pass cell uses skipped/deferred/accepted-risk vocabulary: $cls=$single"; rc=1
    fi
  done <<< "$rows"
  return "$rc"
}

check_b4_section() {
  grep -qi '^## Re-attribution rule' "$1" || { echo "no '## Re-attribution rule' section"; return 1; }
  return 0
}

check_pointer() {
  grep -q 'references/lens-ownership.md' "$1" || { echo "no pointer to references/lens-ownership.md"; return 1; }
  return 0
}

check_no_restatement() {
  ! grep -q '| `correctness` |' "$1" || { echo "restates the ownership table inline"; return 1; }
  return 0
}

check_line_cap() {
  local lc; lc="$(wc -l < "$1")"
  [ "$lc" -le 125 ] || { echo "exceeds 125 lines (got $lc)"; return 1; }
  return 0
}

echo "[ b1: coverage + T1-pinned class superset ]"
expect_ok  check_b1 "$TABLE"
expect_bad check_b1 "$FIX/bad-unowned-class.md"
expect_bad check_b1 "$FIX/bad-duplicate-owner.md"
expect_bad check_b1 "$FIX/bad-missing-pinned-class.md"
expect_bad check_b1 "$FIX/bad-unbackticked-row.md"
expect_bad check_b1 "$FIX/bad-decoy-table-before-real.md"
expect_bad check_b1 "$FIX/bad-indented-duplicate-row.md"

echo "[ b2: owners in the closed set ]"
expect_ok  check_b2 "$TABLE"
expect_bad check_b2 "$FIX/bad-owner-outside-closed-set.md"
expect_bad check_b2 "$FIX/bad-owned-files-scope-not-gate-a.md"
expect_bad check_b2 "$FIX/bad-verify-owner-outside-closed-set.md"
expect_bad check_b2 "$FIX/bad-single-pass-not-g3.md"

echo "[ b4: re-attribution rule section + vocabulary ]"
expect_ok  check_b4_section "$TABLE"
expect_ok  check_b4_vocab "$TABLE"
expect_bad check_b4_vocab "$FIX/bad-accepted-risk.md"

echo "[ b3: harden/SKILL.md and verify/SKILL.md wiring ]"
expect_ok check_pointer "$HARDEN_SKILL"
expect_ok check_no_restatement "$HARDEN_SKILL"
expect_ok check_line_cap "$HARDEN_SKILL"
expect_ok check_pointer "$VERIFY_SKILL"
expect_ok check_no_restatement "$VERIFY_SKILL"
expect_ok check_line_cap "$VERIFY_SKILL"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
sed '/references\/lens-ownership\.md/d' "$HARDEN_SKILL" > "$TMP/harden-no-pointer.md"
sed '/references\/lens-ownership\.md/d' "$VERIFY_SKILL" > "$TMP/verify-no-pointer.md"
cat "$HARDEN_SKILL" "$TABLE" > "$TMP/harden-with-table.md"
cat "$VERIFY_SKILL" "$TABLE" > "$TMP/verify-with-table.md"

expect_bad check_pointer "$TMP/harden-no-pointer.md"
expect_bad check_pointer "$TMP/verify-no-pointer.md"
expect_bad check_no_restatement "$TMP/harden-with-table.md"
expect_bad check_no_restatement "$TMP/verify-with-table.md"

echo ""
echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
