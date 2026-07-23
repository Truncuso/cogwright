#!/usr/bin/env bash
# goalforge-wp-complexity.sh — classify a work-package as complex or simple.
#
# Usage:
#   goalforge-wp-complexity.sh <wp-path>
#   goalforge-wp-complexity.sh --self-test
#
# Args:
#   <wp-path>  Work-package directory containing overview.md and task-*.md.
#              Must live inside a feature dir (parent of <wp-path>).
#
# Output:
#   Single-line JSON:
#   {"verdict":"complex"|"simple","tripped":["S1",...],"signals":{...}}
#
#   Verdict is complex when ANY signal trips:
#     S1  severity in overview.md frontmatter is HIGH or CRITICAL
#     S2  decision-list items under ## Decisions >= SDD_CPLX_ND (default 3)
#     S3  distinct touched files across task verify/steps >= SDD_CPLX_NF (default 5)
#     S4  task-score (complexity weights + depends_on edges) >= SDD_CPLX_NT (default 4)
#     S5  cross-WP contract: author-declared `cross_wp_contract: true` flag
#         (top-level frontmatter, or under goal:) — set at harden, not inferred
#
#   Exit 0 on success (verdict in JSON). Exit 1 on errors (stderr).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SELF="$SCRIPT_DIR/$(basename "${BASH_SOURCE[0]}")"

usage() {
    sed -n '2,23p' "$SELF" | sed 's/^# \{0,1\}//'
}

# ── Classify WP ───────────────────────────────────────────────────────────────
classify_wp() {
    python3 - "$1" <<'PY'
import sys, re, json, os
from pathlib import Path
try:
    import yaml
except ImportError:
    sys.stderr.write("ERROR: PyYAML not available (pip3 install pyyaml)\n"); sys.exit(1)

wp_path = Path(sys.argv[1])

nd = int(os.environ.get("SDD_CPLX_ND", "3"))
nf = int(os.environ.get("SDD_CPLX_NF", "5"))
nt = int(os.environ.get("SDD_CPLX_NT", "4"))

overview = wp_path / "overview.md"
if not overview.exists():
    sys.stderr.write("ERROR: overview.md not found in %s\n" % wp_path); sys.exit(1)

def parse_fm_and_body(path):
    try:
        text = path.read_text(encoding="utf-8")
    except OSError as e:
        sys.stderr.write("ERROR: cannot read %s: %s\n" % (path, e)); sys.exit(1)
    lines = text.split("\n")
    if not lines or lines[0].strip() != "---":
        return {}, text
    end = None
    for i in range(1, len(lines)):
        if lines[i].strip() == "---":
            end = i; break
    if end is None:
        return {}, text
    try:
        fm = yaml.safe_load("\n".join(lines[1:end]))
    except Exception:
        fm = {}
    body = "\n".join(lines[end + 1:])
    return (fm if isinstance(fm, dict) else {}), body

ov_fm, ov_body = parse_fm_and_body(overview)

# S1: severity HIGH or CRITICAL
sev_raw = str(ov_fm.get("severity") or "").strip()
s1 = sev_raw.upper() in ("HIGH", "CRITICAL")

# S2: count '- ' items under ## Decisions (until next ## or EOF)
def count_decisions(body):
    count = 0
    in_sec = False
    for line in body.split("\n"):
        if re.match(r"^## Decisions\s*$", line):
            in_sec = True
            continue
        if in_sec:
            if re.match(r"^## ", line):
                break
            if line.startswith("- "):
                count += 1
    return count

decisions = count_decisions(ov_body)
s2 = decisions >= nd

# S3: distinct file tokens in task verify frontmatter + ## Steps sections
FILE_RE = re.compile(r"[\w./-]+\.(?:sh|py|md|ts|js|rs|yaml|yml|json|sql)")

def extract_files(task_path):
    fm, body = parse_fm_and_body(task_path)
    tokens = set()
    verify = fm.get("verify")
    if verify is not None:
        vs = verify if isinstance(verify, str) else json.dumps(verify)
        tokens.update(FILE_RE.findall(vs))
    in_steps = False
    for line in body.split("\n"):
        if re.match(r"^## Steps\s*$", line):
            in_steps = True
            continue
        if in_steps:
            if re.match(r"^## ", line):
                break
            tokens.update(FILE_RE.findall(line))
    return tokens

task_files = sorted(wp_path.glob("task-*.md"))
all_files = set()
for tf in task_files:
    all_files.update(extract_files(tf))

touched_files = len(all_files)
s3 = touched_files >= nf

# S4: task score = sum of complexity weights + inter-task depends_on edges
CPLX_SCORE = {"high": 2, "medium": 1}
task_slugs = {tf.stem for tf in task_files}
task_score = 0
for tf in task_files:
    fm, _ = parse_fm_and_body(tf)
    cplx = str(fm.get("complexity") or "").strip().lower()
    task_score += CPLX_SCORE.get(cplx, 0)
    deps = fm.get("depends_on") or []
    if isinstance(deps, list):
        for dep in deps:
            if str(dep).strip() in task_slugs:
                task_score += 1

s4 = task_score >= nt

# S5: cross-WP contract — AUTHOR-DECLARED flag, set at harden when a WP shares an
# owned file/section contract with another WP (e.g. wp-05 & wp-06 co-edit goalforge-harden
# Step 0). Deterministic and intentional — boundary-glob overlap is too noisy to
# infer it (a common workspace like goalforge/scripts/** is shared by nearly every WP).
# Read top-level first (sibling to severity, no goal-hash churn), then goal: fallback.
def truthy(v):
    return str(v).strip().lower() in ("true", "yes", "1") if v is not None else False

_goal_fm = ov_fm.get("goal") if isinstance(ov_fm.get("goal"), dict) else {}
cross_wp = truthy(ov_fm.get("cross_wp_contract")) or truthy(_goal_fm.get("cross_wp_contract"))

s5 = cross_wp

tripped = [s for s, hit in [("S1", s1), ("S2", s2), ("S3", s3), ("S4", s4), ("S5", s5)] if hit]
verdict = "complex" if tripped else "simple"

print(json.dumps({
    "verdict": verdict,
    "tripped": tripped,
    "signals": {
        "severity": sev_raw,
        "decisions": decisions,
        "touched_files": touched_files,
        "task_score": task_score,
        "cross_wp": cross_wp,
    },
}))
PY
}

