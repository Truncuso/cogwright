#!/usr/bin/env bash
# goalforge-respec.test.sh — wp-10 respec edge oracle (behaviors b1-b6) plus a
# known-bad self-check: every case must pass on the shipped files and turn red
# on each one-edit copy under evals/fixtures/respec/known-bad/.
#
#   b1  goalforge-respec-diff.sh buckets over evals/fixtures/respec/pairs/
#   b2  grep -F literal list over the live docs (L1-L4, N1-N3, R1, S1)
#   b3  goalforge-respec-apply.sh WP effects, no status write, idempotent rerun,
#       partial apply resumed (static fixture evals/fixtures/respec/partial/)
#   b4  Feature edges table + Feature policy prose; goalforge-smoke.sh walk
#   b5  apply refuses each of eight broken ratifications, tree byte-identical
#   b6  ratified apply: spec.md == proposed-spec.md, one facet=outcome row more
#
# Systems under test come from env overrides (default: the shipped path):
#   RESPEC_DIFF RESPEC_APPLY SPEC_SKILL_MD RUN_SKILL_MD README_MD PKG_SKILL_MD
#   COMMANDS_SPEC_MD CHAIN_YAML RESPEC_MD STATE_MACHINE_MD SMOKE
set -uo pipefail

SD="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PKG="$(cd "$SD/../.." && pwd)"
FX="$PKG/evals/fixtures/respec"
KB="$FX/known-bad"
PROP_REL="respec/2026-09-01-tighten-c2"

RESPEC_DIFF="${RESPEC_DIFF:-$PKG/scripts/goalforge-respec-diff.sh}"
RESPEC_APPLY="${RESPEC_APPLY:-$PKG/scripts/goalforge-respec-apply.sh}"
SPEC_SKILL_MD="${SPEC_SKILL_MD:-$PKG/spec/SKILL.md}"
RUN_SKILL_MD="${RUN_SKILL_MD:-$PKG/run/SKILL.md}"
README_MD="${README_MD:-$PKG/README.md}"
PKG_SKILL_MD="${PKG_SKILL_MD:-$PKG/SKILL.md}"
COMMANDS_SPEC_MD="${COMMANDS_SPEC_MD:-$PKG/commands/spec.md}"
CHAIN_YAML="${CHAIN_YAML:-$PKG/run/chain.yaml}"
RESPEC_MD="${RESPEC_MD:-$PKG/references/respec.md}"
STATE_MACHINE_MD="${STATE_MACHINE_MD:-$PKG/references/state-machine.md}"
SMOKE="${SMOKE:-$PKG/scripts/goalforge-smoke.sh}"
# Only the b3 (b) known-bad reads this: the transition it must not call.
export RESPEC_TRANSITION="$PKG/scripts/goalforge-transition.sh"

PASS=0; FAIL=0
ok()  { echo "  PASS: $1"; PASS=$((PASS+1)); }
bad() { echo "  FAIL: $1"; FAIL=$((FAIL+1)); }
why() { echo "      - $1"; }

T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT

manifest() { (cd "$1" && find . -type f -print0 | sort -z | xargs -0 sha256sum); }
fresh() {  # $1 = fixture root (tree|partial) -> prints a new temp plans root
  local d; d="$(mktemp -d "$T/root.XXXXXX")"
  cp -a "$FX/$1/." "$d/"
  printf '%s\n' "$d"
}
has() { grep -qF -- "$2" "$1"; }

RAT_DATE="$(grep -oE 'date=[0-9-]+' "$FX/tree/feat/$PROP_REL/RATIFIED" | head -1 | cut -d= -f2)"

