#!/usr/bin/env bash
# sdd-transition.sh — the single WP- and FEATURE-status write mechanism.
#
# Usage:
#   sdd-transition.sh <path> <to> --reason "<text>" \
#       [--from <s>] [--actor <id>] [--override] \
#       [--mode human|auto] [--agent <id>] [--decision-ref <ref>]
#   sdd-transition.sh --self-test
#
# <path> is either a WP dir/overview.md (frontmatter has a `plan:` key) or a
# FEATURE dir/overview.md (frontmatter has `work_packages:`/`feature:` and NO
# `plan:` key). The `plan:` key is the discriminator. WP targets validate against
# the `## Edges` table; FEATURE targets against `## Feature edges` — both in
#   references/state-machine.md.
# Feature-level `→ready` skips the WP-only goal-hash gate; `archived` is not a
# feature edge target (that terminal move lives in sdd-archive.sh only).
#
# Reads the overview.md current `status:` as the authoritative `from`,
# validates the `from→to` edge against the selected table
# (illegal → exit 1; a reverse edge requires `--reason`), then under a POSIX
# `flock` on `<feature-dir>/.sdd-transitions.lock`:
#   1. writes `status:` + `stage_updated:` into overview.md (atomic mktemp→mv),
#   2. appends a JSON row to `plans/<feature>/.sdd-transitions.jsonl`
#      (git-tracked, append-only) — each row carries an auto-filled attribution
#      stamp {mode,actor,session,model,provider,agent,decision_ref} sourced from
#      sdd-attribution.sh (degrade-not-block: any failure → "unknown"),
#   3. invokes sdd-stamp-tables.sh (WP/Tasks STATUS cells — the P5 autostamp)
#      and sdd-rollup.sh (feature todo.md).
# It NEVER writes table cells directly — that is sdd-stamp-tables.sh's job.
#
# `--from` is an optimistic-lock assertion: when given it must equal the on-disk
# status, else the transition is rejected (non-zero). The `.sdd-transitions.lock`
# file is gitignored, never committed.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SELF="$SCRIPT_DIR/$(basename "${BASH_SOURCE[0]}")"
STATE_MACHINE="$SCRIPT_DIR/../references/state-machine.md"
STAMP="$SCRIPT_DIR/goalforge-stamp-tables.sh"
ROLLUP="$SCRIPT_DIR/goalforge-rollup.sh"
VALIDATE="$SCRIPT_DIR/goalforge-validate.sh"
ATTRIB="$SCRIPT_DIR/goalforge-attribution.sh"

usage() {
    sed -n '2,20p' "$SELF" | sed 's/^# \{0,1\}//'
}

# ── Read the on-disk `status:` from a WP overview.md frontmatter ─────────────
read_status() {
    python3 - "$1" <<'PY'
import sys, re
path = sys.argv[1]
val = ""
started = infm = False
try:
    text = open(path, encoding="utf-8").read()
except OSError:
    print(""); sys.exit(0)
for ln in text.splitlines():
    if ln.strip() == "---":
        if not started:
            started = infm = True
            continue
        break
    if infm:
        m = re.match(r"^status:\s*(.*)$", ln)
        if m:
            val = m.group(1).strip().strip("'\"")
            break
print(val)
PY
}

# ── Read goal_approved_version from a WP overview.md frontmatter ──────────────
read_goal_approved() {
    python3 - "$1" <<'PY'
import sys, re
val = ""
started = infm = False
try:
    text = open(sys.argv[1], encoding="utf-8").read()
except OSError:
    print(""); sys.exit(0)
for ln in text.splitlines():
    if ln.strip() == "---":
        if not started:
            started = infm = True
            continue
        break
    if infm:
        m = re.match(r"^goal_approved_version:\s*(.*)$", ln)
        if m:
            val = m.group(1).strip().strip("'\"")
            break
print(val)
PY
}

# ── Read schema_version from a WP overview.md frontmatter ───────────────────
read_schema_version() {
    python3 - "$1" <<'PY'
import sys, re
val = ""
started = infm = False
try:
    text = open(sys.argv[1], encoding="utf-8").read()
except OSError:
    print(""); sys.exit(0)
for ln in text.splitlines():
    if ln.strip() == "---":
        if not started:
            started = infm = True
            continue
        break
    if infm:
        m = re.match(r"^schema_version:\s*(.*)$", ln)
        if m:
            val = m.group(1).strip().strip("'\"")
            break
print(val)
PY
}

