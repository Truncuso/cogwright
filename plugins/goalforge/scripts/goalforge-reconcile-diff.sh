#!/usr/bin/env bash
# sdd-reconcile-diff.sh — pure, deterministic WP reconcile-diff.
#
# Usage:
#   sdd-reconcile-diff.sh <existing-feature-dir> <proposed-json>
#   sdd-reconcile-diff.sh --self-test
#
# Args:
#   <existing-feature-dir>  Dir of wp-*/overview.md files (YAML frontmatter:
#                           name:, status:, goal.outcome:).
#   <proposed-json>         JSON file: [{"slug":"...","goal_outcome":"..."}, ...]
#
# Output: {"same":[...],"changed":[...],"dropped":[...],"new":[...],"ambiguous":[...]}
#   same      — slug present in both, goal-outcome identical.
#   changed   — slug present in both, goal-outcome differs.
#   dropped   — slug in existing only; verified:true when status was verified.
#   new       — slug in proposed only, outcome does not match any existing verified.
#   ambiguous — slug in proposed only, outcome MATCHES an existing verified WP.
#               Judgment-deferred: script NEVER auto-renames or auto-supersedes.
#               Both slugs carried; human/judgment-layer resolves rename-vs-new.
#               The matching existing verified WP is excluded from 'dropped'.
#
# Entries sorted by slug (ambiguous: by proposed_slug). Pure: no writes.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SELF="$SCRIPT_DIR/$(basename "${BASH_SOURCE[0]}")"

usage() {
    sed -n '2,23p' "$SELF" | sed 's/^# \{0,1\}//'
}