# ── b1 ───────────────────────────────────────────────────────────────────────
b1_case() {
  local sut="$1" rc=0 d out before after
  before="$(manifest "$FX/pairs")"
  for d in "$FX"/pairs/*/; do
    out="$(bash "$sut" "$d/approved.md" "$d/proposed.md" 2>/dev/null)" || { why "$(basename "$d"): diff exited non-zero"; rc=1; continue; }
    if [[ "$(jq -S -c . <<<"$out" 2>/dev/null)" != "$(jq -S -c . "$d/expected.json")" ]]; then
      why "$(basename "$d"): got $out"; rc=1
    fi
  done
  after="$(manifest "$FX/pairs")"
  [[ "$before" == "$after" ]] || { why "diff wrote into the fixture tree"; rc=1; }
  return "$rc"
}

# ── b2 ───────────────────────────────────────────────────────────────────────
b2_case() {  # $1 spec $2 run $3 readme $4 pkg-skill $5 commands $6 chain $7 respec
  local spec="$1" run="$2" readme="$3" skill="$4" cmd="$5" chain="$6" respec="$7" rc=0 l f
  for l in 'spec → ready is the single human-gated spec-approval transition' \
           'the stage writes the proposal and parks; it never writes RATIFIED' \
           'an unratified or unreconciled second pass' \
           'spec.md changes only through goalforge-respec-apply.sh'; do
    has "$spec" "$l" || { why "spec/SKILL.md lacks: $l"; rc=1; }
  done
  for l in '(the feature gate) is one of two human-gated transitions' 'are written only after user approval'; do
    has "$spec" "$l" && { why "spec/SKILL.md still carries: $l"; rc=1; }
  done
  for f in "$spec" "$cmd" "$readme" "$skill" "$chain"; do
    for l in 'draft → ready' 'draft -> ready'; do
      has "$f" "$l" && { why "$(basename "$f") still carries: $l"; rc=1; }
    done
  done
  for l in unchanged changed dropped added ambiguous 'ready -> spec' 'active -> spec' \
           'executing -> spec' 'completed -> spec' 'respec/<YYYY-MM-DD>-<slug>/proposed-spec.md' \
           'ratified_by: human date=' 'diff_sha256=' 'base_sha256=' 'goalforge-respec-apply.sh' \
           'superseded_by:' 'goalforge-goal-changelog.sh' 'records, not proves, a human reply'; do
    has "$respec" "$l" || { why "respec.md lacks: $l"; rc=1; }
  done
  has "$run" '| `spec` | feature | spec (ratify) | `goalforge-spec` | human at `spec → ready` |' \
    || { why "run/SKILL.md lacks the S1 feature-spec row"; rc=1; }
  return "$rc"
}
b2_live() { b2_case "$SPEC_SKILL_MD" "$RUN_SKILL_MD" "$README_MD" "$PKG_SKILL_MD" "$COMMANDS_SPEC_MD" "$CHAIN_YAML" "$RESPEC_MD"; }

# ── b3 ───────────────────────────────────────────────────────────────────────
status_lines() { local f; for f in "$1"/feat/overview.md "$1"/feat/wp-*/overview.md; do [[ -f "$f" ]] && grep -m1 '^status:' "$f"; done; }
b3_case() {
  local sut="$1" rc=0 r p m0 m1 m2 mp out wp1 ev st0
  r="$(fresh tree)"; m0="$(manifest "$r")"; st0="$(status_lines "$r")"
  cp "$r/feat/overview.md" "$T/feat-overview.before"; cp "$r/feat/.sdd-transitions.jsonl" "$T/ledger.before"
  cp "$r/feat/wp-03-gamma/overview.md" "$T/gamma.before"
  out="$(bash "$sut" "$r/feat" "$r/feat/$PROP_REL" 2>/dev/null)" || { why "first run exited non-zero"; rc=1; }
  wp1="$r/feat/wp-01-alpha/overview.md"
  if [[ -f "$wp1" ]]; then
    has "$wp1" 'superseded_by:' || { why "C2 verified WP lacks superseded_by:"; rc=1; }
    grep -qx 'status: verified' "$wp1" || { why "C2 verified WP lost status: verified"; rc=1; }
    [[ "$(grep -c '^## Supersession' "$wp1")" -eq 1 ]] || { why "C2 WP does not carry exactly one ## Supersession"; rc=1; }
    grep -q "^- date=$RAT_DATE " "$wp1" || { why "Supersession note date= is not RATIFIED date=$RAT_DATE"; rc=1; }
    [[ -f "$r/feat/wp-01-alpha/evidence.txt" ]] || { why "C2 WP lost a prior file"; rc=1; }
  else
    why "C2 verified WP overview is gone (evidence removed)"; rc=1
  fi
  ev="$r/feat/wp-02-beta/reharden/$RAT_DATE-respec-tighten-c2.md"
  if [[ -f "$ev" ]]; then
    has "$ev" 'kind: execution-learning' || { why "reharden evidence kind is not execution-learning"; rc=1; }
    has "$ev" "locator: $PROP_REL/diff.json" || { why "reharden evidence locator is not the diff.json"; rc=1; }
  else
    why "missing reharden/$RAT_DATE-respec-tighten-c2.md"; rc=1
  fi
  cmp -s "$T/gamma.before" "$r/feat/wp-03-gamma/overview.md" || { why "unrelated WP changed"; rc=1; }
  cmp -s "$T/feat-overview.before" "$r/feat/overview.md" || { why "feature overview changed (status write)"; rc=1; }
  cmp -s "$T/ledger.before" "$r/feat/.sdd-transitions.jsonl" || { why ".sdd-transitions.jsonl changed"; rc=1; }
  [[ "$st0" == "$(status_lines "$r")" ]] || { why "a status: field changed"; rc=1; }
  [[ "$(jq -c '.superseded' <<<"$out" 2>/dev/null)" == '["wp-01-alpha"]' ]] || { why "report does not name the superseded WP"; rc=1; }
  [[ "$(jq -c '.reharden' <<<"$out" 2>/dev/null)" == '["wp-02-beta"]' ]] || { why "report does not name the reharden WP"; rc=1; }
  m1="$(manifest "$r")"
  [[ "$m0" != "$m1" ]] || { why "first run wrote nothing"; rc=1; }
  bash "$sut" "$r/feat" "$r/feat/$PROP_REL" >/dev/null 2>&1 || { why "rerun exited non-zero (refused, not a no-op)"; rc=1; }
  m2="$(manifest "$r")"
  [[ "$m1" == "$m2" ]] || { why "rerun changed files (not idempotent)"; rc=1; }
  p="$(fresh partial)"
  bash "$sut" "$p/feat" "$p/feat/$PROP_REL" >/dev/null 2>&1 || { why "partial-apply run exited non-zero"; rc=1; }
  mp="$(manifest "$p")"
  [[ "$mp" == "$m1" ]] || { why "partial apply did not converge to the first run's tree"; rc=1; }
  return "$rc"
}

