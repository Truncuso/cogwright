#!/usr/bin/env bash
# goalforge-stage-report.test.sh — wp-07 b1, b4, b5, b6, b7.
#
# b1  every known-good validates and renders to <= 40 lines; every known-bad
#     exits 2; and a SABOTAGE arm that reverts goalforge-trace-emit `_validate`
#     to its pre-WP keyword subset turns the ref-shape and missing-ref
#     known-bads green — proving the validator, not this test, rejects them.
# b4  a seeded reader profile moves a seen id into assumed_known[]; the
#     no-profile tree renders the same item in full; the two renders differ.
# b5  one row per call, appended never rewritten; the two schema documents
#     agree field for field on the stage.report payload.
# b6  the nine-issue fixture renders <= 40 lines because the overflow rule
#     fires; an emitter with the budget removed renders 60-80.
# b7  a populated assumed_known[] never suppresses the next_gate ask.
#
# Hermetic: every arm runs in a mktemp git repo with HOME, GIT_CONFIG_GLOBAL,
# GIT_CONFIG_SYSTEM and GOALFORGE_READER set by this test. The checked-in
# evals/fixtures/ tree is only ever READ.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS="$(cd "$HERE/.." && pwd)"
PKG="$(cd "$SCRIPTS/.." && pwd)"
FX="$PKG/evals/fixtures/stage-report"
RFX="$PKG/evals/fixtures/reader"
REPORT="$SCRIPTS/goalforge-stage-report.sh"

PASS=0; FAIL=0
ok()  { echo "  PASS: $1"; PASS=$((PASS+1)); }
bad() { echo "  FAIL: $1"; FAIL=$((FAIL+1)); }
chk() { if [ "$2" = pass ]; then ok "$1"; else bad "$1"; fi; }

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
mkdir -p "$WORK/home"

mkrepo() {
  local d; d="$(mktemp -d "$WORK/repo.XXXXXX")"
  git -C "$d" init -q
  git -C "$d" config user.name Fixture
  git -C "$d" config user.email "fixture@example.com"
  echo "$d"
}
# Run a report script with the ambient environment fully replaced.
gfr() {  # gfr <script> <args...>
  local script="$1"; shift
  env -u GOALFORGE_READER HOME="$WORK/home" \
      GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null \
      GOALFORGE_READER=reader-fixture bash "$script" "$@"
}
# A copy of the package's scripts + references that a sabotage arm may edit.
mkcopy() {
  local d; d="$(mktemp -d "$WORK/copy.XXXXXX")"
  mkdir -p "$d/scripts"
  cp "$SCRIPTS/goalforge-stage-report.sh" "$SCRIPTS/goalforge-reader.sh" \
     "$SCRIPTS/goalforge-trace-emit" "$d/scripts/"
  cp -r "$PKG/references" "$d/references"
  echo "$d"
}

R="$(mkrepo)"

echo "=== goalforge-stage-report: b1 known-goods ==="

GOODS="good-spec:spec good-harden:harden good-execute:execute good-verify:verify good-path-heading:spec"
for pair in $GOODS; do
  f="${pair%%:*}"; st="${pair##*:}"
  OUT="$(gfr "$REPORT" "$st" wp-07 --json "$FX/$f.json" --repo "$R" 2>"$WORK/err")"; RC=$?
  N="$(printf '%s\n' "$OUT" | wc -l)"
  { [ "$RC" -eq 0 ] && [ "$N" -le 40 ]; } \
    && ok "known-good $f validates and renders in $N <= 40 lines" \
    || { bad "known-good $f (rc=$RC lines=$N)"; sed 's/^/        /' "$WORK/err"; }
done

echo "=== b1 known-bads (each must exit 2) ==="

BADS="bad-issue-no-ref:harden bad-ref-paraphrase:harden bad-ref-colon-heading:harden bad-missing-next-gate:harden bad-owner:harden bad-unknown-stage:bogus"
for pair in $BADS; do
  f="${pair%%:*}"; st="${pair##*:}"
  gfr "$REPORT" "$st" wp-07 --json "$FX/$f.json" --repo "$R" >/dev/null 2>&1; RC=$?
  [ "$RC" -eq 2 ] && ok "known-bad $f exits 2" || bad "known-bad $f exits 2 (got $RC)"
done

echo "=== b1 sabotage arm: revert _validate to its pre-WP keyword subset ==="
# Disables exactly the four keywords T1a added (pattern, items, minItems and
# type `array`). If the reverted validator still rejects these two known-bads,
# then something OTHER than the validator was rejecting them and the oracle is
# not load-bearing.
SAB="$(mkcopy)"
sed -i -e 's/"pattern" in schema/"pattern__reverted" in schema/' \
       -e 's/"items" in schema/"items__reverted" in schema/' \
       -e 's/"minItems" in schema/"minItems__reverted" in schema/' \
       -e 's/^    "array": list,$/    "array__reverted": list,/' \
       "$SAB/scripts/goalforge-trace-emit"
