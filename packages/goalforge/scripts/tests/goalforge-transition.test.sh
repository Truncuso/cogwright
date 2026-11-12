#!/usr/bin/env bash
# goalforge-transition.test.sh — ticket-74 sabotage pair for the generic
# edge-legality gate in goalforge-transition.sh (state-machine.md `## Edges`
# lookup). Complements goalforge-transition-evidence.test.sh, which covers
# only the evidence-gated ready<->hardened revert edge, not a plain illegal
# `from -> to` pair.
#
#   known-bad  : an illegal transition (target not in the Edges table for the
#                current status) is rejected: non-zero exit, status untouched.
#   known-good : the matching legal forward edge succeeds: exit 0, status
#                updated on disk, a ledger row written.
set -uo pipefail

SD="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TRANSITION="$SD/../goalforge-transition.sh"
PASS=0; FAIL=0

ok()  { echo "  PASS: $1"; PASS=$((PASS+1)); }
bad() { echo "  FAIL: $1"; FAIL=$((FAIL+1)); }

status_of() { grep -m1 '^status:' "$1/overview.md" | sed 's/^status:[[:space:]]*//'; }

mkwp() { # $1=feat_dir $2=wp_name $3=status -> prints the WP dir path
    local feat="$1" wp="$1/$2" status="$3"
    local fname; fname="$(basename "$feat")"
    mkdir -p "$wp"
    cat > "$feat/overview.md" <<EOF
---
name: $fname
title: transition sabotage-pair fixture
status: ready
created: 2026-09-09
feature: $fname
work_packages: [$2]
---

# fixture feature
EOF
    cat > "$wp/overview.md" <<EOF
---
name: $2
title: transition sabotage-pair WP
status: $status
stage_updated: 2026-09-09
severity: LOW
parallel: false
depends_on: []
plan: $fname
---

# fixture wp
EOF
    printf '%s' "$wp"
}

T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT

# ── known-bad: illegal transition (draft is not a legal target from spec) ────
WPB="$(mkwp "$T/bad/feat-bad" wp-01-bad spec)"
set +e
OUT="$(bash "$TRANSITION" "$WPB" not-a-real-status --reason "sabotage" 2>&1)"
RC=$?
set -e
if [[ "$RC" -ne 0 ]] && echo "$OUT" | grep -qi 'illegal transition'; then
    ok "known-bad: illegal transition rejected (non-zero exit)"
else
    bad "known-bad: illegal transition rejected (non-zero exit) (rc=$RC)"
    echo "$OUT" | sed 's/^/        /'
fi
if [[ "$(status_of "$WPB")" == "spec" ]]; then
    ok "known-bad: status left untouched on illegal transition"
else
    bad "known-bad: status left untouched on illegal transition (got $(status_of "$WPB"))"
fi

# ── known-good: legal forward edge spec -> hardened ───────────────────────────
WPG="$(mkwp "$T/good/feat-good" wp-01-good spec)"
bash "$TRANSITION" "$WPG" hardened --reason "sabotage-pair legal edge" >/dev/null 2>&1
RC=$?
if [[ "$RC" -eq 0 ]]; then
    ok "known-good: legal forward edge exits 0"
else
    bad "known-good: legal forward edge exits 0 (rc=$RC)"
fi
if [[ "$(status_of "$WPG")" == "hardened" ]]; then
    ok "known-good: status updated on disk"
else
    bad "known-good: status updated on disk (got $(status_of "$WPG"))"
fi
LEDGER="$T/good/feat-good/.sdd-transitions.jsonl"
if [[ -f "$LEDGER" ]] && grep -q '"to": "hardened"' "$LEDGER"; then
    ok "known-good: ledger row written"
else
    bad "known-good: ledger row written"
fi

# ── commit.linked carries the FULL 40-char sha (not the short form) ──────────
# Implementers emit commit.linked with the full sha; a short sha here makes the
# same commit appear twice to any consumer doing `sort -u` over linked shas.
WPC="$(mkwp "$T/sha/feat-sha" wp-01-sha spec)"
command git -C "$T/sha/feat-sha" init -q
command git -C "$T/sha/feat-sha" -c user.name=t -c user.email=t@example.invalid \
    commit -q --allow-empty -m "fixture"