# ── Classify an overview.md as a WP or a FEATURE by frontmatter ──────────────
# Discriminator: a top-level `plan:` key => "wp" (points at its parent feature);
# else `work_packages:`/`feature:` => "feature"; else "error". Only top-level
# scalar keys are scanned (indented lines under `goal:` etc. are skipped), so a
# WP's `goal:` block never confuses the check.
classify_target() {
    python3 - "$1" <<'PY'
import sys, re
try:
    text = open(sys.argv[1], encoding="utf-8").read()
except OSError:
    print("error"); sys.exit(0)
lines = text.split("\n")
if not lines or lines[0].strip() != "---":
    print("error"); sys.exit(0)
keys = set()
for ln in lines[1:]:
    if ln.strip() == "---":
        break
    if not ln or ln[0] in " \t#":
        continue
    m = re.match(r"^([A-Za-z0-9_-]+):", ln)
    if m:
        keys.add(m.group(1))
if "plan" in keys:
    print("wp")
elif "work_packages" in keys or "feature" in keys:
    print("feature")
else:
    print("error")
PY
}

# ── Look up a from→to edge in state-machine.md ──────────────────────────────
# Prints "legal <reason_required> <human_gated>" or "illegal" (or "error").
# $3 selects the table section header ("Edges" for WPs, "Feature edges" for
# features) — matched exactly so the two tables never collide.
edge_lookup() {
    python3 - "$STATE_MACHINE" "$1" "$2" "$3" <<'PY'
import sys
sm, frm, to, header = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4]
want = ("## " + header).lower()
try:
    text = open(sm, encoding="utf-8").read()
except OSError:
    print("error"); sys.exit(0)
in_edges = False
for ln in text.splitlines():
    s = ln.strip()
    if s.startswith("## "):
        in_edges = s.lower() == want
        continue
    if not in_edges or not s.startswith("|"):
        continue
    cells = [c.strip() for c in s.strip("|").split("|")]
    if len(cells) < 4:
        continue
    if cells[0].lower() == "from" or set("".join(cells)) <= set("-: "):
        continue
    if cells[0] == frm and cells[1] == to:
        print(f"legal {cells[2]} {cells[3]}")
        sys.exit(0)
print("illegal")
PY
}

# ── The write: atomic status/stage_updated rewrite + ledger append ───────────
do_write() {
    # args: overview to today ledger wp from reason actor override commit ts
    #       session model provider agent mode decision_ref
    python3 - "$@" <<'PY'
import sys, json, os, re, tempfile
(overview, to, today, ledger, wp, frm, reason,
 actor, override, commit, ts,
 session, model, provider, agent, mode, decision_ref) = sys.argv[1:18]
text = open(overview, encoding="utf-8").read()
lines = text.split("\n")
if not lines or lines[0].strip() != "---":
    sys.stderr.write("no frontmatter in %s\n" % overview); sys.exit(1)
end = None
for i in range(1, len(lines)):
    if lines[i].strip() == "---":
        end = i; break
if end is None:
    sys.stderr.write("unterminated frontmatter in %s\n" % overview); sys.exit(1)
have_status = have_stage = False
for i in range(1, end):
    if re.match(r"^status:\s*", lines[i]):
        lines[i] = "status: %s" % to; have_status = True
    elif re.match(r"^stage_updated:\s*", lines[i]):
        lines[i] = "stage_updated: %s" % today; have_stage = True
if not have_status:
    lines.insert(1, "status: %s" % to); end += 1
if not have_stage:
    lines.insert(end, "stage_updated: %s" % today)
new = "\n".join(lines)
d = os.path.dirname(os.path.abspath(overview))
fd, tmp = tempfile.mkstemp(dir=d, suffix=".tmp")
try:
    with os.fdopen(fd, "w", encoding="utf-8") as f:
        f.write(new)
    os.replace(tmp, overview)
except Exception:
    try: os.unlink(tmp)
    except OSError: pass
    raise
row = {"ts": ts, "wp": wp, "from": frm, "to": to, "reason": reason,
       "actor": actor, "override": override == "true", "commit": commit,
       "mode": mode, "session": session, "model": model,
       "provider": provider, "agent": agent, "decision_ref": decision_ref}
with open(ledger, "a", encoding="utf-8") as f:
    f.write(json.dumps(row, sort_keys=False) + "\n")
PY
}

