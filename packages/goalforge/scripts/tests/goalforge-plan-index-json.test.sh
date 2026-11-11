#!/usr/bin/env bash
# goalforge-plan-index-json.test.sh — b15 (L0-11): the plan-index JSON generator
# models the WP `## Checklist`, not retired task-*.md files.
#
# Drives the REAL goalforge-plan-index-json over a throwaway mktemp plans root
# (never a live plans/ tree). Expected values are hand-written below.
#
#   b15 WP      : two checklist items -> tasks [T1 done, T2 pending], key set
#                 {id, status, task_route}, task_route ""; a stray task-01-old.md
#                 adds no entry.
#   [X] WP      : an upper-case check mark gives status done.
#   empty WPs   : no `## Checklist` heading, and a heading with only a non-item
#                 line, both give tasks [].
#   determinism : two runs are byte-identical; schema_version is 1.
#   self-test   : --self-test exits 0 and, observed at runtime by an audit hook,
#                 opens no task-*.md file for writing.
#   agreement   : the compiler's parse_checklist and the generator read the same
#                 ids in the same order from one shared fixture.
set -uo pipefail

SD="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GEN="$SD/../goalforge-plan-index-json"
COMPILER="$SD/../goalforge-workflow-compile.py"
PASS=0; FAIL=0

ok()  { echo "  PASS: $1"; PASS=$((PASS+1)); }
bad() { echo "  FAIL: $1"; FAIL=$((FAIL+1)); }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
export HOME="$TMP/home"; mkdir -p "$HOME"
export PYTHONDONTWRITEBYTECODE=1

ROOT="$TMP/plans"
FEAT="$ROOT/tmpfeat"
mkdir -p "$FEAT"
cat > "$FEAT/overview.md" <<'EOF'
---
name: tmpfeat
feature: tmpfeat
status: ready
route: standard
---

# feat
EOF

mk_wp() { # $1=wp-dir-name ; body on stdin
    mkdir -p "$FEAT/$1"
    {
        printf -- '---\nname: %s\ntitle: fixture\nstatus: ready\nschema_version: 6\nseverity: LOW\nparallel: false\ndepends_on: []\nplan: tmpfeat\ntask_type: code\n---\n\n' "$1"
        cat
    } > "$FEAT/$1/overview.md"
}

mk_wp wp-01-two <<'EOF'
## Checklist

- [x] T1 ... {files: a.sh} [b1]
- [ ] T2 ... {files: b.sh} [b2]
EOF
cat > "$FEAT/wp-01-two/task-01-old.md" <<'EOF'
---
name: task-01-old
status: done
route: api
---
EOF

mk_wp wp-02-nohead <<'EOF'
## Goal

nothing to do
EOF

mk_wp wp-03-noitem <<'EOF'
## Checklist

Nothing here yet.
EOF

mk_wp wp-04-upper <<'EOF'
## Checklist

- [X] T1 ... {files: c.sh} [b3]
EOF

echo "=== goalforge-plan-index-json.test.sh ==="

OUT1="$TMP/run1.json"; OUT2="$TMP/run2.json"
python3 "$GEN" --plans-root "$ROOT" -o - > "$OUT1" 2>"$TMP/err1"; rc1=$?
python3 "$GEN" --plans-root "$ROOT" -o - > "$OUT2" 2>"$TMP/err2"; rc2=$?
if [ "$rc1" -eq 0 ] && [ "$rc2" -eq 0 ]; then ok "two runs exit 0"; else bad "two runs exit 0 (rc $rc1/$rc2: $(cat "$TMP/err1"))"; fi
if cmp -s "$OUT1" "$OUT2"; then ok "two runs byte-identical"; else bad "two runs byte-identical"; fi

check_json() { # $1=label $2=python expression over idx/wps
    if python3 - "$OUT1" "$2" <<'PY' 2>/dev/null
import json, sys
idx = json.load(open(sys.argv[1], encoding="utf-8"))
wps = {w["id"]: w for w in idx["features"][0]["wps"]}
sys.exit(0 if eval(sys.argv[2]) else 1)
PY
    then ok "$1"; else bad "$1"; fi
}

check_json "schema_version is 1" 'idx["schema_version"] == 1'
check_json "b15 WP tasks are T1 done, T2 pending, task_route empty (stray file adds nothing)" \
  'wps["wp-01-two"]["tasks"] == [{"id": "T1", "status": "done", "task_route": ""}, {"id": "T2", "status": "pending", "task_route": ""}]'
check_json "every task entry has exactly the keys id, status, task_route" \
  'all(set(t) == {"id", "status", "task_route"} for w in wps.values() for t in w["tasks"])'