# ── b4 ───────────────────────────────────────────────────────────────────────
feature_rows() {  # prints "from to rr hg" per Feature edges row
  awk -F'|' '
    /^## /{ inside = ($0 ~ /^## Feature edges[[:space:]]*$/); next }
    inside && /^\|/ {
      for (i = 2; i <= 5; i++) { gsub(/^[ \t]+|[ \t]+$/, "", $i) }
      if ($2 == "from" || $2 ~ /^-+$/) next
      print $2, $3, $4, $5
    }' "$1"
}
policy_bullet() {  # $1 file, $2 bullet label -> the Feature policy bullet text
  awk -v lab="$2" '
    /^## /{ inside = ($0 ~ /^## Feature policy/); next }
    inside && /^- \*\*/ { grab = (index($0, "- **" lab "**") == 1) }
    inside && grab { print }' "$1"
}
b4_case() {
  local sm="$1" rc=0 rows out_draft out_spec gated e hum fwd
  rows="$(feature_rows "$sm")"
  out_draft="$(awk '$1=="draft"{print $2}' <<<"$rows" | sort | tr '\n' ' ')"
  out_spec="$(awk '$1=="spec"{print $2}' <<<"$rows" | sort | tr '\n' ' ')"
  [[ "$out_draft" == "spec " ]] || { why "draft out-edges are {$out_draft}, expected {spec}"; rc=1; }
  [[ "$out_spec" == "draft ready " ]] || { why "spec out-edges are {$out_spec}, expected {draft ready}"; rc=1; }
  gated="$(awk '$2=="ready" && $4=="yes"{print $1"->"$2}' <<<"$rows" | tr '\n' ' ')"
  [[ "$gated" == "spec->ready " ]] || { why "human-gated edges into ready: {$gated}, expected {spec->ready}"; rc=1; }
  for e in ready active executing completed; do
    [[ "$(awk -v f="$e" '$1==f && $2=="spec"{print $3}' <<<"$rows")" == "yes" ]] \
      || { why "respec edge $e -> spec missing or not reason_required: yes"; rc=1; }
  done
  hum="$(policy_bullet "$sm" 'Human-gated')"
  grep -qF -- '`spec -> ready` is the single spec-approval gate' <<<"$hum" || { why "policy prose does not name spec -> ready the single gate"; rc=1; }
  grep -qE -- 'draft ?(->|→) ?ready' <<<"$hum" && { why "policy prose still names draft -> ready as human-gated"; rc=1; }
  fwd="$(policy_bullet "$sm" 'Forward')"
  grep -qF -- 'the only forward edge out of `draft` is' <<<"$fwd" || { why "forward rule does not state the draft/spec exceptions"; rc=1; }
  return "$rc"
}
smoke_case() {  # run a smoke SUT inside a throwaway copy of the package scripts
  local sut="$1" c
  c="$(mktemp -d "$T/pkg.XXXXXX")"
  cp -a "$PKG/scripts" "$PKG/references" "$c/"
  cp "$sut" "$c/scripts/goalforge-smoke.sh"
  bash "$c/scripts/goalforge-smoke.sh" --throwaway >"$T/smoke.out" 2>&1 || { why "smoke --throwaway exited non-zero: $(tail -1 "$T/smoke.out")"; return 1; }
}

