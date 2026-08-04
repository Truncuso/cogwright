#!/usr/bin/env bash
# goalforge-archived-collision.test.sh — regression tests for the archived-slug
# defect class: a slug that is ABSENT from the ACTIVE plans root but PRESENT
# under _archived/ must never be treated as free (okf-substrate duplicate stub,
# 2026-08-03), and archiving must stay permitted when inbound TYPED RELATION
# edges exist (design pin against over-tightening the reference-gate).
#
# Harness matches goalforge-archive.test.sh: the REAL script runs against
# throwaway fixture plans trees (never the live ~/.claude/plans/), with the
# validator stubbed via the GOALFORGE_VALIDATE seam so each case isolates
# archive logic from validator behavior.
#
# SCOPE NOTE — goalforge-capture Step 2 is PROSE (no capture script exists), so
# its compliance cannot be executed here. What IS tested is the script-level
# invariant the prose depends on: after a real archive, the directory-existence
# predicate `-d <root>/_archived/<slug>` is the discriminator that separates a
# free slug from an archived one, and a blind re-capture of that slug produces
# two nodes that the archive collision guard then rejects (exit 4). The prose
# itself is asserted statically by capture/evals/run.sh.
#
# Cases:
#   1 design pin: inbound typed relation edge does NOT gate archiving (exit 0)
#   2 negative control: inbound HARD path ref DOES gate (exit 6) — case 1 is
#     therefore not vacuous
#   3 design pin: the inbound edge is left byte-identical by the archive
#   4 post-archive probe predicate: slug absent live, present archived
#   5 defect class: blind re-capture yields two nodes for one slug; re-archiving
#     the duplicate collides (exit 4) — and the probe predicate would have
#     caught it before the first write
#   6 ideas track: ideas/_archived/<slug>.md is the second probe location
#   7 prose invariant: capture/SKILL.md documents both archived probes + HALT

set -uo pipefail
SD="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ARCHIVE="$SD/../goalforge-archive.sh"
CAPTURE_MD="$SD/../../capture/SKILL.md"
PASS=0; FAIL=0

ok()   { echo "  PASS: $1"; PASS=$((PASS+1)); }
bad()  { echo "  FAIL: $1"; FAIL=$((FAIL+1)); }
assert() { # $1=desc $2=condition-result(0/1 via $?)
    if [[ "$2" -eq 0 ]]; then ok "$1"; else bad "$1"; fi
}

mk_feature() { # $1=root $2=slug $3=status
    mkdir -p "$1/$2"
    cat > "$1/$2/overview.md" <<EOF
---
name: $2
status: $3
updated: 2026-07-01
relationships: []
---
# $2
Body of $2.
EOF
}

mk_dependent() { # $1=root $2=slug $3=typed-edge-target
    mkdir -p "$1/$2"
    cat > "$1/$2/overview.md" <<EOF
---
name: $2
status: active
updated: 2026-07-01
relationships:
  - depends_on: [[$3]]
---
# $2
Body of $2.
EOF
}

run_archive() { # all args forwarded; validator stubbed to pass
    GOALFORGE_VALIDATE=/bin/true "$ARCHIVE" "$@"
}

# The predicate goalforge-capture Step 2 must apply before treating a slug as
# absent. Directory existence, not overview.md presence — an archived feature
# dir may legitimately lack overview.md.
slug_taken() { # $1=plans-root $2=slug -> 0 if taken (live or archived)
    [[ -d "$1/$2" || -d "$1/_archived/$2" || -f "$1/ideas/$2.md" || -f "$1/ideas/_archived/$2.md" ]]
}

# ── Case 1+3: design pin — inbound typed relation edge does not gate ─────────
T=$(mktemp -d); mk_feature "$T/plans" feat-t completed; mk_dependent "$T/plans" feat-dep feat-t
before_dep=$(cat "$T/plans/feat-dep/overview.md")
run_archive feat-t --strict-refs --plans-root "$T/plans" >/dev/null 2>&1
rc=$?
[[ $rc -eq 0 ]]; assert "DESIGN PIN: inbound typed relation edge does not gate archiving (exit 0)" $?
[[ -d "$T/plans/_archived/feat-t" && ! -e "$T/plans/feat-t" ]]; assert "DESIGN PIN: feature still moves to _archived/ with inbound edges present" $?
after_dep=$(cat "$T/plans/feat-dep/overview.md")
[[ "$before_dep" == "$after_dep" ]]; assert "DESIGN PIN: inbound edge left byte-identical (survives, resolves terminal)" $?
rm -rf "$T"