FULL_SHA="$(command git -C "$T/sha/feat-sha" rev-parse HEAD)"
bash "$TRANSITION" "$WPC" hardened --reason "full-sha commit.linked" >/dev/null 2>&1
LINKED="$(grep '"type":"commit.linked"' "$T/sha/feat-sha/trace-events.jsonl" 2>/dev/null | tail -n1)"
LINKED_SHA="$(printf '%s' "$LINKED" | sed -n 's/.*"commit":"\([^"]*\)".*/\1/p')"
if [[ "$LINKED_SHA" =~ ^[0-9a-f]{40}$ && "$LINKED_SHA" == "$FULL_SHA" ]]; then
    ok "commit.linked: commit field is the full 40-char sha"
else
    bad "commit.linked: commit field is the full 40-char sha (got '$LINKED_SHA', want '$FULL_SHA')"
    echo "$LINKED" | sed 's/^/        /'
fi

# ══ Schema-6 gates: the human gate and the auto-advance predicate ═══════════
# Every case runs a transition SUT (env TRANSITION_SUT, default the shipped
# script) inside a throwaway package copy, so a sabotaged copy still finds its
# state-machine table and helper scripts. A failing check prints a `- <id>:`
# line; an arm runs a case on a one-edit mutant and asserts which ids go red.
set +e
PKG="$(cd "$SD/../.." && pwd)"
GOAL_HASH="$PKG/scripts/goalforge-goal-hash.sh"
TRANSITION_SUT="${TRANSITION_SUT:-$TRANSITION}"
OUT="$T/gate.err"
mkdir -p "$T/home"

why() { echo "      - $1"; }

mirror() {  # $1 transition SUT -> prints its path inside a fresh package copy
    local c; c="$(mktemp -d "$T/pkg.XXXXXX")"
    cp -a "$PKG/scripts" "$PKG/references" "$c/"
    cp "$1" "$c/scripts/goalforge-transition.sh"
    printf '%s\n' "$c/scripts/goalforge-transition.sh"
}
gfeat() {  # $1 schema_version ('' = no key), $2 status -> prints a new feature dir
    local f; f="$(mktemp -d "$T/plans.XXXXXX")/feat"; mkdir -p "$f"
    { printf -- '---\nname: feat\ntitle: gate fixture\nstatus: %s\ncreated: 2026-11-12\nfeature: feat\nwork_packages: [wp-01-a]\n' "$2"
      [[ -z "$1" ]] || printf 'schema_version: %s\n' "$1"
      printf -- '---\n\n# gate fixture\n'; } >"$f/overview.md"
    printf '%s\n' "$f"
}
gwp() {  # $1 feature dir, $2 status, $3 schema_version ('' = no key), rest = frontmatter lines -> prints the WP dir (goal hash recorded)
    local f="$1" st="$2" sv="$3" w l; shift 3; w="$f/wp-01-a"; mkdir -p "$w"
    { printf -- '---\nname: wp-01-a\ntitle: gate fixture\nstatus: %s\nplan: feat\n' "$st"
      [[ -z "$sv" ]] || printf 'schema_version: %s\n' "$sv"
      for l in "$@"; do printf '%s\n' "$l"; done
      printf 'goal:\n  outcome: "gate fixture"\n  verification:\n    strategy: deterministic\n    command: "true"\ngoal_approved_version: null\n---\n'; } >"$w/overview.md"
    bash "$GOAL_HASH" --record "$w" >/dev/null 2>&1
    printf '%s\n' "$w"
}
ledger_n() { if [[ -f "$1/.sdd-transitions.jsonl" ]]; then wc -l <"$1/.sdd-transitions.jsonl"; else echo 0; fi; }
st_of() { grep -m1 '^status:' "$1/overview.md" | sed 's/^status:[[:space:]]*//'; }
go() {  # $1 transition, $2 target dir, $3 to, rest = flags -> sets RC, N0 (ledger rows of $FD before), F0 (findings.md before), $OUT = stderr
    local tr="$1" d="$2" to="$3"; shift 3
    N0="$(ledger_n "$FD")"; F0=0; [[ -e "$d/findings.md" ]] && F0=1
    HOME="$T/home" bash "$tr" "$d" "$to" "$@" >"$T/gate.out" 2>"$OUT"; RC=$?
}
refused() {  # $1 id, $2 target dir, $3 status before, $4 rc, $5 stderr prefix, rest = needles (`!x` = must be absent)
    local id="$1" d="$2" st="$3" want="$4" pre="$5" x r=0; shift 5
    [[ "$RC" -eq "$want" ]] || { why "$id: exit $RC, expected $want: $(head -1 "$OUT")"; return 1; }
    [[ "$(head -1 "$OUT")" == "$pre"* ]] || { why "$id: stderr does not start '$pre': $(head -1 "$OUT")"; r=1; }
    for x in "$@"; do
        if [[ "$x" == '!'* ]]; then
            ! grep -qF -- "${x#!}" "$OUT" || { why "$id: stderr names '${x#!}': $(head -1 "$OUT")"; r=1; }
        else
            grep -qF -- "$x" "$OUT" || { why "$id: stderr does not name '$x': $(head -1 "$OUT")"; r=1; }
        fi
    done
    [[ "$(st_of "$d")" == "$st" ]] || { why "$id: status moved $st -> $(st_of "$d")"; r=1; }
    [[ "$(ledger_n "$FD")" -eq "$N0" ]] || { why "$id: a ledger row was written"; r=1; }
    [[ "$F0" == 1 || ! -e "$d/findings.md" ]] || { why "$id: findings.md was created"; r=1; }
    return "$r"
}
taken() {  # $1 id, $2 target dir, $3 to, [$4 mode $5 override: the ledger row's]
    local id="$1" d="$2" to="$3" row
    [[ "$RC" -eq 0 && "$(st_of "$d")" == "$to" ]] || { why "$id: -> $to refused (exit $RC): $(tail -1 "$OUT")"; return 1; }
    [[ -z "${4:-}" ]] && return 0
    row="$(tail -n1 "$FD/.sdd-transitions.jsonl")"
    [[ "$(jq -r '"\(.to) \(.mode) \(.override)"' <<<"$row")" == "$to $4 $5" ]] \
        || { why "$id: ledger row is not to=$to mode=$4 override=$5: $row"; return 1; }
}
arm() {  # $1 label, $2 mutant SUT, $3 case fn, $4 ids that must go red, $5 ids that must stay green
    local label="$1" sut="$2" fn="$3" id out r=0
    if cmp -s "$TRANSITION_SUT" "$sut"; then bad "arm $label: not a mutant (the edit matched nothing)"; return 0; fi
    out="$("$fn" "$(mirror "$sut")" 2>&1)"
    for id in $4; do grep -qF -- "- $id:" <<<"$out" || { echo "      $id stayed green"; r=1; }; done
    for id in $5; do ! grep -qF -- "- $id:" <<<"$out" || { echo "      $id went red"; r=1; }; done
    if [[ "$r" -eq 0 ]]; then ok "arm $label: red on [$4], green on [$5]"; else bad "arm $label"; fi
}

# b17: at schema 6 a human-gated edge (WP hardened -> ready, feature spec -> ready)
# and WP spec -> ready refuse without --mode human (exit 2, `human gate refused:`);
# --override neither lifts nor blocks it; schema 5 and unversioned are exempt.
hg_target() {  # $1 wp-hardened|wp-spec|feature, $2 schema_version -> sets FD TD ST
    case "$1" in
        feature) FD="$(gfeat "$2" spec)"; TD="$FD"; ST=spec ;;
        *)       ST="${1#wp-}"; FD="$(gfeat '' active)"; TD="$(gwp "$FD" "$ST" "$2" 'severity: HIGH')" ;;
    esac
}
b17_case() {  # $1 transition
    local tr="$1" rc=0 k c sv
    local -A FLAGS=([ii]="" [iii]="--mode auto --override" [iv]="--mode evidence" [v]="--mode auto")
    for k in wp-hardened wp-spec feature; do
        hg_target "$k" 6; go "$tr" "$TD" ready --mode human
        taken "b17(i)@$k" "$TD" ready human false || rc=1
        for c in ii iii iv v; do
            [[ "$c" == v && "$k" != feature ]] && continue
            hg_target "$k" 6; go "$tr" "$TD" ready ${FLAGS[$c]}  # word split on purpose
            refused "b17($c)@$k" "$TD" "$ST" 2 'human gate refused:' '--mode human' || rc=1
        done
        for sv in 5 ''; do
            hg_target "$k" "$sv"; go "$tr" "$TD" ready
            taken "b17(vi)@$k-schema${sv:-none}" "$TD" ready auto false || rc=1
        done
        hg_target "$k" 6; go "$tr" "$TD" ready --mode human --override
        taken "b17(vii)@$k" "$TD" ready human true || rc=1
    done
    # schema_version spellings: a present value is read like the respec gate reads it
    # (integers past 2^63 must not wrap; a quoted `#` is a value, not a comment;
    # only ASCII digits count as an integer)
    for sv in '6 # c' '6.0' 'six' '9223372036854775808' '18446744073709551616' '"#6"' '٦'; do
        hg_target wp-hardened "$sv"; go "$tr" "$TD" ready
        refused "b17(sv=$sv)" "$TD" hardened 2 'human gate refused:' '--mode human' || rc=1
    done
    for sv in '5 # c' '5 # older shape' '05'; do
        hg_target wp-hardened "$sv"; go "$tr" "$TD" ready
        taken "b17(sv=$sv)" "$TD" ready auto false || rc=1
    done
    return "$rc"
}

