#!/usr/bin/env bash
# evals/trace-substrate/run.sh — WP-14 trace-substrate verification suite.
#
# Runs the full gate-case matrix (a)-(g) for the trace event substrate, hermetic
# in temp workspaces, no network, deterministic. Aggregates the standalone case
# scripts authored by tasks 03/04 (it invokes them, never re-implements them) and
# adds the harness-owned cases (a),(b),(e),(g) plus the (f) self-test drivers.
#
#   (a) emit-valid-reject          — valid append; unknown-type/missing-required
#                                     rejected exit 2, log byte-unchanged
#   (b) seq-monotonic-append-only  — seq strictly monotonic; earlier bytes frozen
#   (c) derive-deterministic       — delegate → cases/legacy-derivation.sh
#   (d) transition-integration     — delegate → cases/transition-wiring.sh
#   (e) schema-validates-all       — every fixture event of every type validates
#   (f) self-test                  — emitter + derive --self-test both exit 0
#   (g) combined-derive-live       — derive + live-emit on one feature: no
#                                     duplicate, no mis-ordered seq (OQ3 cutover)
#
# Usage:
#   run.sh                 run every case; exit 0 iff all green
#   run.sh --case <name>   run one case (letter a-g or canonical name)
#   run.sh --self-test     harness sanity (fixtures/cases present + executable,
#                          scripts executable, embedded schema parses)
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS="$(cd "$HERE/../../scripts" && pwd)"
CASES="$HERE/cases"
FIXTURES="$HERE/fixtures"
EMIT="$SCRIPTS/goalforge-trace-emit"
DERIVE="$SCRIPTS/goalforge-trace-derive"

WORKROOT="$(mktemp -d)"
trap 'rm -rf "$WORKROOT"' EXIT
mktmp() { mktemp -d "$WORKROOT/case.XXXXXX"; }

c_pass=0; c_fail=0
pass() { echo "PASS ($1): $2"; c_pass=$((c_pass+1)); }
fail() { echo "FAIL ($1): $2"; c_fail=$((c_fail+1)); }

# Validate every non-blank row of a JSONL log against the embedded schema
# (reusing the emitter's own schema loader + validator). Also assert seq is
# contiguous 0..n-1 when $2 == "contiguous". Exit 0 iff all rows valid (and, if
# requested, seq contiguous with no duplicates).
_validate_log() {
    python3 - "$EMIT" "$1" "${2:-}" <<'PY'
import sys, json
from importlib.machinery import SourceFileLoader
emit_path, log_path, mode = sys.argv[1], sys.argv[2], (sys.argv[3] if len(sys.argv) > 3 else "")
mod = SourceFileLoader("emit", emit_path).load_module()
schema = mod.load_schema()
rows = [json.loads(ln) for ln in open(log_path, encoding="utf-8") if ln.strip()]
bad = [r for r in rows if mod._validate(r, schema)]
if bad:
    print("invalid row:", bad[0]); sys.exit(1)
if mode == "contiguous":
    seqs = [r["seq"] for r in rows]
    if seqs != list(range(len(seqs))):
        print("seq not contiguous 0..n-1:", seqs); sys.exit(1)
sys.exit(0)
PY
}

# ── (a) emit-valid-reject ─────────────────────────────────────────────────────
case_a() {
    local tmp feat log rc sha_before sha_after
    tmp="$(mktmp)"
    feat="$tmp/plans/afeat"; mkdir -p "$feat"
    log="$feat/trace-events.jsonl"

    # valid append → exit 0, one row, schema-valid, seq 0
    if python3 "$EMIT" --feature-dir "$feat" \
        --event '{"type":"wp.status_changed","wp":"wp-01-a","from":"spec","to":"hardened","reason":"fwd","actor":"t"}' \
        >/dev/null 2>&1 \
        && [[ -f "$log" ]] && _validate_log "$log" contiguous >/dev/null 2>&1; then
        pass a "valid typed event appended, schema-valid, seq contiguous"
    else
        fail a "valid typed event should append and validate"
    fi

    # unknown type → exit 2, log byte-unchanged
    sha_before="$(sha256sum "$log" | cut -d' ' -f1)"
    set +e
    python3 "$EMIT" --feature-dir "$feat" \
        --event '{"type":"bogus.event","wp":"wp-01-a"}' >/dev/null 2>&1
    rc=$?
    set -e
    sha_after="$(sha256sum "$log" | cut -d' ' -f1)"
    if [[ "$rc" -eq 2 && "$sha_before" == "$sha_after" ]]; then
        pass a "unknown event type rejected exit 2, log byte-unchanged"
    else
        fail a "unknown type should reject exit 2 + leave log unchanged (rc=$rc)"
    fi

    # missing required field (wp.status_changed without from/to) → exit 2, unchanged
    sha_before="$(sha256sum "$log" | cut -d' ' -f1)"
    set +e
    python3 "$EMIT" --feature-dir "$feat" \
        --event '{"type":"wp.status_changed","wp":"wp-01-a"}' >/dev/null 2>&1
    rc=$?
    set -e
    sha_after="$(sha256sum "$log" | cut -d' ' -f1)"
    if [[ "$rc" -eq 2 && "$sha_before" == "$sha_after" ]]; then
        pass a "missing required field rejected exit 2, log byte-unchanged"
    else
        fail a "missing required field should reject exit 2 + leave log unchanged (rc=$rc)"
    fi
}

