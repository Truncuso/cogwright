#!/usr/bin/env bash
# evals/trace-substrate/cases/legacy-derivation.sh — task-04 hermetic case (c).
#
# Proves goalforge-trace-derive projects a legacy .sdd-transitions.jsonl into
# schema-conformant trace events, read-only over the ledger and byte-idempotent.
# Self-contained: builds a scratch feature with a real-shaped legacy ledger
# containing ONLY WP-level and feature-level rows (NO fabricated task-level rows —
# the ledger has no task-level source), and asserts:
#   - stdout projection covers wp.status_changed AND feature.status_changed
#   - commit.linked is derived for rows carrying a commit
#   - feature rows are classified by feature-dir basename match
#   - running derivation twice yields byte-identical stdout (deterministic)
#   - the legacy ledger is never modified
#   - --write feeds rows through the emitter → every appended row is schema-valid,
#     seq is contiguous, and a second --write is a byte-identical no-op
#
# Standalone — the unit's run.sh (task-05) aggregates cases; this does NOT depend
# on it. Exit 0 = pass, non-zero = fail.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS="$(cd "$HERE/../../../scripts" && pwd)"
DERIVE="$SCRIPTS/goalforge-trace-derive"
EMIT="$SCRIPTS/goalforge-trace-emit"

t_pass=0; t_fail=0
ok() { echo "  PASS: $1"; t_pass=$((t_pass+1)); }
no() { echo "  FAIL: $1"; t_fail=$((t_fail+1)); }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

FEAT="$TMP/plans/myfeat"
mkdir -p "$FEAT"
LEDGER="$FEAT/.sdd-transitions.jsonl"

# Real-shaped legacy ledger: WP-level + feature-level rows only.
cat > "$LEDGER" <<'EOF'
{"ts": "2026-07-01T00:00:00Z", "wp": "wp-01-a", "from": "spec", "to": "hardened", "reason": "harden", "actor": "goalforge-harden", "override": false, "commit": "abc1234", "mode": "auto", "session": "s1", "model": "opus", "provider": "anthropic", "agent": "", "decision_ref": "findings.md"}
{"ts": "2026-07-02T00:00:00Z", "wp": "myfeat", "from": "ready", "to": "executing", "reason": "exec entry", "actor": "goalforge-execute", "override": false, "commit": "", "mode": "auto", "session": "s1", "model": "opus", "provider": "anthropic", "agent": "", "decision_ref": ""}
{"ts": "2026-07-03T00:00:00Z", "wp": "wp-02-b", "from": "ready", "to": "executing", "reason": "", "actor": "goalforge-execute", "override": false, "commit": "def5678", "mode": "auto", "session": "s1", "model": "opus", "provider": "anthropic", "agent": "", "decision_ref": ""}
EOF

echo "=== legacy-derivation case (c) ==="

LEDGER_SHA_BEFORE="$(sha256sum "$LEDGER" | cut -d' ' -f1)"

# ── deterministic stdout: run twice → byte-identical ──────────────────────────
OUT1="$(python3 "$DERIVE" "$FEAT")"
OUT2="$(python3 "$DERIVE" "$FEAT")"
if [[ "$OUT1" == "$OUT2" ]]; then
    ok "stdout projection byte-identical across two runs"
else
    no "stdout projection should be byte-identical across runs"
fi

# ── coverage: both status types + commit.linked present ───────────────────────
if grep -q '"type":"wp.status_changed"' <<<"$OUT1"; then
    ok "wp.status_changed derived"
else
    no "wp.status_changed should be derived"
fi
if grep -q '"type":"feature.status_changed"' <<<"$OUT1"; then
    ok "feature.status_changed derived (feature-dir basename match)"
else
    no "feature.status_changed should be derived"
fi
if [[ "$(grep -c '"type":"commit.linked"' <<<"$OUT1")" -eq 2 ]]; then
    ok "commit.linked derived once per commit-bearing ledger row (2)"
else
    no "commit.linked should be derived for each commit-bearing row (expected 2)"
fi

# ── feature classification: the 'myfeat' row is the ONLY feature row ───────────
FEAT_COUNT="$(grep -c '"type":"feature.status_changed"' <<<"$OUT1" || true)"
if [[ "$FEAT_COUNT" -eq 1 ]] && grep -q '"type":"feature.status_changed","schema_version":1,"derived":true,"wp":"myfeat"' <<<"$OUT1"; then
    ok "exactly one feature row, classified by basename (wp==myfeat)"
else
    no "feature classification wrong (count=$FEAT_COUNT)"
fi

# ── read-only: legacy ledger untouched ────────────────────────────────────────
LEDGER_SHA_AFTER="$(sha256sum "$LEDGER" | cut -d' ' -f1)"
if [[ "$LEDGER_SHA_BEFORE" == "$LEDGER_SHA_AFTER" ]]; then
    ok "legacy ledger never modified"
else
    no "legacy ledger must not be modified"
fi

# ── --write: every appended row validates against the embedded schema ─────────
python3 "$DERIVE" "$FEAT" --write >/dev/null 2>&1
LOG="$FEAT/trace-events.jsonl"
_validate_log() {
    python3 - "$EMIT" "$LOG" <<'PY'
import sys, json
from importlib.machinery import SourceFileLoader
mod = SourceFileLoader("emit", sys.argv[1]).load_module()
schema = mod.load_schema()
rows = [json.loads(ln) for ln in open(sys.argv[2], encoding="utf-8") if ln.strip()]
bad = [r for r in rows if mod._validate(r, schema)]
if bad:
    print("invalid:", bad[:1]); sys.exit(1)
seqs = [r["seq"] for r in rows]
if seqs != list(range(len(seqs))):
    print("non-contiguous seq:", seqs); sys.exit(1)
sys.exit(0)
PY
}
if [[ -f "$LOG" ]] && _validate_log; then
    ok "--write: every appended row schema-valid, seq contiguous"
else
    no "--write: appended rows should be schema-valid with contiguous seq"
fi

# ── --write: appended rows carry the VERBATIM ledger ts (not derivation-time) ──
_verbatim_ts() {
    python3 - "$LOG" <<'PY'
import sys, json
allowed = {"2026-07-01T00:00:00Z", "2026-07-02T00:00:00Z", "2026-07-03T00:00:00Z"}
rows = [json.loads(l) for l in open(sys.argv[1], encoding="utf-8") if l.strip()]
sys.exit(0 if rows and all(r.get("ts") in allowed for r in rows) else 1)
PY
}
if _verbatim_ts; then
    ok "--write: appended rows carry verbatim ledger ts (not derivation-time)"
else
    no "--write: appended rows must carry verbatim ledger ts (not derivation-time)"
fi

# ── --write idempotent: second run is a byte-identical no-op ───────────────────
LOG_SHA_1="$(sha256sum "$LOG" | cut -d' ' -f1)"
python3 "$DERIVE" "$FEAT" --write >/dev/null 2>&1
LOG_SHA_2="$(sha256sum "$LOG" | cut -d' ' -f1)"
if [[ "$LOG_SHA_1" == "$LOG_SHA_2" ]]; then
    ok "--write idempotent (sentinel → byte-identical log)"
else
    no "--write should be idempotent (sentinel-bounded)"
fi

echo ""
echo "Results: $t_pass passed, $t_fail failed"
[[ "$t_fail" -eq 0 ]]