# ── b5 ───────────────────────────────────────────────────────────────────────
b5_case() {  # $1 apply SUT, $2 variant name
  local sut="$1" v="$FX/variants/$2" r m0 m1 rc=0 f
  r="$(fresh tree)"
  [[ -d "$v" ]] || { why "no variant $2"; return 1; }
  (cd "$v" && find . -type f ! -name REMOVE -print0) | while IFS= read -r -d '' f; do cp "$v/$f" "$r/feat/$f"; done
  if [[ -f "$v/REMOVE" ]]; then while IFS= read -r f; do rm -f "$r/feat/$f"; done <"$v/REMOVE"; fi
  m0="$(manifest "$r")"
  if bash "$sut" "$r/feat" "$r/feat/$PROP_REL" >/dev/null 2>&1; then why "$2: apply exited 0"; rc=1; fi
  m1="$(manifest "$r")"
  [[ "$m0" == "$m1" ]] || { why "$2: tree changed"; rc=1; }
  grep -qF '"to": "ready"' "$r/feat/.sdd-transitions.jsonl" && { why "$2: a to=ready row was written"; rc=1; }
  return "$rc"
}
VARIANTS=(01-no-ratified 02-missing-date 03-missing-diff-sha 04-missing-base-sha 05-sha-mismatch 06-no-changelog-row 07-stale-diff 08-base-edited)

# ── b6 ───────────────────────────────────────────────────────────────────────
rows_of() { awk '/^## /{ inside = ($0 ~ /^## Goal Changelog/); next } inside && /^- v[0-9]+ /' "$1"; }
b6_case() {
  local sut="$1" r rc=0 n0 n1 last
  r="$(fresh tree)"
  n0="$(rows_of "$r/feat/spec.md" | wc -l)"
  bash "$sut" "$r/feat" "$r/feat/$PROP_REL" >/dev/null 2>&1 || { why "ratified apply exited non-zero"; rc=1; }
  cmp -s "$r/feat/spec.md" "$r/feat/$PROP_REL/proposed-spec.md" || { why "spec.md is not byte-identical to proposed-spec.md"; rc=1; }
  n1="$(rows_of "$r/feat/spec.md" | wc -l)"
  last="$(rows_of "$r/feat/spec.md" | tail -1)"
  [[ "$n1" -eq $((n0 + 1)) ]] || { why "Goal Changelog rows $n0 -> $n1, expected +1"; rc=1; }
  grep -qF ' facet=outcome ' <<<"$last" || { why "new changelog row is not facet=outcome"; rc=1; }
  local f; for f in proposed-spec.md diff.json RATIFIED; do
    [[ -f "$r/feat/$PROP_REL/$f" ]] || { why "proposal artifact $f not retained"; rc=1; }
  done
  return "$rc"
}