# ── Reconcile existing WPs against a proposed decomposition ──────────────────
reconcile_diff() {
    python3 - "$1" "$2" <<'PY'
import sys, re, json
from pathlib import Path
try:
    import yaml
except ImportError:
    sys.stderr.write("ERROR: PyYAML not available (pip3 install pyyaml)\n"); sys.exit(1)

existing_dir = Path(sys.argv[1])
proposed_json_path = sys.argv[2]

if not existing_dir.is_dir():
    sys.stderr.write("ERROR: existing-feature-dir not found: %s\n" % existing_dir); sys.exit(1)

try:
    proposed_list = json.loads(Path(proposed_json_path).read_text(encoding="utf-8"))
except Exception as e:
    sys.stderr.write("ERROR: cannot parse proposed-json: %s\n" % e); sys.exit(1)

def parse_fm(path):
    try:
        text = path.read_text(encoding="utf-8")
    except OSError:
        return None
    lines = text.split("\n")
    if not lines or lines[0].strip() != "---":
        return None
    end = None
    for i in range(1, len(lines)):
        if lines[i].strip() == "---":
            end = i; break
    if end is None:
        return None
    try:
        fm = yaml.safe_load("\n".join(lines[1:end]))
    except Exception:
        return None
    return fm if isinstance(fm, dict) else None

# Load existing WPs (sorted by dir name for deterministic output)
wp_dirs = sorted([d for d in existing_dir.iterdir()
                  if d.is_dir() and re.match(r"^wp-\d+", d.name)],
                 key=lambda d: d.name)

existing = {}   # slug -> {slug, goal_outcome, status}
for d in wp_dirs:
    ov = d / "overview.md"
    if not ov.exists():
        continue
    fm = parse_fm(ov)
    if fm is None:
        continue
    slug = str(fm.get("name") or d.name).strip()
    goal = fm.get("goal") or {}
    outcome = str(goal.get("outcome") or "").strip() if isinstance(goal, dict) else ""
    status_val = str(fm.get("status") or "").strip()
    existing[slug] = {"slug": slug, "goal_outcome": outcome, "status": status_val}

if not isinstance(proposed_list, list):
    sys.stderr.write("ERROR: proposed-json must be a JSON array\n"); sys.exit(1)

proposed = {}   # slug -> {slug, goal_outcome}
for item in proposed_list:
    slug = str(item.get("slug") or "").strip()
    outcome = str(item.get("goal_outcome") or "").strip()
    if slug:
        proposed[slug] = {"slug": slug, "goal_outcome": outcome}

VERIFIED = "verified"

# Index: goal_outcome -> slug, for existing WPs whose status is verified
verified_outcome_to_slug = {}
for slug, info in existing.items():
    if info["status"] == VERIFIED and info["goal_outcome"]:
        verified_outcome_to_slug[info["goal_outcome"]] = slug

# First pass: detect ambiguous pairs (proposed new slug whose outcome matches
# an existing verified WP) — these are pulled from both dropped and new.
ambiguous_existing = set()   # existing slugs claimed by ambiguous
ambiguous_proposed = set()   # proposed slugs claimed by ambiguous
ambiguous = []

for slug, pinfo in proposed.items():
    if slug not in existing:
        outcome = pinfo["goal_outcome"]
        if outcome and outcome in verified_outcome_to_slug:
            ev_slug = verified_outcome_to_slug[outcome]
            ambiguous.append({
                "existing_verified_slug": ev_slug,
                "proposed_slug": slug,
                "goal_outcome": outcome,
            })
            ambiguous_existing.add(ev_slug)
            ambiguous_proposed.add(slug)

# Second pass: classify remaining slugs
same = []
changed = []
dropped = []
new_wps = []

for slug, info in existing.items():
    if slug in ambiguous_existing:
        continue    # claimed by ambiguous
    if slug in proposed:
        if info["goal_outcome"] == proposed[slug]["goal_outcome"]:
            same.append({"slug": slug})
        else:
            changed.append({
                "slug": slug,
                "existing_goal_outcome": info["goal_outcome"],
                "proposed_goal_outcome": proposed[slug]["goal_outcome"],
            })
    else:
        dropped.append({"slug": slug, "verified": info["status"] == VERIFIED})

for slug, pinfo in proposed.items():
    if slug in existing:
        continue    # handled above
    if slug in ambiguous_proposed:
        continue    # claimed by ambiguous
    new_wps.append({"slug": slug, "goal_outcome": pinfo["goal_outcome"]})

# Sort all buckets deterministically
same.sort(key=lambda x: x["slug"])
changed.sort(key=lambda x: x["slug"])
dropped.sort(key=lambda x: x["slug"])
new_wps.sort(key=lambda x: x["slug"])
ambiguous.sort(key=lambda x: x["proposed_slug"])

print(json.dumps({
    "same": same,
    "changed": changed,
    "dropped": dropped,
    "new": new_wps,
    "ambiguous": ambiguous,
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

    # mkwp <feat-dir> <slug> <status> <outcome>
    mkwp() {
        local _fd="$1" _sl="$2" _st="$3" _oc="$4"
        mkdir -p "$_fd/$_sl"
        cat > "$_fd/$_sl/overview.md" << EOF
---
name: $_sl
title: $_sl
status: $_st
stage_updated: 2026-06-23
severity: LOW
parallel: false
depends_on: []
plan: test-feat
goal:
  outcome: "$_oc"
  verification:
    strategy: deterministic
    check: "true"
  constraints: []
  boundaries: []
  iteration_policy: "retry until green"
  blocked_stop: "halt after 3 tries"
inherits_from: null
goal_approved_version: null
---

# $_sl
EOF
    }

    local ok no
    ok() { echo "$1: PASS"; t_pass=$((t_pass+1)); }
    no() { echo "$1: FAIL — $2"; t_fail=$((t_fail+1)); }

    echo "=== sdd-reconcile-diff.sh --self-test ==="

    # ── (1) identity: proposed == existing → all same, all other buckets empty ──
    mkdir -p "$d/feat-identity"
    mkwp "$d/feat-identity" wp-01-alpha spec "deliver alpha"
    mkwp "$d/feat-identity" wp-02-beta  spec "deliver beta"
    local pj_id="$d/proposed-identity.json"
    printf '%s\n' '[{"slug":"wp-01-alpha","goal_outcome":"deliver alpha"},{"slug":"wp-02-beta","goal_outcome":"deliver beta"}]' > "$pj_id"
    local out_id same_id changed_id dropped_id new_id amb_id
    out_id="$(bash "$SELF" "$d/feat-identity" "$pj_id")"
    same_id="$(echo "$out_id"    | command jq -c '.same | length')"
    changed_id="$(echo "$out_id" | command jq -c '.changed | length')"
    dropped_id="$(echo "$out_id" | command jq -c '.dropped | length')"
    new_id="$(echo "$out_id"     | command jq -c '.new | length')"
    amb_id="$(echo "$out_id"     | command jq -c '.ambiguous | length')"
    if [[ "$same_id" == "2" && "$changed_id" == "0" && "$dropped_id" == "0" && "$new_id" == "0" && "$amb_id" == "0" ]]; then
        ok "identity"
    else
        no "identity" "same=$same_id changed=$changed_id dropped=$dropped_id new=$new_id ambiguous=$amb_id"
    fi

    # ── (2) ambiguous: existing verified WP whose slug changes but outcome matches ─
    mkdir -p "$d/feat-ambig"
    mkwp "$d/feat-ambig" wp-01-old  verified "shared outcome text"
    mkwp "$d/feat-ambig" wp-02-keep spec     "keep as is"
    local pj_amb="$d/proposed-ambig.json"
    printf '%s\n' '[{"slug":"wp-01-renamed","goal_outcome":"shared outcome text"},{"slug":"wp-02-keep","goal_outcome":"keep as is"}]' > "$pj_amb"
    local files_before files_after
    files_before="$(find "$d/feat-ambig" -type f | sort | wc -l | tr -d ' ')"
    local out_amb amb_count amb_ev_slug amb_pr_slug same_amb dropped_amb
    out_amb="$(bash "$SELF" "$d/feat-ambig" "$pj_amb")"
    files_after="$(find "$d/feat-ambig" -type f | sort | wc -l | tr -d ' ')"
    amb_count="$(echo "$out_amb"    | command jq -c '.ambiguous | length')"
    amb_ev_slug="$(echo "$out_amb"  | command jq -r '.ambiguous[0].existing_verified_slug')"
    amb_pr_slug="$(echo "$out_amb"  | command jq -r '.ambiguous[0].proposed_slug')"
    same_amb="$(echo "$out_amb"     | command jq -c '.same | length')"
    dropped_amb="$(echo "$out_amb"  | command jq -c '.dropped | length')"
    if [[ "$amb_count" == "1" && "$amb_ev_slug" == "wp-01-old" && "$amb_pr_slug" == "wp-01-renamed" \
          && "$same_amb" == "1" && "$dropped_amb" == "0" && "$files_before" == "$files_after" ]]; then
        ok "ambiguous"
    else
        no "ambiguous" "amb=$amb_count ev=$amb_ev_slug pr=$amb_pr_slug same=$same_amb dropped=$dropped_amb files_before=$files_before files_after=$files_after"
    fi

    # ── (3) drop-verified: existing verified WP absent from proposed → dropped verified:true ─
    mkdir -p "$d/feat-drop"
    mkwp "$d/feat-drop" wp-01-done   verified "completed thing"
    mkwp "$d/feat-drop" wp-02-active spec     "active work"
    local pj_drop="$d/proposed-drop.json"
    printf '%s\n' '[{"slug":"wp-02-active","goal_outcome":"active work"}]' > "$pj_drop"
    local out_drop drop_count drop_verified same_drop
    out_drop="$(bash "$SELF" "$d/feat-drop" "$pj_drop")"
    drop_count="$(echo "$out_drop"    | command jq -c '.dropped | length')"
    drop_verified="$(echo "$out_drop" | command jq -r '.dropped[0].verified')"
    same_drop="$(echo "$out_drop"     | command jq -c '.same | length')"
    if [[ "$drop_count" == "1" && "$drop_verified" == "true" && "$same_drop" == "1" ]]; then
        ok "drop-verified"
    else
        no "drop-verified" "drop_count=$drop_count verified=$drop_verified same=$same_drop"
    fi

    # ── (4) changed: same slug, different goal-outcome ───────────────────────────
    mkdir -p "$d/feat-changed"
    mkwp "$d/feat-changed" wp-01-x spec "original outcome"
    local pj_changed="$d/proposed-changed.json"
    printf '%s\n' '[{"slug":"wp-01-x","goal_outcome":"revised outcome"}]' > "$pj_changed"
    local out_changed ch_count ch_slug ch_ex ch_pr
    out_changed="$(bash "$SELF" "$d/feat-changed" "$pj_changed")"
    ch_count="$(echo "$out_changed" | command jq -c '.changed | length')"
    ch_slug="$(echo "$out_changed"  | command jq -r '.changed[0].slug')"
    ch_ex="$(echo "$out_changed"    | command jq -r '.changed[0].existing_goal_outcome')"
    ch_pr="$(echo "$out_changed"    | command jq -r '.changed[0].proposed_goal_outcome')"
    if [[ "$ch_count" == "1" && "$ch_slug" == "wp-01-x" && "$ch_ex" == "original outcome" && "$ch_pr" == "revised outcome" ]]; then
        ok "changed"
    else
        no "changed" "count=$ch_count slug=$ch_slug ex=$ch_ex pr=$ch_pr"
    fi

    # ── (5) new: genuinely new slug with non-matching outcome ────────────────────
    mkdir -p "$d/feat-new"
    mkwp "$d/feat-new" wp-01-existing spec "existing outcome"
    local pj_new="$d/proposed-new.json"
    printf '%s\n' '[{"slug":"wp-01-existing","goal_outcome":"existing outcome"},{"slug":"wp-02-brand-new","goal_outcome":"novel outcome"}]' > "$pj_new"
    local out_new new_count new_slug same_new
    out_new="$(bash "$SELF" "$d/feat-new" "$pj_new")"
    new_count="$(echo "$out_new" | command jq -c '.new | length')"
    new_slug="$(echo "$out_new"  | command jq -r '.new[0].slug')"
    same_new="$(echo "$out_new"  | command jq -c '.same | length')"
    if [[ "$new_count" == "1" && "$new_slug" == "wp-02-brand-new" && "$same_new" == "1" ]]; then
        ok "new"
    else
        no "new" "new_count=$new_count slug=$new_slug same=$same_new"
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

if [[ "${#POS[@]}" -lt 2 ]]; then
    echo "ERROR: usage: sdd-reconcile-diff.sh <existing-feature-dir> <proposed-json>" >&2
    exit 1
fi

EXISTING_DIR="$(cd "${POS[0]}" 2>/dev/null && pwd)" \
    || { echo "ERROR: existing-feature-dir not found: ${POS[0]}" >&2; exit 1; }
PROPOSED_JSON="${POS[1]}"
[[ -f "$PROPOSED_JSON" ]] \
    || { echo "ERROR: proposed-json not found: $PROPOSED_JSON" >&2; exit 1; }

reconcile_diff "$EXISTING_DIR" "$PROPOSED_JSON"