SAB_OK=pass
for f in bad-ref-paraphrase bad-issue-no-ref bad-ref-colon-heading; do
  gfr "$SAB/scripts/goalforge-stage-report.sh" harden wp-07 \
      --json "$FX/$f.json" --repo "$R" >/dev/null 2>&1; RC=$?
  # Exit 2 is the schema rejection. Under the reverted validator it must NOT
  # happen: whatever the script then does (render, or crash on the field the
  # schema no longer requires) is not a rejection.
  if [ "$RC" -eq 2 ]; then
    echo "        $f still REJECTED (exit 2) by the REVERTED validator"; SAB_OK=fail
  fi
done
chk "reverted validator no longer rejects the ref-shape and missing-ref known-bads" "$SAB_OK"

echo "=== b6 overflow rule ==="
N="$(gfr "$REPORT" harden wp-07 --json "$FX/nine-issues.json" --repo "$R" | wc -l)"
[ "$N" -le 40 ] && ok "nine-issue fixture renders in $N <= 40 lines" \
  || bad "nine-issue fixture renders $N lines (> 40)"
gfr "$REPORT" harden wp-07 --json "$FX/nine-issues.json" --repo "$R" \
  | grep -qE '^\- \+[0-9]+ more \(' \
  && ok "the overflow line fires and names the collapsed ids" \
  || bad "the overflow line fires and names the collapsed ids"

OVR="$(mkcopy)"
sed -i 's/^MAX_LINES = 40 /MAX_LINES = 100000 /' "$OVR/scripts/goalforge-stage-report.sh"
NB="$(gfr "$OVR/scripts/goalforge-stage-report.sh" harden wp-07 \
        --json "$FX/nine-issues.json" --repo "$R" | wc -l)"
{ [ "$NB" -ge 60 ] && [ "$NB" -le 80 ]; } \
  && ok "known-bad: budget removed renders $NB lines (60-80)" \
  || bad "known-bad: budget removed renders $NB lines (expected 60-80)"

echo "=== b7 assumed_known never suppresses the gate ==="
R7="$(mkrepo)"
mkdir -p "$R7/.memory/user/reader-fixture"
cp "$RFX/profile-seen.md" "$R7/.memory/user/reader-fixture/goalforge-communication-profile.md"
OUT7="$(gfr "$REPORT" harden wp-07 --json "$FX/assumed-known-gate.json" --repo "$R7")"
echo "$OUT7" | grep -q 'GATE-ASK-SENTINEL' && A=pass || A=fail
chk "the next_gate ask survives a populated assumed_known" "$A"
echo "$OUT7" | grep -q 'harden/SKILL.md#The' && A=pass || A=fail
chk "the next_gate ref survives a populated assumed_known" "$A"
echo "$OUT7" | grep -qE '^\- (wp-02|ticket-48) — already seen' && A=pass || A=fail
chk "seen ids moved into ## Assumed known" "$A"

GAT="$(mkcopy)"
sed -i 's|+ gate_block + known))|+ ([] if payload.get("assumed_known") else gate_block) + known))|' \
  "$GAT/scripts/goalforge-stage-report.sh"
gfr "$GAT/scripts/goalforge-stage-report.sh" harden wp-07 \
    --json "$FX/assumed-known-gate.json" --repo "$R7" | grep -q 'GATE-ASK-SENTINEL' \
  && bad "known-bad: an emitter that drops next_gate must lose the ask" \
  || ok "known-bad: an emitter that drops next_gate loses the ask"

echo "=== b4 reader profile changes the render ==="
RA="$(mkrepo)"; RB="$(mkrepo)"
mkdir -p "$RA/.memory/user/reader-fixture"
cp "$RFX/profile-seen.md" "$RA/.memory/user/reader-fixture/goalforge-communication-profile.md"
gfr "$REPORT" harden wp-07 --json "$RFX/report-cites-wp02.json" --repo "$RA" > "$WORK/with.txt"
gfr "$REPORT" harden wp-07 --json "$RFX/report-cites-wp02.json" --repo "$RB" > "$WORK/without.txt"
diff -q "$WORK/with.txt" "$WORK/without.txt" >/dev/null \
  && bad "profile-present and profile-absent renders must differ" \
  || ok "profile-present and profile-absent renders differ"
grep -q '^- wp-02 — already seen' "$WORK/with.txt" \
  && ok "with a profile: wp-02 is a one-line pointer under ## Assumed known" \
  || bad "with a profile: wp-02 is a one-line pointer under ## Assumed known"
grep -q 'option read wp-02 first' "$WORK/with.txt" \
  && bad "with a profile: the wp-02 item must not be expanded" \
  || ok "with a profile: the wp-02 item is not expanded"
grep -q 'option read wp-02 first' "$WORK/without.txt" \
  && ok "without a profile: the same item renders in full" \
  || bad "without a profile: the same item renders in full"