# ── A single transition (validated write under the per-feature lock) ─────────
transition() {
    local WP_PATH="$1" TO="$2"
    local WP_DIR OVERVIEW FEATURE_DIR FROM KIND SECTION

    if [[ -d "$WP_PATH" ]]; then
        WP_DIR="$(cd "$WP_PATH" && pwd)"; OVERVIEW="$WP_DIR/overview.md"
    elif [[ -f "$WP_PATH" ]]; then
        OVERVIEW="$(cd "$(dirname "$WP_PATH")" && pwd)/$(basename "$WP_PATH")"
        WP_DIR="$(dirname "$OVERVIEW")"
    else
        echo "ERROR: path not found: $WP_PATH" >&2; return 1
    fi
    [[ -f "$OVERVIEW" ]] || { echo "ERROR: overview.md not found: $OVERVIEW" >&2; return 1; }

    # A WP's ledger/lock/stamp/rollup all live at its parent feature dir; a
    # FEATURE is its own feature dir (the target itself). Route by frontmatter.
    KIND="$(classify_target "$OVERVIEW")"
    case "$KIND" in
        wp)      FEATURE_DIR="$(dirname "$WP_DIR")"; SECTION="Edges" ;;
        feature) FEATURE_DIR="$WP_DIR";              SECTION="Feature edges" ;;
        *)       echo "ERROR: cannot classify $OVERVIEW as a WP or feature (no plan:/work_packages:/feature: key)" >&2; return 1 ;;
    esac

    FROM="$(read_status "$OVERVIEW")"
    if [[ -z "$FROM" ]]; then
        echo "ERROR: could not read current status: from $OVERVIEW" >&2; return 1
    fi
    if [[ -n "$FROM_ASSERT" && "$FROM_ASSERT" != "$FROM" ]]; then
        echo "ERROR: --from $FROM_ASSERT does not match on-disk status $FROM (optimistic-lock reject)" >&2
        return 1
    fi

    local RES VERDICT RR HG
    RES="$(edge_lookup "$FROM" "$TO" "$SECTION")"
    read -r VERDICT RR HG <<<"$RES"
    if [[ "$VERDICT" != "legal" ]]; then
        echo "ERROR: illegal transition $FROM -> $TO (not in state-machine.md $SECTION)" >&2; return 1
    fi
    if [[ "$RR" == "yes" && -z "$REASON" ]]; then
        echo "ERROR: reverse transition $FROM -> $TO requires --reason" >&2; return 1
    fi

    # ── →ready hash gate (Gap 1) — WP-only (feature has no goal: block) ──────
    # A WP WITH a goal: block may reach `ready` only when goal_approved_version is
    # present AND equal to the recomputed goal-block hash. Covers BOTH ready doors
    # (human approval + signal-scoped --mode auto) since both go through here.
    # Fail-CLOSED: sdd-goal-hash exit 3 = no goal block ⇒ nothing to hash, a
    # stamp-less WP is outside Gap 1's scope (bounded exemption; skip). Any OTHER
    # non-zero (IO/usage error on a WP that HAS a block) REFUSES — never a silent
    # skip, which would let an unapproved WP reach ready.
    if [[ "$KIND" == "wp" && "$TO" == "ready" ]]; then
        local GOAL_HASH_SH="$SCRIPT_DIR/goalforge-goal-hash.sh"
        local RECOMPUTED GH_RC APPROVED
        set +e; RECOMPUTED="$(bash "$GOAL_HASH_SH" "$OVERVIEW" 2>/dev/null)"; GH_RC=$?; set -e
        if [[ "$GH_RC" -eq 3 ]]; then
            # no goal: block — bounded exemption, but ONLY when there is also no
            # stamp: a goal-less WP carrying a stray stamp can't be validated against
            # any hash, so refuse it rather than let it pass unchecked.
            #
            # schema_version>=5 goal-mandatory rule (mirrors sdd-validate.sh's
            # check_goal_mandatory): under that marker a goal-less WP is not
            # exempt — sdd-validate would fatally reject it at ready/executing/
            # verified anyway, so refuse the transition here instead of letting
            # it land and immediately fail validation. Absent marker (schema_version
            # <5 or no marker) leaves the bounded exemption byte-identical.
            # Pure-bash validation (no python3 interpolation of a
            # frontmatter-derived value into a python literal — that was an
            # injection/breakage risk on a crafted schema_version). A
            # non-numeric value fails the regex and is treated as the legacy
            # exemption path, mirroring sdd-validate.sh's check_goal_mandatory:
            # it warns and skips the check on ValueError (not this check's
            # concern) rather than fatally rejecting — same effective outcome
            # (no goal required) as sv_num < 5.
            local SCHEMA_VER
            SCHEMA_VER="$(read_schema_version "$OVERVIEW")"
            if [[ -n "$SCHEMA_VER" ]] && [[ "$SCHEMA_VER" =~ ^[0-9]+$ ]] && (( SCHEMA_VER >= 5 )); then
                echo "ready refused: schema_version >= 5 requires a goal: block (goal-mandatory rule; see sdd-validate.sh check_goal_mandatory) — none present on $(basename "$WP_DIR")" >&2
                return 1
            fi
            APPROVED="$(read_goal_approved "$OVERVIEW")"
            if [[ -n "$APPROVED" && "$APPROVED" != "null" ]]; then
                echo "ready refused: goal_approved_version missing or != recomputed hash (run goalforge-goal-hash.sh --record $(basename "$WP_DIR"))" >&2
                return 1
            fi
        elif [[ "$GH_RC" -ne 0 ]]; then
            echo "ready refused: goal_approved_version missing or != recomputed hash (run goalforge-goal-hash.sh --record $(basename "$WP_DIR"))" >&2
            return 1
        else
            APPROVED="$(read_goal_approved "$OVERVIEW")"
            if [[ -z "$APPROVED" || "$APPROVED" == "null" || "$APPROVED" != "$RECOMPUTED" ]]; then
                echo "ready refused: goal_approved_version missing or != recomputed hash (run goalforge-goal-hash.sh --record $(basename "$WP_DIR"))" >&2
                return 1
            fi
        fi
    fi

    local LOCKFILE="$FEATURE_DIR/.sdd-transitions.lock"
    local LEDGER="$FEATURE_DIR/.sdd-transitions.jsonl"
    local TODAY TS COMMIT WP_NAME
    TODAY="$(date +%F)"
    TS="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    COMMIT="$(git -C "$FEATURE_DIR" rev-parse --short HEAD 2>/dev/null || true)"
    WP_NAME="$(basename "$WP_DIR")"

    # ── Attribution stamp (auto-filled; degrade-not-block) ───────────────────
    # Reuse sdd-attribution.sh (→ handoff-env.sh) for session/model/provider and
    # the mode-normalized actor. Any failure resolves to "unknown"; never blocks.
    local SESSION="unknown" MODEL="unknown" PROVIDER="unknown" ATTR_JSON
    ATTR_JSON="$(bash "$ATTRIB" --json --mode "$MODE" --actor "$ACTOR" --agent "$AGENT" 2>/dev/null || true)"
    if [[ -n "$ATTR_JSON" ]]; then
        SESSION="$( printf '%s' "$ATTR_JSON" | jq -r '.session  // "unknown"' 2>/dev/null || echo unknown)"
        MODEL="$(   printf '%s' "$ATTR_JSON" | jq -r '.model    // "unknown"' 2>/dev/null || echo unknown)"
        PROVIDER="$(printf '%s' "$ATTR_JSON" | jq -r '.provider // "unknown"' 2>/dev/null || echo unknown)"
        ACTOR="$(   printf '%s' "$ATTR_JSON" | jq -r '.actor    // empty'     2>/dev/null || true)"
    fi
    [[ -z "$ACTOR" ]] && ACTOR="auto"

    # Critical section: write → ledger → stamp → rollup, serialized per feature.
    exec 9>"$LOCKFILE"
    flock 9
    do_write "$OVERVIEW" "$TO" "$TODAY" "$LEDGER" "$WP_NAME" "$FROM" \
             "$REASON" "$ACTOR" "$OVERRIDE" "$COMMIT" "$TS" \
             "$SESSION" "$MODEL" "$PROVIDER" "$AGENT" "$MODE" "$DECISION_REF"
    bash "$STAMP" "$FEATURE_DIR" >/dev/null
    bash "$ROLLUP" "$FEATURE_DIR" >/dev/null
    flock -u 9
    exec 9>&-

    echo "transition: $WP_NAME $FROM -> $TO${HG:+ (human_gated=$HG)}"
}

