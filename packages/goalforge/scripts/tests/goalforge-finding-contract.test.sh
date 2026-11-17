#!/usr/bin/env bash
# goalforge-finding-contract.test.sh — references/schema/finding.schema.json.
#
# Validates through goalforge-trace-emit `_validate` (the package's one
# validator, same mechanism as goalforge-stage-report). The two worked examples
# are read out of references/finding-contract.md, so the doc and the schema
# cannot drift apart. Negative cases are mutations of those examples.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PKG="$(cd "$HERE/../.." && pwd)"
SCHEMA="${FINDING_SCHEMA:-$PKG/references/schema/finding.schema.json}"
DOC="$PKG/references/finding-contract.md"
EMIT="$PKG/scripts/goalforge-trace-emit"

PASS=0; FAIL=0
ok()  { echo "  PASS: $1"; PASS=$((PASS+1)); }
bad() { echo "  FAIL: $1"; FAIL=$((FAIL+1)); }

# check <name> <expect: valid|invalid> <python expr on dicts det, model>
check() {
  local out
  out="$(python3 -I - "$SCHEMA" "$DOC" "$EMIT" "$3" <<'PY'
import copy, importlib.util, json, re, sys
from importlib.machinery import SourceFileLoader
schema_p, doc_p, emit_p, expr = sys.argv[1:5]
loader = SourceFileLoader("emit", emit_p)
emit = importlib.util.module_from_spec(importlib.util.spec_from_loader("emit", loader))
loader.exec_module(emit)
schema = json.load(open(schema_p))
blocks = re.findall(r"```json\n(.*?)\n```", open(doc_p).read(), re.S)
det, model = json.loads(blocks[0]), json.loads(blocks[1])
inst = eval(expr, {"copy": copy, "det": det, "model": model})
errs = emit._validate(inst, schema)
print("valid" if not errs else "invalid: " + "; ".join(errs))
PY
)"
  if [ "${out%%:*}" = "$2" ]; then ok "$1 ($out)"; else bad "$1 (expected $2, got: $out)"; fi
}

echo "=== goalforge-finding-contract: worked examples ==="
check "deterministic taint example validates"  valid   'det'
check "model N+1 example validates"            valid   'model'
check "reserved names admitted, loosely typed" valid   '{**model, "suppression": {"kind": "inSource"}, "baseline_state": "new", "route_to": "fixer"}'

echo "=== negative cases ==="
check "deterministic without fingerprint fails"   invalid '{k: v for k, v in det.items() if k != "fingerprint"}'
check "deterministic taint without trace fails"   invalid '{k: v for k, v in det.items() if k != "trace"}'
check "deterministic path without trace fails"    invalid '{**{k: v for k, v in det.items() if k != "trace"}, "analysis_kind": "path"}'
check "deterministic pattern without trace valid" valid   '{**{k: v for k, v in det.items() if k != "trace"}, "analysis_kind": "pattern"}'
check "model without why_it_matters fails"        invalid '{k: v for k, v in model.items() if k != "why_it_matters"}'
check "bad severity enum fails"                   invalid '{**det, "severity": "BLOCKER"}'
check "unknown extra field fails"                 invalid '{**det, "extra": 1}'
check "producer.kind outside enum fails"         invalid '{**det, "producer": {"name": "x", "kind": "tool"}}'
check "analysis_kind outside enum fails"         invalid '{**det, "analysis_kind": "vibes"}'
check "missing what fails"                       invalid '{k: v for k, v in det.items() if k != "what"}'
check "schema_version 2 fails"                   invalid '{**det, "schema_version": 2}'
check "extra key in location fails"              invalid '{**det, "location": {**det["location"], "col": 3}}'
check "extra key in trace item fails"            invalid '{**det, "trace": [{**det["trace"][0], "col": 3}]}'
check "start_line 0 fails"                       invalid '{**det, "location": {"file": "a.py", "start_line": 0}}'
check "trace not an array of locations fails"    invalid '{**det, "trace": "app/routes.py:18"}'
check "trace items not locations fail"           invalid '{**det, "trace": ["app/routes.py:18"]}'
check "confidence outside enum fails"            invalid '{**det, "confidence": "certain"}'
check "model taint without trace valid"          valid   '{**model, "analysis_kind": "taint"}'

echo "=== Results: $PASS passed, $FAIL failed ==="
[ "$FAIL" -eq 0 ]
