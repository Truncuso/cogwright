#!/usr/bin/env bash
# goalforge-respec.test.sh — wp-10 respec edge oracle (behaviors b1-b6) plus a
# known-bad self-check: every case must pass on the shipped files and turn red
# on each one-edit copy under evals/fixtures/respec/known-bad/.
#
#   b1  goalforge-respec-diff.sh buckets over evals/fixtures/respec/pairs/
#   b2  grep -F literal list over the live docs (L1-L4, N1-N3, R1, S1)
#   b3  goalforge-respec-apply.sh WP effects, no status write, idempotent rerun,
#       post-status-flip no-op on the applied state, re-supersede by a second
#       proposal, partial apply resumed (static fixture partial/), block-list
#       contract_slice (static fixture blocklist/)
#   b4  Feature edges table (route column) + Feature policy prose (F1-F3);
#       goalforge-smoke.sh walk; transition.sh route legs, four-cell Feature
#       row refused, --self-test — every transition.sh run in a package mirror
#   b5  apply refuses each of fifteen broken proposals (ratification, in-flight
#       WP, unparseable slice), tree byte-identical
#   b6  ratified apply: spec.md == proposed-spec.md, one facet=outcome row more
#
# Systems under test come from env overrides (default: the shipped path):
#   RESPEC_DIFF RESPEC_APPLY SPEC_SKILL_MD RUN_SKILL_MD README_MD PKG_SKILL_MD
#   COMMANDS_SPEC_MD CHAIN_YAML RESPEC_MD STATE_MACHINE_MD SMOKE
#   RESPEC_TRANSITION_SUT
# Known-bads added for T9-T13 pass red --why <substring>: red only when a
# failing check's message carries it, i.e. red on their own target.
set -uo pipefail

SD="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PKG="$(cd "$SD/../.." && pwd)"
FX="$PKG/evals/fixtures/respec"
KB="$FX/known-bad"
PROP_REL="respec/2026-09-01-tighten-c2"
PROP2_REL="respec/2026-09-05-widen-c2"

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
# The transition.sh under test for the b4 route runs; always executed inside a
# throwaway package mirror (transition.sh reads its table via SCRIPT_DIR only).
RESPEC_TRANSITION_SUT="${RESPEC_TRANSITION_SUT:-$PKG/scripts/goalforge-transition.sh}"
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

