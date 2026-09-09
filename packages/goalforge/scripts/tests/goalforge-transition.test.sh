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

echo
echo "goalforge-transition.test.sh: $PASS passed, $FAIL failed"
[[ "$FAIL" -eq 0 ]]