# ── Self-test ─────────────────────────────────────────────────────────────────
_ST_TMP=""
self_test() {
    local t_pass=0 t_fail=0 d

    _ST_TMP="$(mktemp -d)"
    trap '[[ -n "${_ST_TMP:-}" ]] && rm -rf "$_ST_TMP"' EXIT
    d="$_ST_TMP"

    local ok no
    ok() { echo "$1: PASS"; t_pass=$((t_pass+1)); }
    no() { echo "$1: FAIL — $2"; t_fail=$((t_fail+1)); }

    # mk_ov <wp-dir> <severity>   — write overview.md with empty boundaries
    mk_ov() {
        local _dir="$1" _sev="$2"
        mkdir -p "$_dir"
        cat > "$_dir/overview.md" << EOF
---
severity: $_sev
boundaries: []
---
EOF
    }

    # mk_task <wp-dir> <slug> <complexity> <depends_on-yaml>
    mk_task() {
        local _dir="$1" _sl="$2" _cplx="$3" _deps="$4"
        cat > "$_dir/$_sl.md" << EOF
---
complexity: $_cplx
depends_on: $_deps
---
EOF
    }

    echo "=== goalforge-wp-complexity.sh --self-test ==="

    # ── F1: S1 only — severity HIGH ───────────────────────────────────────────
    mk_ov "$d/feat-f1/wp-01-f1" HIGH
    local out1 v1 tr1
    out1="$(bash "$SELF" "$d/feat-f1/wp-01-f1")"
    v1="$(echo "$out1"  | command jq -r '.verdict')"
    tr1="$(echo "$out1" | command jq -c '.tripped')"
    if [[ "$v1" == "complex" && "$tr1" == '["S1"]' ]]; then
        ok "F1-severity"
    else
        no "F1-severity" "verdict=$v1 tripped=$tr1"
    fi

    # ── F2: S2 only — 3 decision items ────────────────────────────────────────
    mk_ov "$d/feat-f2/wp-01-f2" LOW
    cat >> "$d/feat-f2/wp-01-f2/overview.md" << 'EOF'

## Decisions
- item one
- item two
- item three
EOF
    local out2 v2 tr2
    out2="$(bash "$SELF" "$d/feat-f2/wp-01-f2")"
    v2="$(echo "$out2"  | command jq -r '.verdict')"
    tr2="$(echo "$out2" | command jq -c '.tripped')"
    if [[ "$v2" == "complex" && "$tr2" == '["S2"]' ]]; then
        ok "F2-decisions"
    else
        no "F2-decisions" "verdict=$v2 tripped=$tr2"
    fi

    # ── F3: S3 only — 5 distinct files in task steps ──────────────────────────
    mk_ov "$d/feat-f3/wp-01-f3" LOW
    cat > "$d/feat-f3/wp-01-f3/task-01-f3.md" << 'EOF'
---
complexity: low
depends_on: []
---

## Steps

Run deploy.sh and convert.py. Edit settings.yaml and schema.json. Update CHANGELOG.md.
EOF
    local out3 v3 tr3
    out3="$(bash "$SELF" "$d/feat-f3/wp-01-f3")"
    v3="$(echo "$out3"  | command jq -r '.verdict')"
    tr3="$(echo "$out3" | command jq -c '.tripped')"
    if [[ "$v3" == "complex" && "$tr3" == '["S3"]' ]]; then
        ok "F3-touched-files"
    else
        no "F3-touched-files" "verdict=$v3 tripped=$tr3"
    fi

    # ── F4: S4 only — two high tasks (score=4, threshold=4) ───────────────────
    mk_ov "$d/feat-f4/wp-01-f4" LOW
    mk_task "$d/feat-f4/wp-01-f4" task-01-f4 high "[]"
    mk_task "$d/feat-f4/wp-01-f4" task-02-f4 high "[]"
    local out4 v4 tr4
    out4="$(bash "$SELF" "$d/feat-f4/wp-01-f4")"
    v4="$(echo "$out4"  | command jq -r '.verdict')"
    tr4="$(echo "$out4" | command jq -c '.tripped')"
    if [[ "$v4" == "complex" && "$tr4" == '["S4"]' ]]; then
        ok "F4-task-score"
    else
        no "F4-task-score" "verdict=$v4 tripped=$tr4"
    fi

    # ── F5: S5 only — author-declared cross_wp_contract flag (top-level) ───────
    mkdir -p "$d/feat-f5/wp-01-f5"
    cat > "$d/feat-f5/wp-01-f5/overview.md" << 'EOF'
---
severity: LOW
cross_wp_contract: true
---
EOF
    local out5 v5 tr5
    out5="$(bash "$SELF" "$d/feat-f5/wp-01-f5")"
    v5="$(echo "$out5"  | command jq -r '.verdict')"
    tr5="$(echo "$out5" | command jq -c '.tripped')"
    if [[ "$v5" == "complex" && "$tr5" == '["S5"]' ]]; then
        ok "F5-cross-wp-flag"
    else
        no "F5-cross-wp-flag" "verdict=$v5 tripped=$tr5"
    fi

    # ── F5b: flag under goal: also honored ────────────────────────────────────
    mkdir -p "$d/feat-f5b/wp-01-f5b"
    cat > "$d/feat-f5b/wp-01-f5b/overview.md" << 'EOF'
---
severity: LOW
goal:
  cross_wp_contract: true
---
EOF
    local v5b
    v5b="$(bash "$SELF" "$d/feat-f5b/wp-01-f5b" | command jq -r '.verdict')"
    if [[ "$v5b" == "complex" ]]; then
        ok "F5b-cross-wp-flag-goal"
    else
        no "F5b-cross-wp-flag-goal" "verdict=$v5b"
    fi

    # ── F6: simple — no signal trips ──────────────────────────────────────────
    mk_ov "$d/feat-f6/wp-01-f6" LOW
    mk_task "$d/feat-f6/wp-01-f6" task-01-f6 low "[]"
    local out6 v6 tr6
    out6="$(bash "$SELF" "$d/feat-f6/wp-01-f6")"
    v6="$(echo "$out6"  | command jq -r '.verdict')"
    tr6="$(echo "$out6" | command jq -c '.tripped')"
    if [[ "$v6" == "simple" && "$tr6" == '[]' ]]; then
        ok "F6-simple"
    else
        no "F6-simple" "verdict=$v6 tripped=$tr6"
    fi

    # ── F7: shared boundaries WITHOUT the flag do NOT trip S5 → simple ─────────
    # Regression guard: S5 is the author-declared flag only, never inferred from
    # boundary-glob overlap (3 WPs sharing a glob but none flagged → all simple).
    for _w in wp-01-f7 wp-02-f7 wp-03-f7; do
        mkdir -p "$d/feat-f7/$_w"
        cat > "$d/feat-f7/$_w/overview.md" << 'EOF'
---
severity: LOW
goal:
  boundaries:
    - "common/scripts/**"
---
EOF
    done
    local out7 v7 tr7 cw7
    out7="$(bash "$SELF" "$d/feat-f7/wp-01-f7")"
    v7="$(echo "$out7"  | command jq -r '.verdict')"
    tr7="$(echo "$out7" | command jq -c '.tripped')"
    cw7="$(echo "$out7" | command jq -r '.signals.cross_wp')"
    if [[ "$v7" == "simple" && "$tr7" == '[]' && "$cw7" == "false" ]]; then
        ok "F7-common-not-contract"
    else
        no "F7-common-not-contract" "verdict=$v7 tripped=$tr7 cross_wp=$cw7"
    fi

    echo ""
    echo "Results: $t_pass passed, $t_fail failed"
    [[ "$t_fail" -eq 0 ]]
}

# ── Argument parsing ──────────────────────────────────────────────────────────
SELFTEST=0
POS=()

while [[ $# -gt 0 ]]; do
    case "$1" in
        --self-test) SELFTEST=1; shift ;;
        -h|--help)   usage; exit 0 ;;
        --*)         echo "ERROR: unknown flag: $1" >&2; exit 1 ;;
        *)           POS+=("$1"); shift ;;
    esac
done

if [[ "$SELFTEST" -eq 1 ]]; then
    self_test
    exit $?
fi

if [[ "${#POS[@]}" -lt 1 ]]; then
    echo "ERROR: usage: goalforge-wp-complexity.sh <wp-path>" >&2
    exit 1
fi

WP_PATH="$(cd "${POS[0]}" 2>/dev/null && pwd)" \
    || { echo "ERROR: wp-path not found: ${POS[0]}" >&2; exit 1; }

classify_wp "$WP_PATH"