# ── Self-test ───────────────────────────────────────────────────────────────
_ST_TMP=""
self_test() {
    local pr feat wp t_pass=0 t_fail=0
    _ST_TMP="$(mktemp -d)"
    trap '[[ -n "${_ST_TMP:-}" ]] && rm -rf "$_ST_TMP"' EXIT
    pr="$_ST_TMP/plans"; feat="$pr/tmpfeat"; wp="$feat/wp-01-x"
    mkdir -p "$wp"

    cat > "$feat/overview.md" <<'EOF'
---
name: tmpfeat
title: Transition self-test fixture
status: ready
created: 2026-06-23
feature: tmpfeat
work_packages: [wp-01-x]
---

# self-test fixture feature
EOF
    cat > "$wp/overview.md" <<'EOF'
---
name: wp-01-x
title: Self-test WP
status: spec
stage_updated: 2026-06-23
severity: LOW
parallel: false
depends_on: []
plan: tmpfeat
---

# self-test wp
EOF
    cat > "$wp/task-01-x.md" <<'EOF'
---
name: task-01-x
title: noop task
status: pending
verify: "true"
---

# noop
EOF

    local ok
    ok() { echo "  PASS: $1"; t_pass=$((t_pass+1)); }
    no() { echo "  FAIL: $1"; t_fail=$((t_fail+1)); }

    echo "=== sdd-transition.sh --self-test ==="

    # (a) forward edge succeeds + writes a ledger row
    if bash "$SELF" "$wp" hardened --reason "fwd" >/dev/null 2>&1 \
       && [[ "$(read_status "$wp/overview.md")" == "hardened" ]] \
       && [[ -f "$feat/.sdd-transitions.jsonl" ]] \
       && grep -q '"to": "hardened"' "$feat/.sdd-transitions.jsonl" \
       && grep -q '"session":' "$feat/.sdd-transitions.jsonl" \
       && grep -q '"mode":' "$feat/.sdd-transitions.jsonl"; then
        ok "(a) forward edge succeeds + ledger row written (with attribution stamp)"
    else
        no "(a) forward edge should succeed and write a stamped ledger row"
    fi

    # (b) reverse edge WITHOUT --reason is rejected (status unchanged)
    if bash "$SELF" "$wp" spec >/dev/null 2>&1; then
        no "(b) reverse without --reason should be rejected"
    elif [[ "$(read_status "$wp/overview.md")" == "hardened" ]]; then
        ok "(b) reverse without --reason rejected (status unchanged)"
    else
        no "(b) reverse without --reason rejected but status mutated"
    fi

    # (c) reverse edge WITH --reason succeeds (free-reverse)
    if bash "$SELF" "$wp" spec --reason "reopen" >/dev/null 2>&1 \
       && [[ "$(read_status "$wp/overview.md")" == "spec" ]]; then
        ok "(c) reverse with --reason succeeds (free-reverse)"
    else
        no "(c) reverse with --reason should succeed"
    fi

    # (d) illegal/garbage `to` is rejected
    if bash "$SELF" "$wp" bogus --reason "x" >/dev/null 2>&1; then
        no "(d) garbage 'to' should be rejected"
    else
        ok "(d) illegal/garbage 'to' rejected"
    fi

    # (e) --from mismatch is rejected (current is spec; assert ready)
    if bash "$SELF" "$wp" hardened --from ready --reason "x" >/dev/null 2>&1; then
        no "(e) --from mismatch should be rejected"
    else
        ok "(e) --from optimistic-lock mismatch rejected"
    fi

    # (f) sdd-validate --strict green after forward→reverse→forward round-trip
    bash "$SELF" "$wp" hardened --reason "rt-fwd1" >/dev/null 2>&1 || true
    bash "$SELF" "$wp" spec --reason "rt-rev" >/dev/null 2>&1 || true
    bash "$SELF" "$wp" hardened --reason "rt-fwd2" >/dev/null 2>&1 || true
    if bash "$VALIDATE" --strict "$pr" >/dev/null 2>&1; then
        ok "(f) sdd-validate --strict green after round-trip"
    else
        echo "    --- validate --show ---" >&2
        bash "$VALIDATE" --strict --show "$pr" >&2 || true
        no "(f) sdd-validate --strict should be green after round-trip"
    fi

    # ── (g)(h)(i) →ready hash gate — fixtures carry a POPULATED goal: block
    #    (the fixture above has none). Isolated plans root; hardened→ready edge. ──
    local gpr gfeat
    gpr="$_ST_TMP/goalplans"; gfeat="$gpr/gfeat"
    mkdir -p "$gfeat/wp-g-ok" "$gfeat/wp-g-missing" "$gfeat/wp-g-freeform"
    cat > "$gfeat/overview.md" <<'EOF'
---
name: gfeat
title: ready-gate self-test
status: ready
created: 2026-06-23
feature: gfeat
work_packages: [wp-g-ok, wp-g-missing, wp-g-freeform]
---

# ready-gate fixture feature
EOF
    _mk_goal_wp() {  # $1=dir $2=name $3=stamp value (raw: null or "approved-v1")
        cat > "$1/overview.md" <<EOF
---
name: $2
title: ready-gate WP
status: hardened
stage_updated: 2026-06-23
severity: LOW
parallel: false
depends_on: []
plan: gfeat
task_type: code
goal:
  outcome: "the thing is done"
  verification:
    strategy: deterministic
    check: "true"
  constraints: []
  boundaries: []
  iteration_policy: "retry until green"
  blocked_stop: "halt after 3 tries"
inherits_from: null
goal_approved_version: $3
---

# ready-gate wp
EOF
    }
    _mk_goal_wp "$gfeat/wp-g-ok"       wp-g-ok       null
    _mk_goal_wp "$gfeat/wp-g-missing"  wp-g-missing  null
    _mk_goal_wp "$gfeat/wp-g-freeform" wp-g-freeform '"approved-v1"'
    # stamp ONLY wp-g-ok with its correct recomputed hash
    bash "$SCRIPT_DIR/goalforge-goal-hash.sh" --record "$gfeat/wp-g-ok" >/dev/null

    # (g) stamped-and-matching hardened→ready SUCCEEDS
    if bash "$SELF" "$gfeat/wp-g-ok" ready --reason "approved" >/dev/null 2>&1 \
       && [[ "$(read_status "$gfeat/wp-g-ok/overview.md")" == "ready" ]]; then
        ok "(g) →ready with matching goal_approved_version succeeds"
    else
        no "(g) →ready with matching stamp should succeed"
    fi

    # (h) missing stamp (null) hardened→ready REFUSED with the `ready refused:`
    #     message on stderr (asserted, and surfaced into stdout for the grep-guards)
    local h_out h_rc
    set +e; h_out="$(bash "$SELF" "$gfeat/wp-g-missing" ready --reason "x" 2>&1)"; h_rc=$?; set -e
    if [[ "$h_rc" -ne 0 ]] && echo "$h_out" | grep -qi 'ready refused' \
       && [[ "$(read_status "$gfeat/wp-g-missing/overview.md")" == "hardened" ]]; then
        ok "(h) missing stamp refused — $(echo "$h_out" | grep -i 'ready refused' | head -1)"
    else
        no "(h) →ready with missing stamp should be refused with 'ready refused' (rc=$h_rc)"
    fi

    # (i) free-form (non-hash) stamp hardened→ready REFUSED
    local i_out i_rc
    set +e; i_out="$(bash "$SELF" "$gfeat/wp-g-freeform" ready --reason "x" 2>&1)"; i_rc=$?; set -e
    if [[ "$i_rc" -ne 0 ]] && echo "$i_out" | grep -qi 'ready refused' \
       && [[ "$(read_status "$gfeat/wp-g-freeform/overview.md")" == "hardened" ]]; then
        ok "(i) free-form stamp refused"
    else
        no "(i) →ready with free-form stamp should be refused (rc=$i_rc)"
    fi

    # ── (j)(k) the GH_RC==3 exemption branch: a WP with NO goal: block ──────────
    mkdir -p "$gfeat/wp-g-nogoal" "$gfeat/wp-g-straystamp"
    _mk_nogoal_wp() {  # $1=dir $2=name $3=stamp (raw: null or "abc123def456")
        cat > "$1/overview.md" <<EOF
---
name: $2
title: goal-less WP
status: hardened
stage_updated: 2026-06-23
severity: LOW
parallel: false
depends_on: []
plan: gfeat
goal_approved_version: $3
---

# goal-less wp
EOF
    }
    # (j) no goal: block + no stamp → exemption fires, hardened→ready SUCCEEDS
    _mk_nogoal_wp "$gfeat/wp-g-nogoal" wp-g-nogoal null
    if bash "$SELF" "$gfeat/wp-g-nogoal" ready --reason "legacy" >/dev/null 2>&1 \
       && [[ "$(read_status "$gfeat/wp-g-nogoal/overview.md")" == "ready" ]]; then
        ok "(j) goal-less WP with no stamp reaches ready (bounded exemption)"
    else
        no "(j) goal-less stamp-less WP should reach ready (exemption)"
    fi
    # (k) no goal: block + a stray hash-shaped stamp → REFUSED (can't validate it)
    _mk_nogoal_wp "$gfeat/wp-g-straystamp" wp-g-straystamp '"abc123def456"'
    local k_out k_rc
    set +e; k_out="$(bash "$SELF" "$gfeat/wp-g-straystamp" ready --reason "x" 2>&1)"; k_rc=$?; set -e
    if [[ "$k_rc" -ne 0 ]] && echo "$k_out" | grep -qi 'ready refused' \
       && [[ "$(read_status "$gfeat/wp-g-straystamp/overview.md")" == "hardened" ]]; then
        ok "(k) goal-less WP with a stray stamp refused"
    else
        no "(k) goal-less WP with a stray stamp should be refused (rc=$k_rc)"
    fi

    # ── (n)(o)(p) schema_version>=5 goal-mandatory rule — the wp-08 gap-close ───
    #   sdd-validate.sh's check_goal_mandatory fatally rejects a schema_version>=5
    #   WP with no goal: block once it reaches ready/executing/verified. Before this
    #   fix the (j)-style bounded exemption was schema_version-blind, so such a WP
    #   could transition to `ready` here and be immediately rejected by validate —
    #   the two gates disagreed. (n) proves the new refusal; (o) proves the legacy
    #   (no-marker) exemption is untouched; (p) proves a v5 WP WITH a goal: block
    #   is unaffected by this rule (goes through the normal hash-gate path).
    mkdir -p "$gfeat/wp-g-v5-nogoal" "$gfeat/wp-g-v5-goal"
    cat > "$gfeat/wp-g-v5-nogoal/overview.md" <<EOF
---
name: wp-g-v5-nogoal
title: schema v5 goal-less WP
status: hardened
stage_updated: 2026-06-23
severity: LOW
parallel: false
depends_on: []
plan: gfeat
schema_version: 5
goal_approved_version: null
---

# schema v5 goal-less wp
EOF
    # (n) schema_version:5 + no goal: block → REFUSED (the gap this task closes)
    local n_out n_rc
    set +e; n_out="$(bash "$SELF" "$gfeat/wp-g-v5-nogoal" ready --reason "x" 2>&1)"; n_rc=$?; set -e
    if [[ "$n_rc" -ne 0 ]] && echo "$n_out" | grep -qi 'ready refused' \
       && [[ "$(read_status "$gfeat/wp-g-v5-nogoal/overview.md")" == "hardened" ]]; then
        ok "(n) schema_version:5 goal-less WP refused at →ready"
    else
        no "(n) schema_version:5 goal-less WP should be refused at →ready (rc=$n_rc)"
    fi

    # (o) legacy (no schema_version marker) goal-less WP → exemption UNCHANGED.
    #     Fresh fixture (distinct from (j)'s wp-g-nogoal) driven through the same
    #     hardened→ready edge, to pin the byte-identical no-marker behavior
    #     alongside the new (n) case rather than just re-checking (j)'s leftover state.
    mkdir -p "$gfeat/wp-g-legacy-nogoal"
    _mk_nogoal_wp "$gfeat/wp-g-legacy-nogoal" wp-g-legacy-nogoal null
    if bash "$SELF" "$gfeat/wp-g-legacy-nogoal" ready --reason "legacy" >/dev/null 2>&1 \
       && [[ "$(read_status "$gfeat/wp-g-legacy-nogoal/overview.md")" == "ready" ]]; then
        ok "(o) legacy no-marker goal-less WP exemption unchanged"
    else
        no "(o) legacy no-marker goal-less WP should still reach ready (exemption unchanged)"
    fi

    # (p) schema_version:5 WITH a goal: block → unaffected by this rule; falls
    #     through to the normal hash-gate path (refused there instead, for a
    #     different reason — missing/mismatched goal_approved_version — proving
    #     the new schema_version check does not fire when a goal: block exists)
    _mk_goal_wp "$gfeat/wp-g-v5-goal" wp-g-v5-goal null
    python3 - "$gfeat/wp-g-v5-goal/overview.md" <<'PY'
import sys
path = sys.argv[1]
text = open(path, encoding="utf-8").read()
lines = text.split("\n")
lines.insert(1, "schema_version: 5")
open(path, "w", encoding="utf-8").write("\n".join(lines))
PY
    local p_out p_rc
    set +e; p_out="$(bash "$SELF" "$gfeat/wp-g-v5-goal" ready --reason "x" 2>&1)"; p_rc=$?; set -e
    if [[ "$p_rc" -ne 0 ]] && echo "$p_out" | grep -qi 'ready refused' \
       && ! echo "$p_out" | grep -qi 'schema_version >= 5 requires a goal' \
       && [[ "$(read_status "$gfeat/wp-g-v5-goal/overview.md")" == "hardened" ]]; then
        ok "(p) schema_version:5 WITH goal: block unaffected by new rule (hash-gate refusal instead)"
    else
        no "(p) schema_version:5 WITH goal: block should hit the normal hash-gate path, not the new rule (rc=$p_rc)"
    fi

    # ── (l)(m) LIVE fast-route spec→ready --mode auto — the wp-07 regression ────
    #   Reproduces the defect wp-01's hash gate introduced: a route:fast WP is
    #   born goal_approved_version: null and takes spec→ready --mode auto with NO
    #   harden (the sole hash writer), so the null stamp made the fast route
    #   non-runnable end-to-end. (l) the bug: null stamp → REFUSED. (m) the fix:
    #   sdd-goal-hash.sh --record, then the SAME edge SUCCEEDS → ready. Drives the
    #   real spec→ready edge through this script — the coverage gap that let it ship.
    mkdir -p "$gfeat/wp-g-fast"
    cat > "$gfeat/wp-g-fast/overview.md" <<EOF
---
name: wp-g-fast
title: fast-route WP
status: spec
stage_updated: 2026-06-23
severity: LOW
parallel: false
depends_on: []
plan: gfeat
task_type: code
goal:
  outcome: "the fast thing is done"
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

# fast-route wp
EOF
    # (l) NEGATIVE — born null-stamped, spec→ready --mode auto REFUSED (the bug)
    local l_out l_rc
    set +e; l_out="$(bash "$SELF" "$gfeat/wp-g-fast" ready --mode auto --reason "fast-path: route=fast" 2>&1)"; l_rc=$?; set -e
    if [[ "$l_rc" -ne 0 ]] && echo "$l_out" | grep -qi 'ready refused' \
       && [[ "$(read_status "$gfeat/wp-g-fast/overview.md")" == "spec" ]]; then
        ok "(l) fast-route spec→ready --mode auto refused while goal hash unrecorded"
    else
        no "(l) fast-route spec→ready --mode auto should be refused with 'ready refused' (rc=$l_rc)"
    fi
    # (m) POSITIVE — record the hash, then the SAME edge SUCCEEDS → ready (the fix)
    bash "$SCRIPT_DIR/goalforge-goal-hash.sh" --record "$gfeat/wp-g-fast" >/dev/null
    if bash "$SELF" "$gfeat/wp-g-fast" ready --mode auto --reason "fast-path: route=fast" >/dev/null 2>&1 \
       && [[ "$(read_status "$gfeat/wp-g-fast/overview.md")" == "ready" ]]; then
        ok "(m) fast-route spec→ready --mode auto succeeds after --record → ready"
    else
        no "(m) fast-route spec→ready --mode auto should succeed after --record"
    fi

    # ── (q)(r)(s) FEATURE-level edges — the new feature-status write path ────────
    #   A feature overview (work_packages:/feature:, NO plan:) is its own feature
    #   dir: ledger/stamp/rollup land there. Validated against `## Feature edges`.
    #   (q) legal forward edge (no --reason) + feature-dir ledger row;
    #   (r) illegal feature edge (archived is sdd-archive-only, not an edge target);
    #   (s) reverse feature edge requires --reason.
    local featfx="$_ST_TMP/plans/featfx"
    mkdir -p "$featfx"
    cat > "$featfx/overview.md" <<'EOF'
---
name: featfx
title: feature-edge self-test fixture
status: executing
created: 2026-06-23
feature: featfx
work_packages: []
---

# feature-edge fixture
EOF

    # (q) legal forward feature edge executing→completed (no --reason needed)
    if bash "$SELF" "$featfx" completed >/dev/null 2>&1 \
       && [[ "$(read_status "$featfx/overview.md")" == "completed" ]] \
       && [[ -f "$featfx/.sdd-transitions.jsonl" ]] \
       && grep -q '"to": "completed"' "$featfx/.sdd-transitions.jsonl"; then
        ok "(q) feature forward edge executing→completed succeeds + feature-dir ledger row"
    else
        no "(q) feature forward edge executing→completed should succeed and write a ledger row"
    fi

    # (r) illegal feature edge: completed→archived rejected (archived not a target)
    if bash "$SELF" "$featfx" archived --reason "x" >/dev/null 2>&1; then
        no "(r) feature edge →archived should be rejected (sdd-archive-only)"
    elif [[ "$(read_status "$featfx/overview.md")" == "completed" ]]; then
        ok "(r) illegal feature edge →archived rejected (status unchanged)"
    else
        no "(r) feature edge →archived rejected but status mutated"
    fi

    # (s) reverse feature edge completed→executing WITHOUT --reason rejected;
    #     WITH --reason succeeds (FREE-REVERSE mirror)
    if bash "$SELF" "$featfx" executing >/dev/null 2>&1; then
        no "(s) reverse feature edge without --reason should be rejected"
    elif [[ "$(read_status "$featfx/overview.md")" != "completed" ]]; then
        no "(s) reverse feature edge without --reason rejected but status mutated"
    elif bash "$SELF" "$featfx" executing --reason "reopen for follow-up WP" >/dev/null 2>&1 \
       && [[ "$(read_status "$featfx/overview.md")" == "executing" ]]; then
        ok "(s) reverse feature edge requires --reason (rejected without, succeeds with)"
    else
        no "(s) reverse feature edge with --reason should succeed"
    fi

    echo ""
    echo "Results: $t_pass passed, $t_fail failed"
    [[ "$t_fail" -eq 0 ]]
}

