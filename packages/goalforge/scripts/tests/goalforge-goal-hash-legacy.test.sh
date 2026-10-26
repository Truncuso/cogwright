#!/usr/bin/env bash
# goalforge-goal-hash-legacy.test.sh — legacy (pre-2026-09-09, commit 4b3b953)
# whole-block goal hash: recognition, validator downgrade, and the proof-gated
# --restamp-legacy migration.
#
# Drives the REAL goalforge-goal-hash.sh and goalforge-validate.sh over
# throwaway mktemp fixtures (never a live plans/ tree).
#
#   (a) --legacy output is PINNED to the value the real pre-4b3b953 script
#       printed for the fixture below (`git show 4b3b953^:.../goalforge-goal-hash.sh`).
#   (b) legacy stamp + untouched goal -> --matches prints `legacy`; the validator
#       WARNs legacy-hash-stamp and does NOT raise evolved-goal (exit 0 --strict).
#   (c) sabotage: outcome edited under a legacy stamp -> --matches exit 1 and the
#       validator raises evolved-goal-without-reharden (non-zero --strict).
#   (d) git fixture: approve (legacy stamp), commit a constraints-only edit ->
#       --restamp-legacy exit 0 writes the narrow hash; rerun -> noop.
#   (e) sabotage: verification edited after approval -> --restamp-legacy exit 4
#       and the file is byte-identical.
set -uo pipefail

SD="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HASH="$SD/../goalforge-goal-hash.sh"
VALIDATE="$SD/../goalforge-validate.sh"
PASS=0; FAIL=0

ok()  { echo "  PASS: $1"; PASS=$((PASS+1)); }
bad() { echo "  FAIL: $1"; FAIL=$((FAIL+1)); }

# Pinned: output of the real pre-4b3b953 goalforge-goal-hash.sh on mk_wp below.
PINNED_LEGACY="bcd226174987"

mk_wp() { # $1=wp-dir $2=stamp (or null)
    mkdir -p "$1"
    cat > "$1/overview.md" <<EOF
---
name: $(basename "$1")
title: legacy hash fixture
status: ready
stage_updated: 2026-09-01
severity: LOW
parallel: false
depends_on: []
plan: tmpfeat
task_type: code
goal:
  outcome: "the legacy thing is done"
  verification:
    strategy: deterministic
    check: "true"
  constraints: []
  boundaries: []
  iteration_policy: "retry until green"
  blocked_stop: "halt after 3 tries"
inherits_from: null
goal_approved_version: ${2:-null}
---

# fixture
EOF
}

mk_feature() { # $1=plans-root $2=wp-name
    mkdir -p "$1/tmpfeat"
    cat > "$1/tmpfeat/overview.md" <<EOF
---
name: tmpfeat
title: Legacy-hash test feature
status: ready
created: 2026-09-01
feature: tmpfeat
work_packages: [$2]
---

# fixture feature
EOF
}

T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT

# ── (a) legacy output pinned to the real pre-change script ───────────────────
mk_wp "$T/a/wp-01-legacy" null
H_LEG="$(bash "$HASH" --legacy "$T/a/wp-01-legacy")"
if [[ "$H_LEG" == "$PINNED_LEGACY" ]]; then
    ok "(a) --legacy reproduces the pre-4b3b953 whole-block hash ($PINNED_LEGACY)"
else
    bad "(a) --legacy reproduces the pre-4b3b953 whole-block hash (got '$H_LEG', want $PINNED_LEGACY)"
fi
H_NAR="$(bash "$HASH" "$T/a/wp-01-legacy")"
if [[ -n "$H_NAR" && "$H_NAR" != "$H_LEG" ]]; then
    ok "(a) narrow and legacy definitions differ on the fixture (non-vacuous)"
else
    bad "(a) narrow and legacy definitions differ on the fixture ($H_NAR vs $H_LEG)"
fi

# ── (b) legacy stamp + untouched goal -> legacy match, validator WARNs ───────
PR="$T/b/plans"; WP="$PR/tmpfeat/wp-01-legacy"
mk_feature "$PR" wp-01-legacy
mk_wp "$WP" "\"$PINNED_LEGACY\""
M_OUT="$(bash "$HASH" --matches "$WP" "$PINNED_LEGACY")"; M_RC=$?
if [[ "$M_RC" -eq 0 && "$M_OUT" == "legacy" ]]; then
    ok "(b) --matches reports legacy for an untouched pre-09-09 stamp"
else
    bad "(b) --matches reports legacy (rc=$M_RC out=$M_OUT)"
fi
V_OUT="$(bash "$VALIDATE" --strict --show "$PR" 2>&1)"; V_RC=$?
if [[ "$V_RC" -eq 0 ]] && echo "$V_OUT" | grep -q 'legacy-hash-stamp' \
        && ! echo "$V_OUT" | grep -q 'evolved-goal'; then
    ok "(b) validator WARNs legacy-hash-stamp, no evolved-goal, exit 0 --strict"
else
    echo "$V_OUT" | sed 's/^/      /'
    bad "(b) validator WARNs legacy-hash-stamp, no evolved-goal (rc=$V_RC)"
fi