# ── (b) seq-monotonic-append-only ─────────────────────────────────────────────
case_b() {
    local tmp feat log head_before head_after seqs
    tmp="$(mktmp)"
    feat="$tmp/plans/bfeat"; mkdir -p "$feat"
    log="$feat/trace-events.jsonl"

    python3 "$EMIT" --feature-dir "$feat" \
        --event '{"type":"wp.status_changed","wp":"wp-01-b","from":"spec","to":"hardened","actor":"t"}' >/dev/null 2>&1
    # snapshot the first two rows' bytes, then append a third
    python3 "$EMIT" --feature-dir "$feat" \
        --event '{"type":"wp.status_changed","wp":"wp-01-b","from":"hardened","to":"ready","actor":"t"}' >/dev/null 2>&1
    head_before="$(sha256sum <(head -n 2 "$log") | cut -d' ' -f1)"
    python3 "$EMIT" --feature-dir "$feat" \
        --event '{"type":"gate.result","wp":"wp-01-b","gate":"verify","result":"pass","actor":"t"}' >/dev/null 2>&1
    head_after="$(sha256sum <(head -n 2 "$log") | cut -d' ' -f1)"

    # seq strictly monotonic + contiguous 0,1,2
    seqs="$(python3 - "$log" <<'PY'
import sys, json
rows = [json.loads(l) for l in open(sys.argv[1]) if l.strip()]
s = [r["seq"] for r in rows]
print("OK" if s == sorted(s) and len(set(s)) == len(s) and s == list(range(len(s))) else "BAD", s)
PY
)"
    if [[ "$seqs" == OK* ]]; then
        pass b "seq strictly monotonic + contiguous across appends"
    else
        fail b "seq should be strictly monotonic + contiguous ($seqs)"
    fi
    if [[ "$head_before" == "$head_after" ]]; then
        pass b "append-only: existing rows' bytes never rewritten"
    else
        fail b "append should not rewrite existing bytes"
    fi
}

# ── (c) derive-deterministic → delegate ───────────────────────────────────────
case_c() {
    if bash "$CASES/legacy-derivation.sh" >/dev/null 2>&1; then
        pass c "legacy derivation deterministic + idempotent (cases/legacy-derivation.sh)"
    else
        fail c "cases/legacy-derivation.sh failed"
    fi
}

# ── (d) transition-integration → delegate ─────────────────────────────────────
case_d() {
    if bash "$CASES/transition-wiring.sh" >/dev/null 2>&1; then
        pass d "transition wiring emits valid typed rows (cases/transition-wiring.sh)"
    else
        fail d "cases/transition-wiring.sh failed"
    fi
}

# ── (e) schema-validates-all ──────────────────────────────────────────────────
case_e() {
    local fx types
    fx="$FIXTURES/all-events.jsonl"
    if [[ ! -f "$fx" ]]; then
        fail e "fixtures/all-events.jsonl missing"; return
    fi
    if ! _validate_log "$fx" >/dev/null 2>&1; then
        fail e "every fixture event should validate against the embedded schema"; return
    fi
    # assert all 9 event types are represented
    types="$(python3 - "$fx" <<'PY'
import sys, json
seen = {json.loads(l)["type"] for l in open(sys.argv[1]) if l.strip()}
want = {"wp.status_changed","feature.status_changed","task.status_changed",
        "commit.linked","gate.result","finding.recorded",
        "dispatch.launched","dispatch.completed","issue.recorded"}
print("OK" if seen == want else "MISSING " + ",".join(sorted(want - seen)))
PY
)"
    if [[ "$types" == "OK" ]]; then
        pass e "all 9 event types present and schema-valid"
    else
        fail e "fixture coverage incomplete ($types)"
    fi
}

# ── (f) self-test drivers ─────────────────────────────────────────────────────
case_f() {
    if python3 "$EMIT" --self-test >/dev/null 2>&1 && python3 "$DERIVE" --self-test >/dev/null 2>&1; then
        pass f "emitter + derive --self-test both exit 0"
    else
        fail f "emitter/derive --self-test should exit 0"
    fi
}

