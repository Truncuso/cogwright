#!/usr/bin/env bash
# goalforge-harden-surface.sh — surface a harden-panel finding as a propose-only route record.
#
# Usage:
#   goalforge-harden-surface.sh [<finding-json>]    # file path, or "-"/omitted = stdin
#   goalforge-harden-surface.sh --self-test
#
# Args:
#   <finding-json>  A single panel finding as JSON (file path, or "-"/omitted = stdin).
#                   Recognized fields (all optional): severity, type, summary, area, skill.
#
# Behavior:
#   Classifies the finding and emits a PROPOSE-ONLY route record naming where the
#   improvement should go. It NEVER captures, writes, or commits anything — the
#   record is the proposal; invoking idea-capture / skill-improve is a separate,
#   human-gated step. This keeps surfacing from widening the WP goal.
#     skill gap (skill set, or area/type names a skill) -> target "skill-improve"
#       (propose-only; global skills are never auto-edited)
#     otherwise                                          -> target "idea-capture"
#       (mode "from-sdd")
#
# Output:
#   Single-line JSON route record on stdout (written nowhere on disk):
#   {"action":"propose","propose_only":true,"committed":false,"target":...,
#    "mode":...?,"skill":...?,"finding":{...},"note":...}
#
#   Exit 0 on success. Exit 1 on errors (stderr).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SELF="$SCRIPT_DIR/$(basename "${BASH_SOURCE[0]}")"

usage() {
    sed -n '2,28p' "$SELF" | sed 's/^# \{0,1\}//'
}

# ── Surface a finding as a propose-only route record ─────────────────────────
surface_finding() {
    local src="${1:-}" payload
    if [[ "$src" == "-" || -z "$src" ]]; then
        payload="$(cat)"
    else
        [[ -f "$src" ]] || { echo "ERROR: finding-json not found: $src" >&2; exit 1; }
        payload="$(cat "$src")"
    fi
    FINDING_JSON="$payload" python3 - <<'PY'
import json, os, sys
raw = os.environ.get("FINDING_JSON", "").strip()
if not raw:
    sys.stderr.write("ERROR: empty finding (expected JSON on stdin or in <finding-json>)\n"); sys.exit(1)
try:
    f = json.loads(raw)
except Exception as e:
    sys.stderr.write("ERROR: cannot parse finding JSON: %s\n" % e); sys.exit(1)
if not isinstance(f, dict):
    sys.stderr.write("ERROR: finding must be a JSON object\n"); sys.exit(1)

skill = str(f.get("skill") or "").strip()
area  = str(f.get("area") or "").strip().lower()
ftype = str(f.get("type") or "").strip().lower()
is_skill_gap = bool(skill) or area == "skill" or "skill" in ftype

record = {
    "action": "propose",
    "propose_only": True,
    "committed": False,
    "finding": f,
    "note": "propose-only: surfaced from the harden panel; does not widen the WP goal",
}
if is_skill_gap:
    record["target"] = "skill-improve"
    if skill:
        record["skill"] = skill
else:
    record["target"] = "idea-capture"
    record["mode"] = "from-sdd"

print(json.dumps(record))
PY
}

# ── Self-test ─────────────────────────────────────────────────────────────────
_ST_TMP=""
self_test() {
    local t_pass=0 t_fail=0 g

    _ST_TMP="$(mktemp -d)"
    trap '[[ -n "${_ST_TMP:-}" ]] && rm -rf "$_ST_TMP"' EXIT
    g="$_ST_TMP/repo"
    mkdir -p "$g"
    # Isolated git repo with hooks disabled so the user's global commit-msg /
    # pre-push hooks never fire inside the fixture.
    git -C "$g" init -q
    git -C "$g" config user.email t@example.com
    git -C "$g" config user.name t
    : > "$g/seed"
    git -C "$g" add seed
    git -C "$g" -c core.hooksPath=/dev/null -c commit.gpgsign=false commit -q -m seed

    local ok no
    ok() { echo "$1: PASS"; t_pass=$((t_pass+1)); }
    no() { echo "$1: FAIL — $2"; t_fail=$((t_fail+1)); }

    # run_in_repo <finding-json> → sets REC + TREE_UNCHANGED by snapshotting the
    # repo's porcelain status before/after. Proves the helper writes nothing.
    local REC TREE_UNCHANGED
    run_in_repo() {
        local before after
        before="$(git -C "$g" status --porcelain)"
        REC="$(cd "$g" && printf '%s' "$1" | bash "$SELF" -)"
        after="$(git -C "$g" status --porcelain)"
        [[ "$before" == "$after" ]] && TREE_UNCHANGED=1 || TREE_UNCHANGED=0
    }

    echo "=== goalforge-harden-surface.sh --self-test ==="

    # ── skill gap → skill-improve, propose-only, tree unchanged ───────────────
    run_in_repo '{"severity":"MEDIUM","summary":"goalforge-harden panel lacks a debate-mode default","skill":"goalforge-harden"}'
    local tgt po skl
    tgt="$(echo "$REC" | command jq -r '.target')"
    po="$(echo "$REC"  | command jq -r '.propose_only')"
    skl="$(echo "$REC" | command jq -r '.skill')"
    if [[ "$tgt" == "skill-improve" && "$po" == "true" && "$skl" == "goalforge-harden" && "$TREE_UNCHANGED" == "1" ]]; then
        ok "skill-gap-to-skill-improve-propose-only"
    else
        no "skill-gap-to-skill-improve-propose-only" "target=$tgt propose_only=$po skill=$skl tree_unchanged=$TREE_UNCHANGED"
    fi

    # ── non-skill finding → idea-capture from-sdd, nothing committed ──────────
    run_in_repo '{"severity":"LOW","summary":"cross-retry observability could be a feature","area":"plan"}'
    local tgt2 mode2 com2
    tgt2="$(echo "$REC"  | command jq -r '.target')"
    mode2="$(echo "$REC" | command jq -r '.mode')"
    com2="$(echo "$REC"  | command jq -r '.committed')"
    if [[ "$tgt2" == "idea-capture" && "$mode2" == "from-sdd" && "$com2" == "false" && "$TREE_UNCHANGED" == "1" ]]; then
        ok "non-skill-to-idea-capture-tree-unchanged"
    else
        no "non-skill-to-idea-capture-tree-unchanged" "target=$tgt2 mode=$mode2 committed=$com2 tree_unchanged=$TREE_UNCHANGED"
    fi

    # ── propose-only is never a commit: HEAD does not move ────────────────────
    local head_before head_after
    head_before="$(git -C "$g" rev-parse HEAD)"
    run_in_repo '{"severity":"HIGH","summary":"x","skill":"foo"}'
    head_after="$(git -C "$g" rev-parse HEAD)"
    if [[ "$head_before" == "$head_after" && "$TREE_UNCHANGED" == "1" ]]; then
        ok "nothing-committed"
    else
        no "nothing-committed" "HEAD $head_before -> $head_after tree_unchanged=$TREE_UNCHANGED"
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
        -)           POS+=("$1"); shift ;;
        --*)         echo "ERROR: unknown flag: $1" >&2; exit 1 ;;
        *)           POS+=("$1"); shift ;;
    esac
done

if [[ "$SELFTEST" -eq 1 ]]; then
    self_test
    exit $?
fi

surface_finding "${POS[0]:-}"