rat_date() { local l; l="$(<"$1")"; l="${l#* date=}"; printf '%s\n' "${l%% *}"; }
RAT_DATE="$(rat_date "$FX/tree/feat/$PROP_REL/RATIFIED")"
RAT2_DATE="$(rat_date "$FX/tree/feat/$PROP2_REL/RATIFIED")"

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
  local sut="$1" rc=0 r p bl m0 m1 m2 mf mp out wp1 ev st0 n
  r="$(fresh tree)"; m0="$(manifest "$r")"; st0="$(status_lines "$r")"
  cp "$r/feat/overview.md" "$T/feat-overview.before"; cp "$r/feat/.sdd-transitions.jsonl" "$T/ledger.before"
  cp "$r/feat/wp-03-gamma/overview.md" "$T/gamma.before"; cp "$r/feat/wp-05-epsilon/overview.md" "$T/epsilon.before"
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
    grep -qx 'since_ready_ts: none' "$ev" || { why "reharden evidence does not record since_ready_ts: none (no -> ready row)"; rc=1; }
  else
    why "missing reharden/$RAT_DATE-respec-tighten-c2.md"; rc=1
  fi
  cmp -s "$T/gamma.before" "$r/feat/wp-03-gamma/overview.md" || { why "unrelated WP changed"; rc=1; }
  cmp -s "$T/feat-overview.before" "$r/feat/overview.md" || { why "feature overview changed (status write)"; rc=1; }
  cmp -s "$T/ledger.before" "$r/feat/.sdd-transitions.jsonl" || { why ".sdd-transitions.jsonl changed"; rc=1; }
  [[ "$st0" == "$(status_lines "$r")" ]] || { why "a status: field changed"; rc=1; }
  cmp -s "$T/epsilon.before" "$r/feat/wp-05-epsilon/overview.md" || { why "executing wp-05-epsilon (unrelated slice) changed"; rc=1; }
  [[ "$(jq -c '.superseded' <<<"$out" 2>/dev/null)" == '["wp-01-alpha"]' ]] || { why "first run: report .superseded is not [wp-01-alpha]"; rc=1; }
  [[ "$(jq -c '.reharden' <<<"$out" 2>/dev/null)" == '["wp-02-beta"]' ]] || { why "first run: report .reharden is not [wp-02-beta]"; rc=1; }
  [[ "$(jq -r '.other_affected | index("wp-04-delta") != null' <<<"$out" 2>/dev/null)" == true ]] || { why "first run: report .other_affected does not name wp-04-delta"; rc=1; }
  m1="$(manifest "$r")"
  [[ "$m0" != "$m1" ]] || { why "first run wrote nothing"; rc=1; }
  bash "$sut" "$r/feat" "$r/feat/$PROP_REL" >/dev/null 2>&1 || { why "rerun exited non-zero (refused, not a no-op)"; rc=1; }
  m2="$(manifest "$r")"
  [[ "$m1" == "$m2" ]] || { why "rerun changed files (not idempotent)"; rc=1; }

  # Status flip: wp-02-beta verified against the revised spec, wp-04-delta
  # newly ready. A third run on the applied state must touch neither.
  sed -i 's/^status: ready$/status: verified/' "$r/feat/wp-02-beta/overview.md"
  sed -i 's/^status: spec$/status: ready/' "$r/feat/wp-04-delta/overview.md"
  mf="$(manifest "$r")"
  bash "$sut" "$r/feat" "$r/feat/$PROP_REL" >/dev/null 2>&1 || { why "third run on the applied state exited non-zero"; rc=1; }
  [[ "$(manifest "$r")" == "$mf" ]] || { why "third run on the applied state changed files (not a no-op after the status flip)"; rc=1; }

  # Second proposal: re-supersede the C2 verified WP.
  bash "$sut" "$r/feat" "$r/feat/$PROP2_REL" >/dev/null 2>&1 || { why "second-proposal run exited non-zero"; rc=1; }
  grep -qx "superseded_by: \"$PROP2_REL\"" "$wp1" || { why "second-proposal run: superseded_by: is not the second proposal ($(grep '^superseded_by:' "$wp1"))"; rc=1; }
  n="$(grep -c '^## Supersession' "$wp1")"
  [[ "$n" -eq 1 ]] || { why "second-proposal run: ## Supersession headings = $n, expected 1"; rc=1; }
  n="$(grep -c '^- date=' "$wp1")"
  [[ "$n" -eq 2 ]] || { why "second-proposal run: Supersession notes = $n, expected 2"; rc=1; }
  grep -q "^- date=$RAT_DATE respec=$PROP_REL " "$wp1" && grep -q "^- date=$RAT2_DATE respec=$PROP2_REL " "$wp1" \
    || { why "second-proposal run: notes are not one per proposal, each dated with its RATIFIED date="; rc=1; }

  p="$(fresh partial)"
  bash "$sut" "$p/feat" "$p/feat/$PROP_REL" >/dev/null 2>&1 || { why "partial-apply run exited non-zero"; rc=1; }
  mp="$(manifest "$p")"
  [[ "$mp" == "$m1" ]] || { why "partial apply did not converge to the first run's tree"; rc=1; }

  # Block-list contract_slice copy.
  bl="$(fresh blocklist)"
  out="$(bash "$sut" "$bl/feat" "$bl/feat/$PROP_REL" 2>/dev/null)" || { why "block-list run exited non-zero"; rc=1; }
  [[ "$(jq -c '.superseded' <<<"$out" 2>/dev/null)" == '["wp-01-alpha"]' ]] || { why "block-list run: report .superseded is not [wp-01-alpha]"; rc=1; }
  [[ "$(jq -c '.reharden' <<<"$out" 2>/dev/null)" == '["wp-02-beta"]' ]] || { why "block-list run: report .reharden is not [wp-02-beta]"; rc=1; }
  has "$bl/feat/wp-01-alpha/overview.md" 'superseded_by:' || { why "block-list run: wp-01-alpha lacks superseded_by:"; rc=1; }
  [[ "$(grep -c '^## Supersession' "$bl/feat/wp-01-alpha/overview.md")" -eq 1 ]] || { why "block-list run: wp-01-alpha does not carry exactly one ## Supersession"; rc=1; }
  [[ -f "$bl/feat/wp-02-beta/reharden/$RAT_DATE-respec-tighten-c2.md" ]] || { why "block-list run: missing wp-02-beta reharden file"; rc=1; }
  [[ "$(manifest "$bl" | grep -v -e ' ./feat/wp-01-alpha/overview.md$' -e ' ./feat/wp-02-beta/overview.md$')" \
     == "$(grep -v -e ' ./feat/wp-01-alpha/overview.md$' -e ' ./feat/wp-02-beta/overview.md$' <<<"$m1")" ]] \
    || { why "block-list run: tree differs from the first run's result beyond the two block-list overviews"; rc=1; }
  return "$rc"
}

