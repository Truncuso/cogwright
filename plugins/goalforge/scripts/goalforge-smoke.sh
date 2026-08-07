#!/usr/bin/env bash
# goalforge-smoke.sh — offline end-to-end proof that the SHIPPED state-machine
# scripts drive a work package from `draft` to `verified`.
#
# Usage:
#   goalforge-smoke.sh --throwaway     provision a temp git plans root, walk it,
#                                      remove the whole root on exit (re-runnable)
#   goalforge-smoke.sh                 bare mode: walk SDD_PLANS_DIR and LEAVE the
#                                      walked fixture in place for inspection
#                                      (single-shot; refuses on a second run)
#
# The driver writes a one-WP fixture feature into the plans root from the
# heredocs below and walks its WP through the PINNED edge chain
#   draft -> spec -> hardened -> [goal-hash --record] -> ready (--mode auto)
#         -> executing -> [task status write] -> verified
# then takes the fixture FEATURE's one legal forward edge draft -> completed, so
# both edge tables and both classify_target branches are exercised. The on-disk
# `status:` is read back after EVERY hop and the first mismatch fails the run.
# A shortcut (e.g. the legal one-hop draft -> verified) is a spec violation here,
# not a simplification.
#
# Exactly ONE non-transition frontmatter write is sanctioned: the fixture task's
# `status: pending -> verified`, written between the `executing` and `verified`
# hops (no shipped script transitions a task-*.md, and a verified WP needs every
# sibling task verified). It uses the atomic tempfile + os.replace pattern of
# goalforge-transition.sh do_write.
#
# Exit codes:
#   0  the WP reads `status: verified`, the ledger holds exactly one row per
#      pinned edge, and goalforge-validate.sh --strict over the root is clean
#   3  RESERVED for the refusal guard alone — set before any callee runs, so 3
#      always means "refused", never "crashed"
#   1  anything else (usage, or any callee failure — trapped and re-exited as 1)
#
# No slash commands, no `claude -p`, no network. `flock` (used by
# goalforge-transition.sh) and python3 + PyYAML (used by goalforge-rollup.sh and
# goalforge-validate.sh, which every transition shells into) are the runtime
# prerequisites.
#
# Known bare-mode limitation (recorded, not fixed here): goalforge-transition.sh
# takes `flock` with no `-w`, so a concurrent holder of the fixture feature's
# .sdd-transitions.lock would block this script indefinitely. `--throwaway`
# cannot contend — it owns a fresh root.
set -Eeuo pipefail  # -E: the ERR trap must reach callees inside functions — without it "exit 3 means refused, never crashed" is false

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SELF="$SCRIPT_DIR/$(basename "${BASH_SOURCE[0]}")"
TRANSITION="$SCRIPT_DIR/goalforge-transition.sh"
GOAL_HASH="$SCRIPT_DIR/goalforge-goal-hash.sh"
VALIDATE="$SCRIPT_DIR/goalforge-validate.sh"

FIXTURE_FEATURE="gf-smoke-fixture"
FIXTURE_WP="wp-01-smoke"
FIXTURE_TASK="task-01-smoke"

usage() {
    sed -n '2,10p' "$SELF" | sed 's/^# \{0,1\}//'
}

# ── Argument parsing ────────────────────────────────────────────────────────

THROWAWAY=0
while [[ $# -gt 0 ]]; do
    case "$1" in
        --throwaway) THROWAWAY=1; shift ;;
        -h|--help)   usage; exit 0 ;;
        *)           echo "ERROR: unknown argument: $1" >&2; usage >&2; exit 1 ;;
    esac
done

# ── Refusal guard — the ONLY producer of exit 3 ─────────────────────────────
# Runs BEFORE any callee, so exit 3 can never mean "a callee crashed".

refuse() {
    echo "goalforge-smoke: refusing to run — $1" >&2
    echo "goalforge-smoke: re-run with --throwaway for a self-provisioned temp plans root." >&2
    exit 3
}