# ── (g) combined-derive-live ──────────────────────────────────────────────────
# Cutover flow: derive pre-emitter rows into an EMPTY trace log (seq 0..N-1),
# then drive live emits (seq continues at N). Assert the combined log validates,
# seq is contiguous with no duplicate, and rows are in non-decreasing seq order.
case_g() {
    local tmp feat ledger log res
    tmp="$(mktmp)"
    feat="$tmp/plans/gfeat"; mkdir -p "$feat"
    ledger="$feat/.sdd-transitions.jsonl"
    log="$feat/trace-events.jsonl"

    cat > "$ledger" <<'EOF'
{"ts": "2026-07-01T00:00:00Z", "wp": "wp-01-a", "from": "spec", "to": "hardened", "reason": "harden", "actor": "goalforge-harden", "override": false, "commit": "abc1234", "mode": "auto", "session": "s1", "model": "opus", "provider": "anthropic", "agent": "", "decision_ref": "findings.md"}
{"ts": "2026-07-02T00:00:00Z", "wp": "gfeat", "from": "ready", "to": "executing", "reason": "exec", "actor": "goalforge-execute", "override": false, "commit": "", "mode": "auto", "session": "s1", "model": "opus", "provider": "anthropic", "agent": "", "decision_ref": ""}
EOF

    # 1. derive pre-emitter rows (empty log → whole ledger, seq 0..N-1)
    python3 "$DERIVE" "$feat" --write >/dev/null 2>&1
    # 2. live-emit continues after the derived boundary
    python3 "$EMIT" --feature-dir "$feat" \
        --event '{"type":"wp.status_changed","wp":"wp-01-a","from":"hardened","to":"ready","actor":"goalforge-harden"}' >/dev/null 2>&1
    python3 "$EMIT" --feature-dir "$feat" \
        --event '{"type":"gate.result","wp":"wp-01-a","gate":"verify","result":"pass","actor":"goalforge-verify"}' >/dev/null 2>&1

    # combined log: schema-valid, seq contiguous 0..n-1 (no dup, no gap, ordered)
    res="$(python3 - "$EMIT" "$log" <<'PY'
import sys, json
from importlib.machinery import SourceFileLoader
mod = SourceFileLoader("emit", sys.argv[1]).load_module()
schema = mod.load_schema()
rows = [json.loads(l) for l in open(sys.argv[2]) if l.strip()]
bad = [r for r in rows if mod._validate(r, schema)]
seqs = [r["seq"] for r in rows]
if bad:
    print("INVALID", bad[0])
elif len(set(seqs)) != len(seqs):
    print("DUPLICATE", seqs)
elif seqs != sorted(seqs):
    print("MISORDERED", seqs)
elif seqs != list(range(len(seqs))):
    print("GAP", seqs)
else:
    print("OK", len(seqs))
PY
)"
    if [[ "$res" == OK* ]]; then
        pass g "derive + live-emit: no duplicate, no mis-ordered seq (OQ3 cutover holds) [$res]"
    else
        fail g "combined derive+live seq contract violated ($res)"
    fi
}

# ── harness self-test ─────────────────────────────────────────────────────────
self_test() {
    local ok=0
    echo "run.sh --self-test: harness sanity"
    for f in "$FIXTURES/all-events.jsonl" "$CASES/transition-wiring.sh" "$CASES/legacy-derivation.sh"; do
        if [[ -f "$f" ]]; then echo "  ok present: $f"; else echo "  MISSING: $f"; ok=1; fi
    done
    for x in "$CASES/transition-wiring.sh" "$CASES/legacy-derivation.sh" "$EMIT" "$DERIVE"; do
        if [[ -x "$x" ]]; then echo "  ok executable: $x"; else echo "  NOT EXECUTABLE: $x"; ok=1; fi
    done
    if python3 - "$EMIT" <<'PY'
import sys
from importlib.machinery import SourceFileLoader
mod = SourceFileLoader("emit", sys.argv[1]).load_module()
s = mod.load_schema()
assert len(s.get("oneOf", [])) == 9, "expected 9 schema branches"
print("  ok embedded schema parses (9 branches)")
PY
    then :; else echo "  SCHEMA PARSE FAILED"; ok=1; fi
    if _validate_log "$FIXTURES/all-events.jsonl" >/dev/null 2>&1; then
        echo "  ok fixtures/all-events.jsonl schema-valid"
    else
        echo "  FIXTURE VALIDATION FAILED"; ok=1
    fi
    return "$ok"
}

# ── dispatch ──────────────────────────────────────────────────────────────────
run_case() {
    case "$1" in
        a|emit-valid-reject)          case_a ;;
        b|seq-monotonic-append-only)  case_b ;;
        c|derive-deterministic)       case_c ;;
        d|transition-integration)     case_d ;;
        e|schema-validates-all)       case_e ;;
        f|self-test)                  case_f ;;
        g|combined-derive-live)       case_g ;;
        *) echo "unknown case: $1" >&2; return 2 ;;
    esac
}

main() {
    if [[ "${1:-}" == "--self-test" ]]; then
        self_test; exit $?
    fi
    if [[ "${1:-}" == "--case" ]]; then
        [[ -n "${2:-}" ]] || { echo "--case needs a name" >&2; exit 2; }
        run_case "$2"
        echo ""
        echo "Results: $c_pass passed, $c_fail failed"
        [[ "$c_fail" -eq 0 ]]
        exit $?
    fi
    for c in a b c d e f g; do run_case "$c"; done
    echo ""
    echo "Results: $c_pass passed, $c_fail failed"
    [[ "$c_fail" -eq 0 ]]
}

main "$@"