# ── b4 ───────────────────────────────────────────────────────────────────────
feature_rows() {  # prints "from to rr hg route" per Feature edges row (route "-" when the cell is missing)
  awk -F'|' '
    /^## /{ inside = ($0 ~ /^## Feature edges[[:space:]]*$/); next }
    inside && /^\|/ {
      for (i = 2; i <= 6; i++) { gsub(/^[ \t]+|[ \t]+$/, "", $i) }
      if ($2 == "from" || $2 ~ /^-+$/) next
      print $2, $3, $4, $5, (NF >= 7 && $6 != "" ? $6 : "-")
    }' "$1"
}
policy_bullet() {  # $1 file, $2 bullet label -> the Feature policy bullet text
  awk -v lab="$2" '
    /^## /{ inside = ($0 ~ /^## Feature policy/); next }
    inside && /^- \*\*/ { grab = (index($0, "- **" lab "**") == 1) }
    inside && grab { print }' "$1"
}
b4_case() {
  local sm="$1" rc=0 rows out_draft out_spec scoped gated e hum fwd
  rows="$(feature_rows "$sm")"
  out_draft="$(awk '$1=="draft" && $5=="any"{print $2}' <<<"$rows" | sort | tr '\n' ' ')"
  out_spec="$(awk '$1=="spec" && $5=="any"{print $2}' <<<"$rows" | sort | tr '\n' ' ')"
  [[ "$out_draft" == "spec " ]] || { why "draft out-edges (route any) are {$out_draft}, expected {spec}"; rc=1; }
  [[ "$out_spec" == "draft ready " ]] || { why "spec out-edges (route any) are {$out_spec}, expected {draft ready}"; rc=1; }
  scoped="$(awk '$5!="any"{print $1"->"$2":"$5}' <<<"$rows" | sort | tr '\n' ' ')"
  [[ "$scoped" == "draft->completed:fast " ]] || { why "route-scoped rows are {$scoped}, expected {draft->completed:fast}"; rc=1; }
  has "$sm" '`draft -> completed` is legal only for a `route: fast` feature with no `spec.md`' \
    || { why "policy prose lacks F1 (the route: fast draft -> completed exit)"; rc=1; }
  has "$sm" 'for a feature that is not `route: fast`, every path from `draft` or `spec` onward passes `spec -> ready`' \
    || { why "policy prose lacks F2 (the qualified path claim)"; rc=1; }
  has "$sm" 'so every path from `draft` or `spec` onward passes' \
    && { why "policy prose still carries F3 (the unqualified path claim)"; rc=1; }
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
pkg_mirror() {  # $1 script basename, $2 SUT copied over it, [$3 table over references/state-machine.md]
  local c
  c="$(mktemp -d "$T/pkg.XXXXXX")"
  cp -a "$PKG/scripts" "$PKG/references" "$c/"
  cp "$2" "$c/scripts/$1"
  [[ -z "${3:-}" ]] || cp "$3" "$c/references/state-machine.md"
  printf '%s\n' "$c"
}
smoke_case() {  # run a smoke SUT inside a throwaway copy of the package scripts
  local c
  c="$(pkg_mirror goalforge-smoke.sh "$1")"
  bash "$c/scripts/goalforge-smoke.sh" --throwaway >"$T/smoke.out" 2>&1 || { why "smoke --throwaway exited non-zero: $(tail -1 "$T/smoke.out")"; return 1; }
}
route_leg() {  # $1 mirror, $2 leg, $3 route: line ('' = none), $4 spec.md? (0|1), $5 take|refuse, [$6 stderr substring]
  local f lrc st
  f="$(mktemp -d "$T/plans.XXXXXX")/feat-$2"
  mkdir -p "$f"
  { printf -- '---\nname: feat-%s\ntitle: route leg fixture\nstatus: draft\n' "$2"
    [[ -z "$3" ]] || printf '%s\n' "$3"
    printf 'feature: feat-%s\nwork_packages: []\n---\n\n# route leg\n' "$2"
  } >"$f/overview.md"
  [[ "$4" == 0 ]] || printf -- '---\nname: feat-%s-spec\n---\n' "$2" >"$f/spec.md"
  bash "$1/scripts/goalforge-transition.sh" "$f" completed >"$T/leg.out" 2>&1; lrc=$?
  st="$(grep -m1 '^status:' "$f/overview.md")"
  if [[ "$5" == take ]]; then
    [[ "$lrc" -eq 0 && "$st" == "status: completed" ]] && return 0
    why "leg $2: expected draft -> completed taken, got rc=$lrc $st"; return 1
  fi
  [[ "$lrc" -ne 0 && "$st" == "status: draft" ]] || { why "leg $2: expected refusal with status: draft unchanged, got rc=$lrc $st"; return 1; }
  [[ -z "${6:-}" ]] || grep -qF -- "$6" "$T/leg.out" || { why "leg $2: refusal does not say '$6': $(tail -1 "$T/leg.out")"; return 1; }
}
transition_case() {  # $1 transition SUT: the six route legs over the live table
  local c rc=0
  c="$(pkg_mirror goalforge-transition.sh "$1")"
  route_leg "$c" standard       "route: standard"          0 refuse || rc=1
  route_leg "$c" no-route       ""                         0 refuse || rc=1
  route_leg "$c" fast-with-spec "route: fast"              1 refuse || rc=1
  route_leg "$c" fast           "route: fast"              0 take   || rc=1
  route_leg "$c" fast-comment   "route: fast  # re-routed" 0 take   || rc=1
  route_leg "$c" fast-quoted    "route: 'fast'"            0 take   || rc=1
  return "$rc"
}
fast_leg_case() {  # $1 transition SUT: the bare route: fast leg alone
  route_leg "$(pkg_mirror goalforge-transition.sh "$1")" fast "route: fast" 0 take
}
fourcell_case() {  # $1 transition SUT over the mirror table whose draft -> completed row has four cells
  route_leg "$(pkg_mirror goalforge-transition.sh "$1" "$FX/four-cell-state-machine.md")" \
    four-cell-standard "route: standard" 0 refuse "edge_lookup error"
}
selftest_case() {  # $1 transition SUT: --self-test rc 0 inside a mirror
  local c
  c="$(pkg_mirror goalforge-transition.sh "$1")"
  bash "$c/scripts/goalforge-transition.sh" --self-test >"$T/selftest.out" 2>&1 || { why "--self-test exited non-zero: $(tail -1 "$T/selftest.out")"; return 1; }
}

# ── b5 ───────────────────────────────────────────────────────────────────────
b5_case() {  # $1 apply SUT, $2 variant name (a variant adding wp-06-zeta must name it on stderr)
  local sut="$1" v="$FX/variants/$2" r m0 m1 rc=0 f
  r="$(fresh tree)"
  [[ -d "$v" ]] || { why "no variant $2"; return 1; }
  (cd "$v" && find . -type f ! -name REMOVE -print0) | while IFS= read -r -d '' f; do mkdir -p "$(dirname "$r/feat/$f")"; cp "$v/$f" "$r/feat/$f"; done
  if [[ -f "$v/REMOVE" ]]; then while IFS= read -r f; do rm -f "$r/feat/$f"; done <"$v/REMOVE"; fi
  m0="$(manifest "$r")"
  if bash "$sut" "$r/feat" "$r/feat/$PROP_REL" >/dev/null 2>"$T/b5.err"; then why "$2: apply exited 0"; rc=1; fi
  m1="$(manifest "$r")"
  [[ "$m0" == "$m1" ]] || { why "$2: tree changed"; rc=1; }
  grep -qF '"to": "ready"' "$r/feat/.sdd-transitions.jsonl" && { why "$2: a to=ready row was written"; rc=1; }
  if [[ -f "$v/wp-06-zeta/overview.md" ]] && ! grep -qF 'wp-06-zeta' "$T/b5.err"; then
    why "$2: the refusal does not name wp-06-zeta on stderr"; rc=1
  fi
  if [[ "$2" == *-hardened ]] && ! grep -qF 'goalforge-transition.sh wp-06-zeta spec ' "$T/b5.err"; then
    why "$2: the refusal does not walk the hardened WP back to spec"; rc=1
  fi
  return "$rc"
}
VARIANTS=(01-no-ratified 02-missing-date 03-missing-diff-sha 04-missing-base-sha 05-sha-mismatch 06-no-changelog-row 07-stale-diff 08-base-edited)
INFLIGHT=(09-inflight-hardened 10-inflight-executing 11-inflight-implemented 12-inflight-dropped-key 13-inflight-block-zero-indent 14-inflight-renumber 16-inflight-status-comment)
VARIANTS+=("${INFLIGHT[@]}" 15-unparseable-slice)

# M1-r2: two applies of two ratified proposals on one base, released at once
# from a lock the test holds, serialize: exactly one writes, the other refuses
# on the base-state check. Three trials; any lost revision is red.
race_trial() {  # $1 apply SUT
  local sut="$1" r a b ra rb ino i win lose n
  r="$(fresh tree)"; a="$r/feat/$PROP_REL"; b="$r/feat/respec/2026-09-01-race-b"
  cp -a "$a" "$b"
  printf '\nrace b\n' >>"$b/proposed-spec.md"
  sed -i "s/ sha256=[0-9a-f]* / sha256=$(sha256sum <"$b/proposed-spec.md" | cut -d' ' -f1) /" "$b/RATIFIED"
  exec 8>"$r/feat/.sdd-transitions.lock"; flock 8
  bash "$sut" "$r/feat" "$a" >/dev/null 2>"$T/race-a.err" 8>&- & ra=$!
  bash "$sut" "$r/feat" "$b" >/dev/null 2>"$T/race-b.err" 8>&- & rb=$!
  ino="$(stat -c %i "$r/feat/.sdd-transitions.lock")"
  for i in $(seq 100); do  # both applies queued on the lock the test holds
    [[ "$(grep -c -- "-> FLOCK .*:$ino " /proc/locks 2>/dev/null)" -ge 2 ]] && break
    sleep 0.05
  done
  flock -u 8; exec 8>&-
  wait "$ra"; ra=$?; wait "$rb"; rb=$?
  if [[ "$ra" -eq 0 && "$rb" -ne 0 ]]; then win="$a"; lose="$T/race-b.err"
  elif [[ "$rb" -eq 0 && "$ra" -ne 0 ]]; then win="$b"; lose="$T/race-a.err"
  else why "race: not exactly one apply exited 0 (a rc=$ra, b rc=$rb): a lost revision"; return 1; fi
  grep -qF 'neither the ratified base' "$lose" || { why "race: the losing apply did not refuse on the base state: $(tail -1 "$lose")"; return 1; }
  cmp -s "$r/feat/spec.md" "$win/proposed-spec.md" || { why "race: spec.md is not the winning proposal"; return 1; }
  n="$(find "$r/feat/wp-02-beta/reharden" -name '*-respec-*' | wc -l)"
  [[ "$n" -eq 1 ]] || { why "race: wp-02-beta carries $n respec reharden files, expected 1 (one applied revision)"; return 1; }
}
race_case() {  # $1 apply SUT
  local i; for i in 1 2 3; do race_trial "$1" || return 1; done
}

# M1-l7: the apply records the WP's last -> ready ledger ts in its reharden file.
reharden_record_case() {  # $1 apply SUT
  local r ev
  r="$(fresh tree)"
  printf '%s\n' '{"ts": "2026-08-01T09:00:00Z", "wp": "wp-02-beta", "from": "hardened", "to": "ready"}' \
    '{"ts": "2026-08-02T09:00:00Z", "wp": "wp-02-beta", "from": "hardened", "to": "ready"}' \
    '{"ts": "2026-08-03T09:00:00Z", "wp": "wp-03-gamma", "from": "hardened", "to": "ready"}' \
    '{"ts": "2026-08-04T09:00:00Z", "wp": "wp-02-beta", "from": "ready", "to": "hardened"}' >>"$r/feat/.sdd-transitions.jsonl"
  bash "$1" "$r/feat" "$r/feat/$PROP_REL" >/dev/null 2>&1 || { why "record: apply exited non-zero"; return 1; }
  ev="$r/feat/wp-02-beta/reharden/$RAT_DATE-respec-tighten-c2.md"
  grep -qx 'since_ready_ts: 2026-08-02T09:00:00Z' "$ev" 2>/dev/null \
    || { why "record: reharden file does not record the last -> ready ts ($(grep '^since_ready_ts' "$ev" 2>/dev/null))"; return 1; }
}

# H1-r2 / M1-l7: a ready WP whose newest (by filename) reharden/*-respec-* file
# is not answered by a -> ready row after its since_ready_ts: does not move
# forward; mtime plays no part; a real re-harden recovers it.
gate_fx() {  # $1 ledger rows (one per line) -> prints a feature dir holding ready wp-01-a
  local f; f="$(mktemp -d "$T/plans.XXXXXX")/feat"
  mkdir -p "$f/wp-01-a/reharden"
  printf -- '---\nname: feat\ntitle: gate fixture\nstatus: active\nfeature: feat\nwork_packages: [wp-01-a]\n---\n' >"$f/overview.md"
  printf -- '---\nname: wp-01-a\ntitle: gate fixture\nstatus: ready\nplan: feat\n---\n' >"$f/wp-01-a/overview.md"
  printf '%s\n' "$1" >"$f/.sdd-transitions.jsonl"
  printf '%s\n' "$f"
}
gate_ev() {  # $1 file, [$2 since_ready_ts value; omitted = no key]
  { printf -- '---\nkind: execution-learning\nlocator: respec/x/diff.json\nsummary: respec changed C2\n'
    [[ $# -lt 2 ]] || printf 'since_ready_ts: %s\n' "$2"
    printf -- '---\n'; } >"$1"
}
gate_refuses() {  # $1 transition, $2 wp dir, $3 to, $4 file the refusal must name, $5 label
  bash "$1" "$2" "$3" >"$T/gate.out" 2>&1 && { why "gate $5: ready -> $3 not refused"; return 1; }
  grep -qx 'status: ready' "$2/overview.md" || { why "gate $5: status moved off ready"; return 1; }
  grep -qF "$4" "$T/gate.out" && grep -qF 're-harden' "$T/gate.out" \
    || { why "gate $5: refusal does not name $4 and the re-harden step: $(tail -1 "$T/gate.out")"; return 1; }
}
reharden_gate_case() {  # $1 transition SUT
  local c tr f ev x y rc=0
  c="$(pkg_mirror goalforge-transition.sh "$1")"; tr="$c/scripts/goalforge-transition.sh"
  # recorded ts == last -> ready ts (not strictly greater); an old mtime is irrelevant
  f="$(gate_fx '{"ts": "2026-09-01T10:00:00Z", "wp": "wp-01-a", "from": "hardened", "to": "ready"}')"
  ev="$f/wp-01-a/reharden/2026-09-02-respec-x.md"
  gate_ev "$ev" 2026-09-01T10:00:00Z; touch -d '2026-08-01' "$ev"
  gate_refuses "$tr" "$f/wp-01-a" executing "reharden/2026-09-02-respec-x.md" executing || rc=1
  gate_refuses "$tr" "$f/wp-01-a" implemented "reharden/2026-09-02-respec-x.md" implemented || rc=1
  gate_refuses "$tr" "$f/wp-01-a" verified "reharden/2026-09-02-respec-x.md" verified || rc=1
  # recovery through a real re-harden: ready -> hardened -> ready writes a newer row
  bash "$tr" "$f/wp-01-a" hardened --mode evidence --evidence "$ev" --reason "respec" >"$T/gate.out" 2>&1 \
    && bash "$tr" "$f/wp-01-a" ready >>"$T/gate.out" 2>&1 \
    && bash "$tr" "$f/wp-01-a" executing >>"$T/gate.out" 2>&1 \
    && grep -qx 'status: executing' "$f/wp-01-a/overview.md" \
    || { why "gate recovery: re-harden then ready did not let ready -> executing pass: $(tail -1 "$T/gate.out")"; rc=1; }
  # the newest file by name decides, not the newest by mtime
  f="$(gate_fx "$(printf '%s\n' '{"ts": "2026-09-01T10:00:00Z", "wp": "wp-01-a", "from": "hardened", "to": "ready"}' \
                               '{"ts": "2026-09-03T10:00:00Z", "wp": "wp-01-a", "from": "hardened", "to": "ready"}')")"
  x="$f/wp-01-a/reharden/2026-09-02-respec-x.md"; y="$f/wp-01-a/reharden/2026-09-04-respec-y.md"
  gate_ev "$x" 2026-09-01T10:00:00Z; gate_ev "$y" 2026-09-03T10:00:00Z
  touch -d '2026-08-01' "$y"
  gate_refuses "$tr" "$f/wp-01-a" executing "reharden/2026-09-04-respec-y.md" "two files" || rc=1
  # a file with no recorded value refuses, fail-closed, naming the file
  f="$(gate_fx '{"ts": "2026-09-01T10:00:00Z", "wp": "wp-01-a", "from": "hardened", "to": "ready"}')"
  gate_ev "$f/wp-01-a/reharden/2026-09-02-respec-z.md"
  gate_refuses "$tr" "$f/wp-01-a" executing "reharden/2026-09-02-respec-z.md" "no value" || rc=1
  grep -qF 'since_ready_ts' "$T/gate.out" || { why "gate no value: refusal does not name since_ready_ts: $(tail -1 "$T/gate.out")"; rc=1; }
  return "$rc"
}

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
b3_case "$RESPEC_APPLY" && ok "b3 apply effects, no status write, rerun + post-flip no-op, re-supersede, partial resumed, block-list slice" || bad "b3 apply effects"
b4_case "$STATE_MACHINE_MD" && ok "b4 feature edge table (route column) + policy prose (F1-F3)" || bad "b4 feature edge table + policy prose"
smoke_case "$SMOKE" && ok "b4 goalforge-smoke.sh --throwaway walks draft -> spec -> ready -> completed" || bad "b4 smoke walk"
transition_case "$RESPEC_TRANSITION_SUT" && ok "b4 transition.sh route legs: draft -> completed only for route: fast with no spec.md" || bad "b4 transition.sh route legs"
fourcell_case "$RESPEC_TRANSITION_SUT" && ok "b4 transition.sh refuses a four-cell Feature row as an edge_lookup error" || bad "b4 four-cell Feature row"
selftest_case "$RESPEC_TRANSITION_SUT" && ok "b4 goalforge-transition.sh --self-test rc 0" || bad "b4 transition --self-test"
for v in "${VARIANTS[@]}"; do
  b5_case "$RESPEC_APPLY" "$v" && ok "b5 apply refuses $v, tree byte-identical" || bad "b5 apply refuses $v"
done
race_case "$RESPEC_APPLY" && ok "M1-r2 two applies on one base released together: exactly one writes, the other refuses (3 trials)" || bad "M1-r2 apply race"
reharden_record_case "$RESPEC_APPLY" && ok "M1-l7 apply records the WP's last -> ready ts as since_ready_ts:" || bad "M1-l7 since_ready_ts record"
reharden_gate_case "$RESPEC_TRANSITION_SUT" && ok "H1-r2 transition refuses ready -> executing|implemented|verified until a -> ready row follows the recorded ts; newest file by name; re-harden recovers" || bad "H1-r2 reharden gate"
b6_case "$RESPEC_APPLY" && ok "b6 ratified apply writes the proposal and one outcome row" || bad "b6 ratified apply"
if bash "$PKG/spec/evals/run.sh" >"$T/spec-evals.out" 2>&1; then ok "spec/evals/run.sh rc 0"; else bad "spec/evals/run.sh"; sed 's/^/      /' "$T/spec-evals.out"; fi

# ── known-bad self-check: each copy must turn its case red ───────────────────
red() {  # $1 label, [--why <substring>], rest = the case command; RESPEC_TEST_VERBOSE=1 shows why
  # With --why, the known-bad counts red only when a failing check's message
  # carries the substring, so it is shown red by its own target.
  local label="$1" want="" out; shift
  if [[ "${1:-}" == --why ]]; then want="$2"; shift 2; fi
  if out="$("$@" 2>&1)"; then
    bad "known-bad stays green: $label"
  elif [[ -n "$want" ]] && ! awk -v w="$want" 'index($0, "      - ") == 1 && index($0, w) { f = 1 } END { exit !f }' <<<"$out"; then
    bad "known-bad red, but not on its target '$want': $label"; printf '%s\n' "$out" | sed 's/^/    /'
  else
    ok "known-bad red: $label${want:+ (why: $want)}"
  fi
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
red b3g-apply-no-t9-skip --why "third run on the applied state" b3_case "$KB/b3g-apply-no-t9-skip.sh"
red b3g2-apply-reharden-in-applied --why "third run on the applied state" b3_case "$KB/b3g2-apply-reharden-in-applied.sh"
red b3h-apply-no-by-rewrite --why "superseded_by: is not the second proposal" b3_case "$KB/b3h-apply-no-by-rewrite.sh"
red b3i-apply-second-h2 --why "## Supersession headings" b3_case "$KB/b3i-apply-second-h2.sh"
red b3j-apply-flow-only --why "block-list run: report .superseded" b3_case "$KB/b3j-apply-flow-only.sh"
for k in "$KB"/b4[a-e]-*.md; do red "$(basename "$k" .md)" b4_case "$k"; done
red b4f-smoke-draft-completed smoke_case "$KB/b4f-smoke-draft-completed.sh"
red b4g-transition-ignore-route --why "leg standard:" transition_case "$KB/b4g-transition-ignore-route.sh"
red b4h-transition-missing-route-fast --why "leg no-route:" transition_case "$KB/b4h-transition-missing-route-fast.sh"
red b4i-transition-four-cell-any --why "leg four-cell-standard:" fourcell_case "$KB/b4i-transition-four-cell-any.sh"
red b4j-transition-no-spec-check --why "leg fast-with-spec:" transition_case "$KB/b4j-transition-no-spec-check.sh"
red b4k-transition-raw-route --why "leg fast-comment:" transition_case "$KB/b4k-transition-raw-route.sh"
for k in b4g-transition-ignore-route b4h-transition-missing-route-fast b4j-transition-no-spec-check b4k-transition-raw-route; do
  fast_leg_case "$KB/$k.sh" >/dev/null && ok "known-bad keeps the bare route: fast leg green: $k" || bad "known-bad breaks the bare route: fast leg: $k"
done
red b4l-sm-unqualified-path-claim --why "F3" b4_case "$KB/b4l-sm-unqualified-path-claim.md"
KB5=(b5a-apply-absent-pass b5b-apply-default-date b5c-apply-default-diff-sha b5d-apply-default-base-sha
     b5e-apply-no-sha-bind b5f-apply-no-changelog-check b5g-apply-no-diff-bind b5h-apply-any-base)
for i in "${!KB5[@]}"; do red "${KB5[$i]} on ${VARIANTS[$i]}" b5_case "$KB/${KB5[$i]}.sh" "${VARIANTS[$i]}"; done
for v in "${INFLIGHT[@]}"; do
  red "b5i-apply-no-inflight on $v" --why "$v: apply exited 0" b5_case "$KB/b5i-apply-no-inflight.sh" "$v"
done
for v in 09-inflight-hardened 10-inflight-executing 11-inflight-implemented; do
  red "b5i2-apply-inflight-in-loop on $v" --why "$v: tree changed" b5_case "$KB/b5i2-apply-inflight-in-loop.sh" "$v"
done
red "b5j-apply-slice-skip on 15-unparseable-slice" --why "15-unparseable-slice: apply exited 0" b5_case "$KB/b5j-apply-slice-skip.sh" 15-unparseable-slice
red "b5k-apply-inflight-any-slice on b3" --why "first run exited non-zero" b3_case "$KB/b5k-apply-inflight-any-slice.sh"
red "b5k-apply-inflight-any-slice on b6" --why "ratified apply exited non-zero" b6_case "$KB/b5k-apply-inflight-any-slice.sh"
red "b5l-apply-no-ambiguous-dropped on 14-inflight-renumber" --why "14-inflight-renumber: apply exited 0" b5_case "$KB/b5l-apply-no-ambiguous-dropped.sh" 14-inflight-renumber
# Patch-sized mutants of the live files, made at test time (no frozen copies).
sed '/^current = sha(SPEC)$/d; /^lock_fd = os.open/i current = sha(SPEC)' "$RESPEC_APPLY" >"$T/m-lock-late.sh"
red m-apply-sha-before-lock --why "race:" race_case "$T/m-lock-late.sh"
sed 's/fcntl\.flock(lock_fd, fcntl\.LOCK_EX)/fcntl.flock(lock_fd, fcntl.LOCK_SH)/' "$RESPEC_APPLY" >"$T/m-lock-sh.sh"
red m-apply-lock-shared --why "race:" race_case "$T/m-lock-sh.sh"
sed '/^fcntl\.flock(lock_fd, fcntl\.LOCK_EX)$/a fcntl.flock(lock_fd, fcntl.LOCK_UN)' "$RESPEC_APPLY" >"$T/m-lock-early-unlock.sh"
red m-apply-unlock-after-lock-ex --why "race:" race_case "$T/m-lock-early-unlock.sh"
sed 's/\.split("#", 1)\[0\]//' "$RESPEC_APPLY" >"$T/m-raw-status.sh"
red m-apply-raw-status --why "16-inflight-status-comment: apply exited 0" b5_case "$T/m-raw-status.sh" 16-inflight-status-comment
sed 's/back = "spec" if status == "hardened" else "ready"/back = "ready"/' "$RESPEC_APPLY" >"$T/m-hardened-ready.sh"
red m-apply-hardened-to-ready --why "back to spec" b5_case "$T/m-hardened-ready.sh" 09-inflight-hardened
sed 's/if \[\[ -n "\$STALE_EV" \]\]; then/if false; then/' "$RESPEC_TRANSITION_SUT" >"$T/m-no-gate.sh"
red m-transition-no-reharden-gate --why "not refused" reharden_gate_case "$T/m-no-gate.sh"
sed 's/if t is not None and (since is None or t > since):/if t is not None:/' "$RESPEC_TRANSITION_SUT" >"$T/m-gate-ignores-recorded.sh"
red m-transition-gate-ignores-recorded-ts --why "not refused" reharden_gate_case "$T/m-gate-ignores-recorded.sh"
red b6-apply-noop b6_case "$KB/b6-apply-noop.sh"

echo ""
echo "Results: $PASS passed, $FAIL failed"
[[ "$FAIL" -eq 0 ]]
