#!/usr/bin/env bash
# goalforge-transition-evidence.test.sh — offline fixtures for the wp-02
# evidence-gated `ready → hardened` revert exception.
#
# Drives the REAL goalforge-transition.sh inside throwaway mktemp fixtures
# (never the live plans/ tree, never the network). Each fixture is a self-
# contained feature dir: a `ready`-status WP overview.md (goal-less, no
# schema_version marker — so the →ready hash gate's bounded exemption applies)
# plus a typed `reharden/<date>-<slug>.md` evidence file. Status is read back
# from the on-disk `status:` frontmatter, ledger/trace rows from the actual
# `.sdd-transitions.jsonl` / `trace-events.jsonl` files the script writes.
#
# Fixtures:
#   A legal      --mode evidence + a valid evidence file → exit 0,
#                `status: hardened` on disk, a `.sdd-transitions.jsonl` row.
#   B refusal    four sub-cases, each REFUSED (non-zero) with `status:` still
#                `ready`: (i) a bare --reason revert (no --mode evidence),
#                (ii) an absent evidence path (--evidence points at a missing
#                file), (iii) a malformed evidence file (missing `locator`),
#                (iv) UNTERMINATED frontmatter (no closing `---` fence) whose
#                required field survives only as a body prose line.
#   C trace      GOALFORGE_TRACE_EMIT at the real emitter → `reharden.proposed`
#                and `reharden.accepted` rows land in the temp trace-events.jsonl.
#   D regression one forward edge (spec → hardened) and one reverse edge
#                (executing → ready --reason) behave unchanged, exit 0.
set -uo pipefail

SD="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TRANSITION="$SD/../goalforge-transition.sh"
EMITTER="$SD/../goalforge-trace-emit"
PASS=0; FAIL=0

ok()   { echo "  PASS: $1"; PASS=$((PASS+1)); }
bad()  { echo "  FAIL: $1"; FAIL=$((FAIL+1)); }
assert() { if [[ "$2" -eq 0 ]]; then ok "$1"; else bad "$1"; fi; }

PARENT="$(mktemp -d)"
trap 'rm -rf "$PARENT"' EXIT

DATE="2026-07-24"

status_of() { grep -m1 '^status:' "$1/overview.md" | sed 's/^status:[[:space:]]*//'; }

# ── Fixture builder: a feature dir with one WP at a given status ──────────────
mkwp() { # $1=feat_dir $2=wp_name $3=status  → prints the WP dir path
    local feat="$1" wp="$1/$2" status="$3"
    local fname; fname="$(basename "$feat")"
    mkdir -p "$wp"
    cat > "$feat/overview.md" <<EOF
---
name: $fname
title: transition-evidence test feature
status: ready
created: $DATE
feature: $fname
work_packages: [$2]
---

# fixture feature
EOF
    cat > "$wp/overview.md" <<EOF
---
name: $2
title: transition-evidence test WP
status: $status
stage_updated: $DATE
severity: LOW
parallel: false
depends_on: []
plan: $fname
---

# fixture wp
EOF
    printf '%s' "$wp"
}

# ── Valid re-harden evidence file (kind/locator/summary all non-empty) ────────
write_evidence() { # $1=file $2=slug $3=feat $4=wp
    mkdir -p "$(dirname "$1")"
    cat > "$1" <<EOF
---
name: $2
title: "prototype surfaced a broken goal"
kind: prototype-findings
locator: plans/$3/$4/findings.md
summary: the ready goal no longer holds under the prototype
plan: $3
wp: $4
created: $DATE
---

## Evidence
prototype surfaced a broken goal
EOF
}

# ── Fixture A (legal): --mode evidence + valid file → hardened ────────────────
echo "=== Fixture A: legal evidence-gated ready→hardened revert ==="
WPA="$(mkwp "$PARENT/A/feat-a" wp-01-a ready)"
write_evidence "$WPA/reharden/$DATE-proto.md" "$DATE-proto" feat-a wp-01-a
OUT="$(bash "$TRANSITION" "$WPA" hardened --mode evidence \
        --evidence "$WPA/reharden/$DATE-proto.md" \
        --reason "re-harden: prototype invalidated the ready goal" 2>&1)"; RC=$?