# b18: WP hardened|spec -> ready --mode auto passes only when the script finds
# the auto-advance predicate true; a refusal names the failing clause.
b18_case() {  # $1 transition
    local tr="$1" rc=0 st c
    for st in hardened spec; do
        for c in a b c d e f g h i; do
            FD="$(gfeat '' active)"
            case "$c" in
                a|i) TD="$(gwp "$FD" "$st" 6 'severity: LOW' 'human_required: null' 'task_type: code')" ;;
                b)   TD="$(gwp "$FD" "$st" 6 'severity: MEDIUM')" ;;
                c)   TD="$(gwp "$FD" "$st" 6 'severity: HIGH')" ;;
                d)   TD="$(gwp "$FD" "$st" 6 'severity: CRITICAL')" ;;
                e)   TD="$(gwp "$FD" "$st" 6)" ;;
                f)   TD="$(gwp "$FD" "$st" 6 'severity: low')" ;;
                g)   TD="$(gwp "$FD" "$st" 6 'severity: LOW' 'human_required: "schema change needs a DBA"')" ;;
                h)   TD="$(gwp "$FD" "$st" 6 'severity: LOW' 'task_type: migration')" ;;
            esac
            if [[ "$c" == i ]]; then go "$tr" "$TD" ready --mode auto --override; else go "$tr" "$TD" ready --mode auto; fi
            case "$c" in
                a|b)     taken "b18($c)@$st" "$TD" ready auto false ;;
                i)       taken "b18($c)@$st" "$TD" ready auto true ;;
                c|d|e|f) refused "b18($c)@$st" "$TD" "$st" 2 'human gate refused:' severity '!human_required' '!task_type' ;;
                g)       refused "b18($c)@$st" "$TD" "$st" 2 'human gate refused:' human_required '!severity' '!task_type' ;;
                h)       refused "b18($c)@$st" "$TD" "$st" 2 'human gate refused:' task_type '!severity' '!human_required' ;;
            esac || rc=1
        done
    done
    return "$rc"
}