# ── Case 2: negative control — a HARD path ref still gates ──────────────────
# Without this, case 1 would pass even if the ref-gate were disabled entirely.
T=$(mktemp -d); mk_feature "$T/plans" feat-p completed
mkdir -p "$T/plans/other"
echo 'locator: "plans/feat-p/overview.md"' > "$T/plans/other/overview.md"
run_archive feat-p --strict-refs --plans-root "$T/plans" >/dev/null 2>&1
[[ $? -eq 6 ]]; assert "negative control: inbound HARD path ref still gates under --strict-refs (exit 6)" $?
rm -rf "$T"

# ── Case 4: post-archive probe predicate ────────────────────────────────────
T=$(mktemp -d); mk_feature "$T/plans" feat-a completed
run_archive feat-a --plans-root "$T/plans" >/dev/null 2>&1
[[ $? -eq 0 ]]; assert "archive happy path exits 0" $?
[[ ! -e "$T/plans/feat-a" ]]; assert "post-archive: slug is ABSENT from the active root (the trap)" $?
[[ -d "$T/plans/_archived/feat-a" ]]; assert "post-archive: slug is PRESENT under _archived/ (the probe target)" $?
slug_taken "$T/plans" feat-a; assert "probe predicate reports the archived slug as TAKEN" $?
slug_taken "$T/plans" never-used; [[ $? -ne 0 ]]; assert "probe predicate reports an unused slug as FREE (not over-broad)" $?

# ── Case 5: defect class — blind re-capture yields two nodes for one slug ────
# A capture that skipped the probe would take this branch; assert both the
# duplicate state and that the archive collision guard rejects it (exit 4).
mkdir -p "$T/plans/feat-a"
cat > "$T/plans/feat-a/overview.md" <<'EOF'
---
name: feat-a
status: draft
updated: 2026-08-03
relationships: []
---
# feat-a
Blind re-capture stub — what an unguarded Step 2 produces.
EOF
[[ -f "$T/plans/feat-a/overview.md" && -f "$T/plans/_archived/feat-a/overview.md" ]]
assert "defect class reproduced: two nodes exist for one slug" $?
# The duplicate is unarchivable: at draft the status gate refuses first (exit 3),
# and once it reaches completed the destination-collision guard fires (exit 4).
# Either way the tree can never be reconciled by archiving — the slug is stuck
# with two nodes until a human merges them. Hence the probe must run at capture.
run_archive feat-a --plans-root "$T/plans" >/dev/null 2>&1
[[ $? -eq 3 ]]; assert "duplicate draft stub cannot be archived (status gate, exit 3)" $?
sed -i 's/^status: draft/status: completed/' "$T/plans/feat-a/overview.md"
run_archive feat-a --plans-root "$T/plans" >/dev/null 2>&1
[[ $? -eq 4 ]]; assert "duplicate node is a real conflict: re-archiving collides (exit 4)" $?
rm -rf "$T"

# ── Case 6: ideas track is the second probe location ───────────────────────
T=$(mktemp -d); mkdir -p "$T/plans/ideas/_archived"
cat > "$T/plans/ideas/_archived/okf-substrate.md" <<'EOF'
---
name: okf-substrate
status: promoted
---
Archived idea; slug absent from the live ideas/ root.
EOF
[[ ! -e "$T/plans/ideas/okf-substrate.md" ]]; assert "ideas: archived slug is absent from the live ideas/ root" $?
slug_taken "$T/plans" okf-substrate; assert "probe predicate reports the archived IDEA slug as TAKEN" $?
rm -rf "$T"

# ── Case 7: prose invariant (capture Step 2 is prose-only) ─────────────────
grep -qE '_archived/(<feature>|<slug>)/' "$CAPTURE_MD"
assert "capture/SKILL.md documents the plans/_archived probe" $?
grep -qE 'ideas/_archived/(<feature>|<slug>)\.md' "$CAPTURE_MD"
assert "capture/SKILL.md documents the ideas/_archived probe" $?
grep -qE 'HALT' "$CAPTURE_MD"
assert "capture/SKILL.md HALTs on an archived collision" $?

echo
echo "goalforge-archived-collision.test.sh: $PASS passed, $FAIL failed"
[[ $FAIL -eq 0 ]]