[[ "$RC" -eq 0 ]]; assert "A: exit 0" $?
[[ "$(status_of "$WPA")" == "hardened" ]]; assert "A: status hardened on disk" $?
LEDGER_A="$PARENT/A/feat-a/.sdd-transitions.jsonl"
[[ -f "$LEDGER_A" ]] && grep -q '"to": "hardened"' "$LEDGER_A"; assert "A: .sdd-transitions.jsonl row present" $?
grep -q '"mode": "evidence"' "$LEDGER_A"; assert "A: ledger row carries mode=evidence" $?

# ── Fixture B (refusal): three sub-cases, status must stay `ready` ────────────
echo "=== Fixture B: refusal paths (status stays ready) ==="

# (i) bare --reason on this edge (no --mode evidence) → refused
WPBi="$(mkwp "$PARENT/Bi/feat-bi" wp-01-bi ready)"
set +e; OUT="$(bash "$TRANSITION" "$WPBi" hardened --reason "just reopen" 2>&1)"; RC=$?; set -e
if [[ "$RC" -ne 0 ]] && echo "$OUT" | grep -qi 'requires --mode evidence'; then
    ok "B(i): bare --reason revert refused (requires --mode evidence)"
else
    bad "B(i): bare --reason revert should be refused (rc=$RC)"
fi
[[ "$(status_of "$WPBi")" == "ready" ]]; assert "B(i): status still ready" $?

# (ii) --mode evidence pointing at an absent evidence path (file missing) → refused
WPBii="$(mkwp "$PARENT/Bii/feat-bii" wp-01-bii ready)"
set +e; OUT="$(bash "$TRANSITION" "$WPBii" hardened --mode evidence \
              --evidence "$WPBii/reharden/nope.md" --reason "x" 2>&1)"; RC=$?; set -e
if [[ "$RC" -ne 0 ]] && echo "$OUT" | grep -qi 'evidence file not found'; then
    ok "B(ii): absent evidence path refused (file not found)"
else
    bad "B(ii): absent evidence path should be refused (rc=$RC)"
fi
[[ "$(status_of "$WPBii")" == "ready" ]]; assert "B(ii): status still ready" $?

# (iii) --mode evidence with a malformed evidence file (missing locator) → refused
WPBiii="$(mkwp "$PARENT/Biii/feat-biii" wp-01-biii ready)"
mkdir -p "$WPBiii/reharden"
cat > "$WPBiii/reharden/bad.md" <<EOF
---
name: bad
kind: prototype-findings
summary: missing the locator field
plan: feat-biii
wp: wp-01-biii
created: $DATE
---

## Evidence
no locator
EOF
set +e; OUT="$(bash "$TRANSITION" "$WPBiii" hardened --mode evidence \
              --evidence "$WPBiii/reharden/bad.md" --reason "x" 2>&1)"; RC=$?; set -e
if [[ "$RC" -ne 0 ]] && echo "$OUT" | grep -qi 'evidence frontmatter must carry'; then
    ok "B(iii): malformed evidence (missing locator) refused"
else
    bad "B(iii): malformed evidence should be refused (rc=$RC)"
fi
[[ "$(status_of "$WPBiii")" == "ready" ]]; assert "B(iii): status still ready" $?

# (iv) --mode evidence with an UNTERMINATED-frontmatter evidence file → refused.
# No closing `---` fence; kind+summary sit in the pseudo-frontmatter and the
# required `locator` appears ONLY as a body prose line after `## Evidence`. The
# pre-fix parser (break-on-`---`, never requiring the close) recovered all three
# and ACCEPTED; the fence-tracking gate must refuse. No stray `---` anywhere — a
# markdown rule would count as a close and defeat the guard.
WPBiv="$(mkwp "$PARENT/Biv/feat-biv" wp-01-biv ready)"
mkdir -p "$WPBiv/reharden"
cat > "$WPBiv/reharden/unterminated.md" <<EOF
---
name: unterminated
kind: prototype-findings
summary: frontmatter never closes
plan: feat-biv
wp: wp-01-biv
created: $DATE