b17_case "$(mirror "$TRANSITION_SUT")" && ok "b17 human gate: schema-6 WP hardened|spec -> ready and feature spec -> ready need --mode human (exit 2); --override inert; schema 5, unversioned and '5 # c' exempt" || bad "b17 human gate"
b18_case "$(mirror "$TRANSITION_SUT")" && ok "b18 auto-advance predicate: --mode auto passes only on severity LOW|MEDIUM, human_required unset, task_type not migration, at hardened and spec" || bad "b18 auto-advance predicate"
sed 's/PRED_FAIL="$(auto_predicate_failures "$OVERVIEW")"/PRED_FAIL=""/' "$TRANSITION_SUT" >"$T/m-pred-true.sh"
arm m-predicate-true "$T/m-pred-true.sh" b18_case \
    "b18(c)@hardened b18(d)@hardened b18(e)@hardened b18(f)@hardened b18(g)@hardened b18(h)@hardened b18(c)@spec b18(d)@spec b18(e)@spec b18(f)@spec b18(g)@spec b18(h)@spec" \
    "b18(a)@hardened b18(b)@hardened b18(i)@hardened b18(a)@spec b18(b)@spec b18(i)@spec"

# ══ Schema-6 ready-row gate (b23) ════════════════════════════════════════════
# A WP moves to executing|implemented|verified only with a -> ready ledger row
# later in the file than its latest move into spec or hardened. Fixtures P1-P8
# are built with real transitions of the SUT (P7's ledger is hand-written).
rr_line() { printf '%s refused: wp-01-a has no -> ready ledger row after its latest move into spec or hardened (harden it, then hardened -> ready --mode human)' "$1"; }
step() {  # $1 transition, $2 to, rest = flags: one fixture-building move of $TD
    local tr="$1" to="$2"; shift 2
    HOME="$T/home" bash "$tr" "$TD" "$to" "$@" >"$T/step.out" 2>&1 \
        || { why "fixture move -> $to failed: $(tail -1 "$T/step.out")"; return 1; }
}
pfx() {  # $1 transition, $2 P1..P8, [$3 schema_version, default 6] -> sets FD TD
    local tr="$1" p="$2" sv="${3-6}" sev='severity: HIGH'
    [[ "$p" == P6 ]] && sev='severity: MEDIUM'
    FD="$(gfeat '' active)"
    if [[ "$p" == P7 ]]; then
        TD="$(gwp "$FD" ready "$sv" "$sev")"
        printf '{"ts": "2026-11-04T10:00:00Z", "wp": "wp-01-a", "from": "spec", "to": "hardened"}\n{"ts": "2026-11-04T10:00:00Z", "wp": "wp-01-a", "from": "hardened", "to": "ready"}\n' >"$FD/.sdd-transitions.jsonl"
        return 0
    fi
    TD="$(gwp "$FD" spec "$sv" "$sev")"
    case "$p" in
        P1) ;;
        P2) step "$tr" hardened ;;
        P3) step "$tr" hardened && step "$tr" ready --mode human ;;
        P4) step "$tr" hardened && step "$tr" ready --mode human && step "$tr" spec --reason "walk back" ;;
        P5|P6) step "$tr" hardened && step "$tr" spec --reason "back to spec" ;;
        P8) step "$tr" hardened || return 1
            mkdir -p "$TD/reharden"
            printf -- '---\nkind: execution-learning\nlocator: respec/x/diff.json\nsummary: respec changed C2\nsince_ready_ts: none\n---\n' >"$TD/reharden/2026-11-04-respec-x.md" ;;
    esac
}
b23_case() {  # $1 transition
    local tr="$1" rc=0 sv
    pfx "$tr" P1 && go "$tr" "$TD" executing && refused "b23(i)" "$TD" spec 2 "$(rr_line executing)" || rc=1
    pfx "$tr" P1 && go "$tr" "$TD" implemented && refused "b23(ii)" "$TD" spec 2 "$(rr_line implemented)" || rc=1
    pfx "$tr" P2 && go "$tr" "$TD" implemented && refused "b23(iii)" "$TD" hardened 2 "$(rr_line implemented)" || rc=1
    pfx "$tr" P2 && go "$tr" "$TD" verified && refused "b23(iv)" "$TD" hardened 2 "$(rr_line verified)" || rc=1
    pfx "$tr" P4 && go "$tr" "$TD" executing && refused "b23(v)" "$TD" spec 2 "$(rr_line executing)" || rc=1
    pfx "$tr" P1 && go "$tr" "$TD" executing --override && refused "b23(vi)" "$TD" spec 2 "$(rr_line executing)" || rc=1
    pfx "$tr" P5 && go "$tr" "$TD" ready --mode auto && refused "b23(vii)" "$TD" spec 2 'human gate refused:' severity \
        && go "$tr" "$TD" executing && refused "b23(vii)" "$TD" spec 2 "$(rr_line executing)" || rc=1
    pfx "$tr" P6 && go "$tr" "$TD" ready --mode auto && taken "b23(viii)" "$TD" ready auto false \
        && go "$tr" "$TD" executing && taken "b23(viii)" "$TD" executing || rc=1
    pfx "$tr" P3 && go "$tr" "$TD" executing && taken "b23(ix)" "$TD" executing || rc=1
    pfx "$tr" P7 && go "$tr" "$TD" executing && taken "b23(x)" "$TD" executing || rc=1
    for sv in 5 ''; do
        pfx "$tr" P1 "$sv" && go "$tr" "$TD" executing && taken "b23(xi)" "$TD" executing || rc=1
    done
    pfx "$tr" P1 six && go "$tr" "$TD" executing && refused "b23(six)" "$TD" spec 2 "$(rr_line executing)" || rc=1
    pfx "$tr" P8 && go "$tr" "$TD" executing \
        && refused "b23(xii)" "$TD" hardened 1 'ERROR: hardened -> executing refused:' \
               'harden re-entry (references/respec.md §Re-entry)' '!its latest move into spec or hardened' || rc=1
    return "$rc"
}
b23_case "$(mirror "$TRANSITION_SUT")" && ok "b23 ready-row gate: schema-6 -> executing|implemented|verified needs a -> ready row after the latest move into spec or hardened (exit 2); ledger order, not ts; schema 5 and unversioned exempt; respec refusal first" || bad "b23 ready-row gate"
B23_IDS="b23(i) b23(ii) b23(iii) b23(iv) b23(v) b23(vi) b23(vii) b23(viii) b23(ix) b23(x) b23(xi) b23(six) b23(xii)"
b23_arm() {  # $1 label, $2 mutant SUT, $3 ids that must go red, [$4 ids left unasserted]
    local id green=""
    for id in $B23_IDS; do [[ " $3 ${4:-} " == *" $id "* ]] || green+="$id "; done
    arm "$1" "$2" b23_case "$3" "$green"
}
sed 's/if \[\[ -n "\$NO_READY_ROW" \]\]; then/if false; then/' "$TRANSITION_SUT" >"$T/m-rr-none.sh"
b23_arm m-ready-row-deleted "$T/m-rr-none.sh" "b23(i) b23(ii) b23(iii) b23(iv) b23(v) b23(vi) b23(vii) b23(six)"
sed 's/r\[0\] > pre\[0\]/r[1] > pre[1]/' "$TRANSITION_SUT" >"$T/m-rr-ts.sh"
# (viii) and (ix) build their ready row and the move before it with real
# transitions, often in the same second, so a ts compare may refuse them too.
b23_arm m-ready-row-ts-compare "$T/m-rr-ts.sh" "b23(x)" "b23(viii) b23(ix)"
sed 's/"\$KIND" == "wp" \&\& "\$RESPEC_STRICT" == 1 \&\& "\$TO" =~/"$KIND" == "wp" \&\& "$TO" =~/' "$TRANSITION_SUT" >"$T/m-rr-noschema.sh"
b23_arm m-ready-row-no-schema-guard "$T/m-rr-noschema.sh" "b23(xi)"
sed 's/PRED_FAIL="$(auto_predicate_failures "$OVERVIEW")"/PRED_FAIL="severity"/' "$TRANSITION_SUT" >"$T/m-pred-false.sh"
b23_arm m-predicate-false "$T/m-pred-false.sh" "b23(viii)"
python3 - "$TRANSITION_SUT" "$T/m-rr-first.sh" <<'PY'
# move the ready-row block (its marker comment up to the TS= line) above the respec gate
import sys
lines = open(sys.argv[1], encoding="utf-8").read().split("\n")
try:
    a = next(i for i, l in enumerate(lines) if l.startswith("    # ── ready-row gate"))
    b = next(i for i in range(a, len(lines)) if lines[i].startswith('    TS="$(date -u'))
    r = next(i for i, l in enumerate(lines) if l.startswith("    # ── respec reharden gate"))
    block = lines[a:b]
    rest = lines[:a] + lines[b:]
    lines = rest[:r] + block + rest[r:]