guard() {
    [[ "$THROWAWAY" -eq 1 ]] && return 0

    [[ -n "${SDD_PLANS_DIR:-}" ]] || refuse \
        "bare mode needs SDD_PLANS_DIR set to a caller-designated git plans root"
    [[ -d "$SDD_PLANS_DIR" ]] || refuse \
        "SDD_PLANS_DIR is not an existing directory: $SDD_PLANS_DIR"
    git -C "$SDD_PLANS_DIR" rev-parse --git-dir >/dev/null 2>&1 || refuse \
        "SDD_PLANS_DIR is not a git repository: $SDD_PLANS_DIR"

    local -a hits=()
    local g
    shopt -s nullglob
    for g in "$SDD_PLANS_DIR"/*/overview.md "$SDD_PLANS_DIR"/_archived/*/overview.md; do
        hits+=("$g")
    done
    shopt -u nullglob
    if [[ ${#hits[@]} -gt 0 ]]; then
        if [[ "${hits[0]}" == "$SDD_PLANS_DIR/$FIXTURE_FEATURE/"* ]]; then
            refuse "SDD_PLANS_DIR already holds a previous smoke run (${hits[0]}) — bare mode is single-shot; clear it with: rm -rf $SDD_PLANS_DIR/$FIXTURE_FEATURE"
        fi
        refuse "SDD_PLANS_DIR already holds feature dirs (${hits[0]}) — this is not a smoke root; bare mode never writes into a populated plans root"
    fi
}

guard

# ── Past the guard: every failure below re-exits 1, never 3 ─────────────────

on_err() {
    local rc=$?
    echo "goalforge-smoke: FAILED (callee exit $rc)" >&2
    exit 1
}
trap on_err ERR

fail() {
    echo "goalforge-smoke: FAILED — $1" >&2
    exit 1
}

# ── Plans root ──────────────────────────────────────────────────────────────

if [[ "$THROWAWAY" -eq 1 ]]; then
    THROWAWAY_ROOT="$(mktemp -d)"
    trap 'rm -rf "$THROWAWAY_ROOT"' EXIT
    git -C "$THROWAWAY_ROOT" init -q
    export SDD_PLANS_DIR="$THROWAWAY_ROOT"
fi

ROOT="$SDD_PLANS_DIR"
FEATURE_DIR="$ROOT/$FIXTURE_FEATURE"
WP_DIR="$FEATURE_DIR/$FIXTURE_WP"
FEATURE_OVERVIEW="$FEATURE_DIR/overview.md"
WP_OVERVIEW="$WP_DIR/overview.md"
TASK_FILE="$WP_DIR/$FIXTURE_TASK.md"
LEDGER="$FEATURE_DIR/.sdd-transitions.jsonl"
TODAY="$(date +%F)"

echo "goalforge-smoke: plans root $ROOT"

# ── 1. Emit the fixture (heredocs — no fixture .md ships under packages/) ───
# The fixture text carries NO rewrite-class token (no author install path, no
# $SCRIPT_DIR climb), so the generated plugin copy of this script emits a
# byte-identical fixture.

emit_fixture() {
    mkdir -p "$WP_DIR"

    cat > "$FEATURE_OVERVIEW" <<EOF
---
name: $FIXTURE_FEATURE
title: "goalforge smoke fixture feature"
status: draft
created: $TODAY
feature: $FIXTURE_FEATURE
work_packages: [$FIXTURE_WP]
---

# goalforge smoke fixture feature

Emitted by goalforge-smoke.sh. Disposable.
EOF

    cat > "$WP_OVERVIEW" <<EOF
---
name: $FIXTURE_WP
title: "goalforge smoke fixture work package"
status: draft
schema_version: 5
stage_updated: $TODAY
severity: LOW
parallel: false
depends_on: []
plan: $FIXTURE_FEATURE
task_type: code
goal:
  outcome: "The fixture work package walks the pinned edge chain through the shipped scripts and lands at verified."
  verification:
    strategy: deterministic
    check: "true"
inherits_from: null
goal_approved_version: null
---

# goalforge smoke fixture work package

## Goal

Walk the pinned edge chain. No real work.

## Open Questions

## Decisions

- Fixture emitted by goalforge-smoke.sh; no pre-computed goal hash.
EOF

    cat > "$TASK_FILE" <<EOF
---
name: $FIXTURE_TASK
title: "goalforge smoke fixture task"
status: pending
verify: "true"
---

# goalforge smoke fixture task

checkpoint: fixture task emitted by goalforge-smoke.sh (body-level, defence-in-depth)
EOF
}

# ── 2. Walk the pinned chain, reading status back after EVERY hop ───────────

read_status() {
    python3 - "$1" <<'PY'
import sys, re
lines = open(sys.argv[1], encoding="utf-8").read().split("\n")
if not lines or lines[0].strip() != "---":
    sys.exit(1)
for ln in lines[1:]:
    if ln.strip() == "---":
        break
    m = re.match(r"^status:\s*(\S+)\s*$", ln)
    if m:
        print(m.group(1).strip("'\""))
        break
PY
}

assert_status() {
    # $1=overview  $2=expected  $3=label
    local got
    got="$(read_status "$1")"
    [[ "$got" == "$2" ]] || fail "after $3: on-disk status is '$got', expected '$2' ($1)"
    echo "goalforge-smoke: ok $3 -> $2"
}

# Write the fixture task's status atomically (tempfile + os.replace), mirroring
# goalforge-transition.sh do_write. This is the ONE sanctioned non-transition
# frontmatter write: no shipped script transitions a task-*.md, and validate
# invariant 1 requires every sibling task verified under a verified WP.
write_task_status() {
    python3 - "$1" "$2" <<'PY'
import sys, os, re, tempfile
path, to = sys.argv[1], sys.argv[2]
lines = open(path, encoding="utf-8").read().split("\n")
if not lines or lines[0].strip() != "---":
    sys.stderr.write("no frontmatter in %s\n" % path); sys.exit(1)
end = None
for i in range(1, len(lines)):
    if lines[i].strip() == "---":
        end = i; break
if end is None:
    sys.stderr.write("unterminated frontmatter in %s\n" % path); sys.exit(1)
found = False
for i in range(1, end):
    if re.match(r"^status:\s*", lines[i]):
        lines[i] = "status: %s" % to; found = True
if not found:
    sys.stderr.write("no status: key in %s\n" % path); sys.exit(1)
new = "\n".join(lines)
d = os.path.dirname(os.path.abspath(path))
fd, tmp = tempfile.mkstemp(dir=d, suffix=".tmp")
try:
    with os.fdopen(fd, "w", encoding="utf-8") as f:
        f.write(new)
    os.replace(tmp, path)
except Exception:
    try: os.unlink(tmp)
    except OSError: pass
    raise
PY
}

walk_chain() {
    bash "$TRANSITION" "$WP_DIR" spec --reason "smoke: draft to spec"
    assert_status "$WP_OVERVIEW" spec "draft->spec"

    bash "$TRANSITION" "$WP_DIR" hardened --reason "smoke: spec to hardened"
    assert_status "$WP_OVERVIEW" hardened "spec->hardened"

    # MANDATORY before ->ready: the ready gate refuses while goal_approved_version
    # is null or != the recomputed goal-block hash, and --override has no escape
    # on that path. The fixture therefore ships no pre-computed hash.
    bash "$GOAL_HASH" --record "$WP_DIR" >/dev/null
    assert_status "$WP_OVERVIEW" hardened "goal-hash --record (status unchanged)"

    # The transition also auto-creates the missing findings.md here — expected.
    bash "$TRANSITION" "$WP_DIR" ready --mode auto \
        --reason "signal-scoped auto-advance: complexity simple, severity LOW, task_type code"
    assert_status "$WP_OVERVIEW" ready "hardened->ready"

    bash "$TRANSITION" "$WP_DIR" executing --reason "smoke: ready to executing"
    assert_status "$WP_OVERVIEW" executing "ready->executing"

    write_task_status "$TASK_FILE" verified
    [[ "$(read_status "$TASK_FILE")" == "verified" ]] \
        || fail "sanctioned task-status write did not land in $TASK_FILE"
    echo "goalforge-smoke: ok task status -> verified (sanctioned atomic write)"

    bash "$TRANSITION" "$WP_DIR" verified --reason "smoke: executing to verified"
    assert_status "$WP_OVERVIEW" verified "executing->verified"

    # The feature edge table's one legal forward hop — also exercises
    # classify_target's `feature` branch.
    bash "$TRANSITION" "$FEATURE_DIR" completed --reason "smoke: feature draft to completed"
    assert_status "$FEATURE_OVERVIEW" completed "feature draft->completed"
}

# ── 3. Assert the end state from an authority other than our own control flow ─

PINNED_EDGES=(
    '"from": "draft", "to": "spec"'
    '"from": "spec", "to": "hardened"'
    '"from": "hardened", "to": "ready"'
    '"from": "ready", "to": "executing"'
    '"from": "executing", "to": "verified"'
    '"from": "draft", "to": "completed"'
)

assert_end_state() {
    [[ "$(read_status "$WP_OVERVIEW")" == "verified" ]] \
        || fail "WP overview frontmatter does not read 'status: verified': $WP_OVERVIEW"

    [[ -f "$LEDGER" ]] || fail "no transition ledger at $LEDGER"

    local e
    for e in "${PINNED_EDGES[@]}"; do
        grep -qF "$e" "$LEDGER" || fail "ledger is missing the pinned edge row: $e"
    done

    # The --mode flag is documentary at the transition layer (mode defaults to
    # auto); the discriminating evidence for the pinned auto-advance is the
    # signal-scoped reason ON the ready row, asserted together with its mode.
    grep -F '"to": "ready"' "$LEDGER" | grep -F '"mode": "auto"' | grep -qF 'signal-scoped auto-advance' \
        || fail "ready row does not carry mode=auto with the signal-scoped auto-advance reason"

    local rows
    rows="$(wc -l < "$LEDGER")"
    [[ "$rows" -eq ${#PINNED_EDGES[@]} ]] \
        || fail "ledger holds $rows rows, expected ${#PINNED_EDGES[@]} (one per pinned edge — a shortcut edge is a spec violation)"
    echo "goalforge-smoke: ok ledger holds $rows rows, one per pinned edge"

    bash "$VALIDATE" --strict "$ROOT" \
        || fail "goalforge-validate.sh --strict reported errors over $ROOT"
    echo "goalforge-smoke: ok goalforge-validate.sh --strict reports zero errors (warnings expected)"
}

emit_fixture
walk_chain
assert_end_state

echo "goalforge-smoke: PASS ($FIXTURE_WP verified via the shipped scripts)"
if [[ "$THROWAWAY" -eq 1 ]]; then
    echo "goalforge-smoke: throwaway root removed on exit"
else
    echo "goalforge-smoke: walked fixture left in place at $FEATURE_DIR"
    echo "goalforge-smoke: re-run bare mode after: rm -rf $FEATURE_DIR"
fi