# ── (c) sabotage: outcome edited under a legacy stamp -> evolved-goal ────────
sed -i 's/outcome: "the legacy thing is done"/outcome: "the legacy thing is DONE"/' "$WP/overview.md"
M_OUT="$(bash "$HASH" --matches "$WP" "$PINNED_LEGACY")"; M_RC=$?
if [[ "$M_RC" -eq 1 && "$M_OUT" =~ ^[0-9a-f]{12}$ ]]; then
    ok "(c) --matches exit 1 (prints narrow hash) after an outcome edit"
else
    bad "(c) --matches exit 1 after an outcome edit (rc=$M_RC out=$M_OUT)"
fi
V_OUT="$(bash "$VALIDATE" --strict --show "$PR" 2>&1)"; V_RC=$?
if [[ "$V_RC" -ne 0 ]] && echo "$V_OUT" | grep -q 'evolved-goal-without-reharden'; then
    ok "(c) validator raises evolved-goal-without-reharden (non-zero --strict)"
else
    echo "$V_OUT" | sed 's/^/      /'
    bad "(c) validator raises evolved-goal-without-reharden (rc=$V_RC)"
fi

# ── git fixture helper for (d)/(e) ───────────────────────────────────────────
git_repo() { # $1=repo-dir; commits a legacy-stamped WP at wp-01-legacy/
    mkdir -p "$1"
    git -C "$1" init -q
    git -C "$1" config user.email t@example.invalid
    git -C "$1" config user.name tester
    git -C "$1" config commit.gpgsign false
    mk_wp "$1/wp-01-legacy" "\"$PINNED_LEGACY\""
    git -C "$1" add -A && git -C "$1" commit -q --no-verify -m approve
}

# ── (d) constraints-only edit after approval -> restamp writes narrow; noop ──
R="$T/d/repo"; git_repo "$R"
sed -i 's/constraints: \[\]/constraints: ["no regressions"]/' "$R/wp-01-legacy/overview.md"
git -C "$R" commit -q --no-verify -am "constraints-only edit"
N_WANT="$(bash "$HASH" "$R/wp-01-legacy")"
RS_OUT="$(bash "$HASH" --restamp-legacy "$R/wp-01-legacy" 2>&1)"; RS_RC=$?
if [[ "$RS_RC" -eq 0 ]] && grep -q "^goal_approved_version: \"$N_WANT\"$" "$R/wp-01-legacy/overview.md"; then
    ok "(d) --restamp-legacy proves via git and records the narrow hash ($N_WANT)"
else
    echo "$RS_OUT" | sed 's/^/      /'
    bad "(d) --restamp-legacy records the narrow hash (rc=$RS_RC)"
fi
RS_OUT="$(bash "$HASH" --restamp-legacy "$R/wp-01-legacy" 2>&1)"; RS_RC=$?
if [[ "$RS_RC" -eq 0 ]] && echo "$RS_OUT" | grep -q '^noop'; then
    ok "(d) rerun of --restamp-legacy is a noop"
else
    bad "(d) rerun of --restamp-legacy is a noop (rc=$RS_RC out=$RS_OUT)"
fi

# ── (e) sabotage: verification edited after approval -> exit 4, untouched ───
R="$T/e/repo"; git_repo "$R"
sed -i 's/check: "true"/check: "false"/' "$R/wp-01-legacy/overview.md"
git -C "$R" commit -q --no-verify -am "verification edit"
SUM_BEFORE="$(sha256sum < "$R/wp-01-legacy/overview.md")"
RS_OUT="$(bash "$HASH" --restamp-legacy "$R/wp-01-legacy" 2>&1)"; RS_RC=$?
SUM_AFTER="$(sha256sum < "$R/wp-01-legacy/overview.md")"
if [[ "$RS_RC" -eq 4 && "$SUM_BEFORE" == "$SUM_AFTER" ]] \
        && echo "$RS_OUT" | grep -q 'changed since approval'; then
    ok "(e) --restamp-legacy refuses (exit 4) and leaves the file byte-identical"
else
    echo "$RS_OUT" | sed 's/^/      /'
    bad "(e) --restamp-legacy refuses, file untouched (rc=$RS_RC)"
fi

# ── (e') untracked file with a non-matching stamp -> exit 4, untouched ───────
mk_wp "$T/e2/wp-01-legacy" '"0123456789ab"'
SUM_BEFORE="$(sha256sum < "$T/e2/wp-01-legacy/overview.md")"
bash "$HASH" --restamp-legacy "$T/e2/wp-01-legacy" >/dev/null 2>&1; RS_RC=$?
SUM_AFTER="$(sha256sum < "$T/e2/wp-01-legacy/overview.md")"
if [[ "$RS_RC" -eq 4 && "$SUM_BEFORE" == "$SUM_AFTER" ]]; then
    ok "(e') untracked file, unprovable stamp -> exit 4, file untouched"
else
    bad "(e') untracked file, unprovable stamp -> exit 4 (rc=$RS_RC)"
fi

echo
echo "goalforge-goal-hash-legacy.test.sh: $PASS passed, $FAIL failed"
[[ "$FAIL" -eq 0 ]]