check_json "[X] item gives status done" \
  'wps["wp-04-upper"]["tasks"] == [{"id": "T1", "status": "done", "task_route": ""}]'
check_json "WP without a Checklist heading has tasks []" 'wps["wp-02-nohead"]["tasks"] == []'
check_json "WP with a Checklist heading and no item has tasks []" 'wps["wp-03-noitem"]["tasks"] == []'
check_json "WP and feature key sets unchanged" \
  'set(idx) == {"schema_version", "generated_from", "features"} and set(idx["features"][0]) == {"name", "status", "route", "wps"} and all(set(w) == {"id", "status", "depends_on", "goal_digest", "tasks"} for w in wps.values())'

# --self-test: exit 0, and no write-mode open of a task-*.md basename, observed
# at runtime by an audit hook (the self-test's temp dir is gone after the run).
python3 - "$GEN" > "$TMP/selftest.out" 2>&1 <<'PY'
import importlib.machinery, importlib.util, os, sys
sys.dont_write_bytecode = True
gen = sys.argv[1]
hits = []
WRITE_FLAGS = os.O_WRONLY | os.O_RDWR | os.O_CREAT | os.O_APPEND | os.O_TRUNC

def hook(event, args):
    if event != "open" or not args or not isinstance(args[0], (str, bytes, os.PathLike)):
        return
    base = os.path.basename(os.fsdecode(args[0]))
    if not (base.startswith("task-") and base.endswith(".md")):
        return
    mode, flags = args[1], args[2]
    writing = (isinstance(mode, str) and any(c in mode for c in "wax+")) or (
        mode is None and isinstance(flags, int) and flags & WRITE_FLAGS)
    if writing:
        hits.append(base)
        raise PermissionError(f"self-test wrote {base}")

sys.addaudithook(hook)
loader = importlib.machinery.SourceFileLoader("_plan_index_json", gen)
spec = importlib.util.spec_from_loader("_plan_index_json", loader)
mod = importlib.util.module_from_spec(spec)
loader.exec_module(mod)
try:
    rc = mod.main(["--self-test"])
except PermissionError as e:
    print(e)
    rc = 99
print(f"SELFTEST_RC={rc} TASK_WRITES={len(hits)}")
sys.exit(0 if rc == 0 and not hits else 1)
PY
if [ $? -eq 0 ]; then ok "--self-test exits 0 and writes no task-*.md file"; else bad "--self-test exits 0 and writes no task-*.md file ($(tail -1 "$TMP/selftest.out"))"; fi

# agreement: compiler parse_checklist and generator agree on ids, in order.
AGREE="$TMP/agree/feat"
mkdir -p "$AGREE/wp-01-agree"
printf -- '---\nname: feat\nfeature: feat\nstatus: ready\nroute: standard\n---\n' > "$AGREE/overview.md"
cat > "$AGREE/wp-01-agree/overview.md" <<'EOF'
---
name: wp-01-agree
status: ready
depends_on: []
---

## Checklist

- [ ] T1 first {files: a.sh} [b1]
- [ ] T2 no files block here [b2]
- [X] T3 upper mark {files: c.sh}
    - [ ] T4 indented {files: d.sh} [b4]

## Notes

- [ ] T5 after a later heading {files: e.sh} [b5]
EOF
python3 - "$COMPILER" "$GEN" "$AGREE" > "$TMP/agree.out" 2>&1 <<'PY'
import importlib.machinery, importlib.util, json, sys
from pathlib import Path
sys.dont_write_bytecode = True
compiler, gen, feat = sys.argv[1], sys.argv[2], Path(sys.argv[3])

def load(name, path):
    loader = importlib.machinery.SourceFileLoader(name, path)
    spec = importlib.util.spec_from_loader(name, loader)
    mod = importlib.util.module_from_spec(spec)
    sys.modules[name] = mod
    loader.exec_module(mod)
    return mod

comp = load("_wf_compile", compiler)
text = (feat / "wp-01-agree" / "overview.md").read_text(encoding="utf-8")
comp_ids = [i.id for i in comp.parse_checklist(text)]
g = load("_plan_index_json", gen)
gen_ids = [t["id"] for t in g.build_index(feat.parent)["features"][0]["wps"][0]["tasks"]]
expected = ["T1", "T3", "T4"]
print(f"compiler={comp_ids} generator={gen_ids}")
sys.exit(0 if comp_ids == gen_ids == expected else 1)
PY
if [ $? -eq 0 ]; then ok "compiler and generator agree on checklist ids"; else bad "compiler and generator agree on checklist ids ($(tail -1 "$TMP/agree.out"))"; fi

echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
