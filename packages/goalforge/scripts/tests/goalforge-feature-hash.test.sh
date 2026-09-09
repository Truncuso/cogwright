#!/usr/bin/env bash
# goalforge-feature-hash.test.sh — ticket-74 sabotage pair for
# goalforge-feature-hash.sh's contract_slice narrowing (wp-01 T5).
#
#   known-bad  : editing a NAMED slice's ## Interface Contract subsection
#                (one the WP's contract_slice: list references) DOES change
#                the hash -- asserted positively so a no-op implementation
#                (a hash that never reads spec.md) is caught.
#   known-good : editing an UNNAMED slice (a subsection outside the WP's
#                contract_slice: list) leaves the hash unchanged.
set -uo pipefail

SD="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FHASH="$SD/../goalforge-feature-hash.sh"
PASS=0; FAIL=0

ok()  { echo "  PASS: $1"; PASS=$((PASS+1)); }
bad() { echo "  FAIL: $1"; FAIL=$((FAIL+1)); }

T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT

FEAT="$T/feat"
WP="$FEAT/wp-01-a"
mkdir -p "$WP"

cat > "$FEAT/spec.md" <<'EOF'
# feat spec

## Interface Contract

### C1 — first slice

Original C1 body text.

### C2 — second slice

Original C2 body text.
EOF

cat > "$WP/overview.md" <<'EOF'
---
name: wp-01-a
title: feature-hash fixture
status: hardened
plan: feat
contract_slice: [C1]
---

# fixture wp
EOF

H_BEFORE="$(bash "$FHASH" "$WP")"

# ── known-bad guard: editing the NAMED slice (C1) changes the hash ──────────
sed -i 's/Original C1 body text\./Original C1 body text, mutated./' "$FEAT/spec.md"
H_AFTER_NAMED="$(bash "$FHASH" "$WP")"
if [[ "$H_AFTER_NAMED" != "$H_BEFORE" ]]; then
    ok "known-good: editing the named slice (C1) changes the hash"
else
    bad "known-good: editing the named slice (C1) changes the hash (defect: hash did not move)"
fi

# ── known-good: editing the UNNAMED slice (C2) leaves the hash unchanged ────
sed -i 's/Original C2 body text\./Original C2 body text, mutated./' "$FEAT/spec.md"
H_AFTER_UNNAMED="$(bash "$FHASH" "$WP")"
if [[ "$H_AFTER_UNNAMED" == "$H_AFTER_NAMED" ]]; then
    ok "known-good: editing an unnamed slice (C2) leaves the hash unchanged"
else
    bad "known-good: editing an unnamed slice (C2) leaves the hash unchanged ($H_AFTER_NAMED vs $H_AFTER_UNNAMED)"
fi

# ── usage error: missing WP dir -> exit 2 ────────────────────────────────────
bash "$FHASH" "$T/does-not-exist" >/dev/null 2>/tmp/fh-missing.err
RC=$?
if [[ "$RC" -eq 2 ]]; then
    ok "known-bad: nonexistent WP dir -> exit 2 (fail closed)"
else
    bad "known-bad: nonexistent WP dir -> exit 2 (fail closed) (rc=$RC)"
fi

echo
echo "goalforge-feature-hash.test.sh: $PASS passed, $FAIL failed"
[[ "$FAIL" -eq 0 ]]