echo "=== b5 one row per call, appended, and the two schemas agree ==="
FEAT="$RA/plans/afeature"; mkdir -p "$FEAT"
gfr "$REPORT" harden wp-07 --json "$FX/good-harden.json" --repo "$RA" \
    --feature-dir "$FEAT" >/dev/null
N1="$(grep -c '"type":"stage.report"' "$FEAT/trace-events.jsonl")"
HEAD_BEFORE="$(head -n 1 "$FEAT/trace-events.jsonl" | sha256sum | cut -d' ' -f1)"
gfr "$REPORT" harden wp-07 --json "$FX/good-execute.json" --repo "$RA" \
    --feature-dir "$FEAT" >/dev/null
N2="$(grep -c '"type":"stage.report"' "$FEAT/trace-events.jsonl")"
HEAD_AFTER="$(head -n 1 "$FEAT/trace-events.jsonl" | sha256sum | cut -d' ' -f1)"
{ [ "$N1" -eq 1 ] && [ "$N2" -eq 2 ]; } \
  && ok "exactly one stage.report row per call" \
  || bad "exactly one stage.report row per call (got $N1 then $N2)"
[ "$HEAD_AFTER" = "$HEAD_BEFORE" ] \
  && ok "rows are appended, never rewritten" \
  || bad "rows are appended, never rewritten"

# The payload schema (the goalforge-viz seam) and the stage.report branch of
# the trace ENVELOPE schema must carry the same payload fields, with the same
# subschemas and the same required set. A fork between them is a failure.
cat > "$WORK/schemas.py" <<'PY'
import json, sys
from pathlib import Path
pkg = Path(sys.argv[1])
payload = json.loads((pkg / "references/schema/stage-report.schema.json")
                     .read_text(encoding="utf-8"))
lines = (pkg / "references/trace-events.md").read_text(encoding="utf-8").split("\n")
i = lines.index("```json")
j = lines.index("```", i + 1)
env = json.loads("\n".join(lines[i + 1:j]))
branch = next(b for b in env["oneOf"]
              if b["properties"]["type"].get("const") == "stage.report")
ENVELOPE = {"type", "seq", "ts", "schema_version"}
ATTR = {"actor", "mode", "override", "session", "model", "provider", "agent",
        "decision_ref"}


def strip(o):
    if isinstance(o, dict):
        return {k: strip(v) for k, v in o.items() if k != "description"}
    if isinstance(o, list):
        return [strip(x) for x in o]
    return o


a = strip({k: v for k, v in payload["properties"].items()})
b = strip({k: v for k, v in branch["properties"].items()
           if k not in ENVELOPE | ATTR})
rc = 0
if set(a) != set(b):
    print("payload-only:", sorted(set(a) - set(b)))
    print("envelope-only:", sorted(set(b) - set(a)))
    rc = 1
for k in sorted(set(a) & set(b)):
    if a[k] != b[k]:
        print("subschema differs for field:", k)
        rc = 1
if set(payload["required"]) != set(branch["required"]) - {"type"}:
    print("required set differs:",
          set(payload["required"]) ^ (set(branch["required"]) - {"type"}))
    rc = 1
sys.exit(rc)
PY
python3 "$WORK/schemas.py" "$PKG" >"$WORK/schemas.out" 2>&1 && A=pass || A=fail
chk "the two schema documents agree field for field on the payload" "$A"
[ "$A" = fail ] && sed 's/^/        /' "$WORK/schemas.out"

FORK="$(mkcopy)"
sed -i '/"assumed_known": { "type": "array", "items": { "type": "string" } },/d' \
  "$FORK/references/trace-events.md"
python3 "$WORK/schemas.py" "$FORK" >/dev/null 2>&1 \
  && bad "known-bad: a forked envelope branch must fail the field-for-field check" \
  || ok "known-bad: a forked envelope branch fails the field-for-field check"

# b5: the event roster in the trace-substrate suite carries stage.report.
grep -q '"stage.report"' "$PKG/evals/trace-substrate/run.sh" \
  && ok "trace-substrate case (e) roster names stage.report" \
  || bad "trace-substrate case (e) roster names stage.report"
grep -q '"type":"stage.report"' "$PKG/evals/trace-substrate/fixtures/all-events.jsonl" \
  && ok "trace-substrate fixture carries a stage.report row" \
  || bad "trace-substrate fixture carries a stage.report row"

# b5: the two prose homes document the event and the C8 field schema, with
# content assertions rather than an existence grep that an empty stub passes.
grep -q '^### `stage.report`$' "$PKG/references/trace-events.md" \
  && ok "trace-events.md documents the stage.report event" \
  || bad "trace-events.md documents the stage.report event"
RP="$PKG/references/reader-profile.md"
RP_OK=pass
for field in 'seen\[\]' 'explained_terms\[\]' 'depth' 'register' 'GOALFORGE_READER' \
             'goalforge.yaml' 'anonymous'; do
  grep -qE "$field" "$RP" || { echo "        reader-profile.md never names $field"; RP_OK=fail; }
done
chk "reader-profile.md documents every C8 field and ladder rung" "$RP_OK"

echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