## Evidence
locator: plans/feat-biv/wp-01-biv/findings.md
EOF
set +e; OUT="$(bash "$TRANSITION" "$WPBiv" hardened --mode evidence \
              --evidence "$WPBiv/reharden/unterminated.md" --reason "x" 2>&1)"; RC=$?; set -e
if [[ "$RC" -ne 0 ]] && echo "$OUT" | grep -qi 'evidence frontmatter must carry'; then
    ok "B(iv): unterminated frontmatter refused (no closing fence)"
else
    bad "B(iv): unterminated frontmatter should be refused (rc=$RC)"
fi
[[ "$(status_of "$WPBiv")" == "ready" ]]; assert "B(iv): status still ready" $?

# ── Fixture C (trace): reharden.proposed + reharden.accepted rows land ────────
echo "=== Fixture C: trace-event emission ==="
WPC="$(mkwp "$PARENT/C/feat-c" wp-01-c ready)"
write_evidence "$WPC/reharden/$DATE-ev.md" "$DATE-ev" feat-c wp-01-c
GOALFORGE_TRACE_EMIT="$EMITTER" \
    bash "$TRANSITION" "$WPC" hardened --mode evidence \
        --evidence "$WPC/reharden/$DATE-ev.md" --reason "re-harden" >/dev/null 2>&1
RC=$?
[[ "$RC" -eq 0 ]]; assert "C: transition exit 0" $?
TRACE_C="$PARENT/C/feat-c/trace-events.jsonl"
[[ -f "$TRACE_C" ]] && grep -q 'reharden.proposed' "$TRACE_C"; assert "C: reharden.proposed row present" $?
grep -q 'reharden.accepted' "$TRACE_C" 2>/dev/null; assert "C: reharden.accepted row present" $?

# payload mirror: proposed/accepted rows carry the evidence file's kind/locator/
# summary AND the evidence path (compact JSON — no space after the colon; the
# emitter writes json.dumps(separators=(",",":"))). Values come from write_evidence
# above; the evidence path is asserted with grep -F (literal `/`).
EV_C="$WPC/reharden/$DATE-ev.md"
for ET in reharden.proposed reharden.accepted; do
    ROW="$(grep "\"type\":\"$ET\"" "$TRACE_C" 2>/dev/null | head -n1)"
    echo "$ROW" | grep -q '"kind":"prototype-findings"'; assert "C: $ET payload kind mirrored" $?
    echo "$ROW" | grep -q '"locator":"plans/feat-c/wp-01-c/findings.md"'; assert "C: $ET payload locator mirrored" $?
    echo "$ROW" | grep -q '"summary":"the ready goal no longer holds under the prototype"'; assert "C: $ET payload summary mirrored" $?
    echo "$ROW" | grep -qF "\"evidence\":\"$EV_C\""; assert "C: $ET payload evidence path mirrored" $?
done

# ── Fixture D (regression): existing edges unchanged ─────────────────────────
echo "=== Fixture D: regression on pre-existing edges ==="

# forward edge spec → hardened (not the evidence-gated edge; no --mode needed)
WPDf="$(mkwp "$PARENT/Df/feat-df" wp-01-df spec)"
bash "$TRANSITION" "$WPDf" hardened --reason "fwd" >/dev/null 2>&1; RC=$?
[[ "$RC" -eq 0 ]]; assert "D: forward spec→hardened exit 0" $?
[[ "$(status_of "$WPDf")" == "hardened" ]]; assert "D: forward spec→hardened status hardened" $?

# reverse edge executing → ready (--reason; NOT ready→hardened) unchanged
WPDr="$(mkwp "$PARENT/Dr/feat-dr" wp-01-dr executing)"
bash "$TRANSITION" "$WPDr" ready --reason "reopen" >/dev/null 2>&1; RC=$?
[[ "$RC" -eq 0 ]]; assert "D: reverse executing→ready exit 0" $?
[[ "$(status_of "$WPDr")" == "ready" ]]; assert "D: reverse executing→ready status ready" $?

# ── Hygiene: executable bit (subagent-rewrite gotcha) ────────────────────────
[[ -x "$TRANSITION" ]]; assert "goalforge-transition.sh keeps executable bit" $?

echo
echo "goalforge-transition-evidence.test.sh: $PASS passed, $FAIL failed"
[[ "$FAIL" -eq 0 ]]