# ── live run ─────────────────────────────────────────────────────────────────
echo "=== goalforge-respec.test.sh ==="
b1_case "$RESPEC_DIFF" && ok "b1 diff buckets over every pair; fixture tree untouched" || bad "b1 diff buckets"
b2_live && ok "b2 documentation literal list (L1-L4, N1-N3, R1, S1)" || bad "b2 documentation literal list"
b3_case "$RESPEC_APPLY" && ok "b3 apply effects, no status write, rerun no-op, partial apply resumed" || bad "b3 apply effects"
b4_case "$STATE_MACHINE_MD" && ok "b4 feature edge table + policy prose" || bad "b4 feature edge table + policy prose"
smoke_case "$SMOKE" && ok "b4 goalforge-smoke.sh --throwaway walks draft -> spec -> ready -> completed" || bad "b4 smoke walk"
for v in "${VARIANTS[@]}"; do
  b5_case "$RESPEC_APPLY" "$v" && ok "b5 apply refuses $v, tree byte-identical" || bad "b5 apply refuses $v"
done
b6_case "$RESPEC_APPLY" && ok "b6 ratified apply writes the proposal and one outcome row" || bad "b6 ratified apply"
if bash "$PKG/spec/evals/run.sh" >"$T/spec-evals.out" 2>&1; then ok "spec/evals/run.sh rc 0"; else bad "spec/evals/run.sh"; sed 's/^/      /' "$T/spec-evals.out"; fi

# ── known-bad self-check: each copy must turn its case red ───────────────────
red() {  # $1 label, rest = the case command; RESPEC_TEST_VERBOSE=1 shows why
  local label="$1" out; shift
  if out="$("$@" 2>&1)"; then bad "known-bad stays green: $label"; else ok "known-bad red: $label"; fi
  [[ -n "${RESPEC_TEST_VERBOSE:-}" ]] && printf '%s\n' "$out"
  return 0
}
echo "--- known-bad self-check ---"
for k in b1a-diff-raw b1b-diff-ambiguous-resolved b1c-diff-keys-only; do red "$k" b1_case "$KB/$k.sh"; done
L=("$SPEC_SKILL_MD" "$RUN_SKILL_MD" "$README_MD" "$PKG_SKILL_MD" "$COMMANDS_SPEC_MD" "$CHAIN_YAML" "$RESPEC_MD")
for k in b2a-spec-no-gotcha b2b-spec-two-gates b2c-spec-unattended-ratifies b2d-spec-277; do
  red "$k" b2_case "$KB/$k.md" "${L[@]:1}"
done
red b2e-run-no-s1 b2_case "${L[0]}" "$KB/b2e-run-no-s1.md" "${L[@]:2}"
red b2f-readme-n2 b2_case "${L[0]}" "${L[1]}" "$KB/b2f-readme-n2.md" "${L[@]:3}"
for k in b3a-apply-archive b3b-apply-transition b3c-apply-double-note b3d-apply-rerun-refused \
         b3e-apply-early-exit b3f1-apply-wallclock-reharden b3f2-apply-wallclock-note; do
  red "$k" b3_case "$KB/$k.sh"
done
for k in "$KB"/b4[a-e]-*.md; do red "$(basename "$k" .md)" b4_case "$k"; done
red b4f-smoke-draft-completed smoke_case "$KB/b4f-smoke-draft-completed.sh"
KB5=(b5a-apply-absent-pass b5b-apply-default-date b5c-apply-default-diff-sha b5d-apply-default-base-sha
     b5e-apply-no-sha-bind b5f-apply-no-changelog-check b5g-apply-no-diff-bind b5h-apply-any-base)
for i in "${!KB5[@]}"; do red "${KB5[$i]} on ${VARIANTS[$i]}" b5_case "$KB/${KB5[$i]}.sh" "${VARIANTS[$i]}"; done
red b6-apply-noop b6_case "$KB/b6-apply-noop.sh"

echo ""
echo "Results: $PASS passed, $FAIL failed"
[[ "$FAIL" -eq 0 ]]