# ── Argument parsing ────────────────────────────────────────────────────────
REASON=""
FROM_ASSERT=""
ACTOR=""
OVERRIDE="false"
MODE="auto"
AGENT=""
DECISION_REF=""
SELFTEST=0
POS=()

while [[ $# -gt 0 ]]; do
    case "$1" in
        --self-test)    SELFTEST=1; shift ;;
        --reason)       REASON="${2:-}"; shift 2 ;;
        --from)         FROM_ASSERT="${2:-}"; shift 2 ;;
        --actor)        ACTOR="${2:-}"; shift 2 ;;
        --override)     OVERRIDE="true"; shift ;;
        --mode)         MODE="${2:-auto}"; shift 2 ;;
        --agent)        AGENT="${2:-}"; shift 2 ;;
        --decision-ref) DECISION_REF="${2:-}"; shift 2 ;;
        -h|--help)      usage; exit 0 ;;
        --*)            echo "ERROR: unknown flag: $1" >&2; exit 1 ;;
        *)              POS+=("$1"); shift ;;
    esac
done

if [[ "$SELFTEST" -eq 1 ]]; then
    self_test
    exit $?
fi

if [[ "${#POS[@]}" -lt 2 ]]; then
    echo "ERROR: usage: sdd-transition.sh <wp-path> <to> --reason \"<text>\" [--from <s>] [--actor <id>] [--override] [--mode human|auto] [--agent <id>] [--decision-ref <ref>]" >&2
    exit 1
fi

transition "${POS[0]}" "${POS[1]}"