except StopIteration:
    pass
open(sys.argv[2], "w", encoding="utf-8").write("\n".join(lines))
PY
b23_arm m-ready-row-before-respec "$T/m-rr-first.sh" "b23(xii)"

# ══ b24: a feature made from the shipped template gets the human gate ═══════
TEMPLATE="$PKG/references/templates/feature-overview.md"
b24_case() {  # $1 transition
    local tr="$1" rc=0 root
    grep -q '^schema_version: 6' "$TEMPLATE" || { why "b24(template): feature-overview.md does not carry schema_version: 6"; rc=1; }
    root="$(mktemp -d "$T/plans.XXXXXX")"; FD="$root/tfeat"; mkdir -p "$FD"
    sed -e 's/<feature>/tfeat/g' -e 's/YYYY-MM-DD/2026-11-12/' "$TEMPLATE" >"$FD/overview.md"
    bash "$PKG/scripts/goalforge-validate.sh" --strict --quiet "$root" >"$T/b24.val" 2>&1 \
        || { why "b24(validate): validator --strict exit non-zero at draft: $(tail -1 "$T/b24.val")"; rc=1; }
    go "$tr" "$FD" spec && taken "b24(draft->spec)" "$FD" spec || rc=1
    go "$tr" "$FD" ready && refused "b24(a)" "$FD" spec 2 'human gate refused:' '--mode human' || rc=1
    go "$tr" "$FD" ready --mode human && taken "b24(b)" "$FD" ready human false || rc=1
    return "$rc"
}
b24_case "$(mirror "$TRANSITION_SUT")" && ok "b24 template feature: schema_version 6, validates --strict at draft, spec -> ready refused without --mode human, taken with it" || bad "b24 template feature"

echo
echo "goalforge-transition.test.sh: $PASS passed, $FAIL failed"
[[ "$FAIL" -eq 0 ]]
