#!/usr/bin/env bash
# goalforge-route.sh — capture-time chain-route classifier (fast|standard|wave).
#
# Reads a feature overview.md and emits one JSON object:
#   {"route":"fast"|"standard"|"wave","confidence":"clear"|"borderline"|"pinned",
#    "tripped":["R1",...],"signals":{...}}
#
# Baseline is FAST (small clean goal). Route escalates to STANDARD when ANY
# strong signal trips:
#   R1  frontmatter task_type is migration or ops            (strong)
#   R2  bullets under ## Scope  >= SDD_ROUTE_NS (default 4)  (strong)
#   R3  bullets under ## Open Questions >= SDD_ROUTE_NQ (3)  (strong)
#   R4  distinct path-like tokens in body >= SDD_ROUTE_NF (5)(strong)
#   R5  blast-radius keyword in Problem/Goal text             (weak)
# and escalates to WAVE when ANY wave signal trips (multi-feature /
# cross-spec / parallel fan-out markers — WAVE dominates STANDARD):
#   W1  bullets under ## Scope >= SDD_ROUTE_NW (default 8)   (wave)
#   W2  parallel/fan-out keyword in body                      (wave)
#
# Confidence:
#   pinned     — frontmatter already carries route: (echoed back; idempotent).
#                Legacy vocab normalizes on read: full->standard, one-go->fast
#                (never a 4th enum value). NEW vocab (fast|standard|wave)
#                echoes as-is. A route: line with an UNRECOGNIZED value (e.g. a
#                `route: fsat` typo) is not a valid pin: one WARN line to stderr,
#                the pin is discarded, and classification proceeds normally.
#   clear      — no signal (fast), >=1 strong signal (standard), or a wave
#                signal (wave).
#   borderline — only weak signal(s) tripped, or ## Goal missing/empty
#                (unclassifiable => safe default standard). Caller confirms with
#                the human on borderline; clear routes silently.
#
# Consumed by goalforge-capture as typed DATA, never as instructions.
# Exit 0 on success (verdict in JSON). Exit 1 on errors (stderr).
set -uo pipefail

usage() { echo "usage: goalforge-route.sh <feature-overview.md> | --self-test" >&2; }

classify() {
    # arg: <overview.md path>
    SDD_ROUTE_NS="${SDD_ROUTE_NS:-4}" SDD_ROUTE_NQ="${SDD_ROUTE_NQ:-3}" \
    SDD_ROUTE_NF="${SDD_ROUTE_NF:-5}" SDD_ROUTE_NW="${SDD_ROUTE_NW:-8}" \
    python3 - "$1" <<'PY'
import json, os, re, sys

path = sys.argv[1]
try:
    text = open(path, encoding="utf-8").read()
except OSError as e:
    print(f"sdd-goal-route: cannot read {path}: {e}", file=sys.stderr)
    sys.exit(1)

NS = int(os.environ.get("SDD_ROUTE_NS", 4))
NQ = int(os.environ.get("SDD_ROUTE_NQ", 3))
NF = int(os.environ.get("SDD_ROUTE_NF", 5))
NW = int(os.environ.get("SDD_ROUTE_NW", 8))

# Split frontmatter / body.
fm, body = "", text
m = re.match(r"^---\n(.*?)\n---\n(.*)$", text, re.DOTALL)
if m:
    fm, body = m.group(1), m.group(2)

# Pinned route: echo back, no re-classification (idempotent). Legacy vocab
# normalizes on read (full->standard, one-go->fast); never a 4th enum value.
mr = re.search(r"^route:\s*['\"]?(fast|standard|wave|full|one-go)", fm, re.MULTILINE)
if mr:
    LEGACY = {"full": "standard", "one-go": "fast"}
    route = LEGACY.get(mr.group(1), mr.group(1))
    print(json.dumps({"route": route, "confidence": "pinned",
                      "tripped": [], "signals": {"pinned": True}}))
    sys.exit(0)

# A route: line carrying an UNRECOGNIZED value (e.g. a `route: fsat` typo) is
# NOT a valid pin: warn on stderr, discard the pin, and fall through to normal
# classification rather than silently losing the user's (malformed) intent.
mbad = re.search(r"^route:\s*['\"]?([^\s'\"]+)", fm, re.MULTILINE)
if mbad:
    print(f"WARN: unrecognized route: '{mbad.group(1)}' — ignoring pin, "
          f"reclassifying", file=sys.stderr)

def section(name):
    """Lines of the named ## section (until next heading), [] when absent."""
    out, inside = [], False
    for ln in body.splitlines():
        h = re.match(r"^#{1,6}\s+(.*?)\s*$", ln)
        if h:
            inside = h.group(1).strip().lower() == name
            continue
        if inside:
            out.append(ln)
    return out

def bullets(lines):
    return [l for l in lines if re.match(r"^\s*[-*]\s+\S", l)]

goal_lines = [l for l in section("goal") if l.strip() and not l.strip().startswith("<")]
scope_bullets = len(bullets(section("scope")))
oq_bullets = len(bullets(section("open questions")))

# R1: task_type migration|ops in frontmatter (tolerate absent).
mt = re.search(r"^task_type:\s*['\"]?(\w+)", fm, re.MULTILINE)
r1 = bool(mt and mt.group(1) in ("migration", "ops"))

# R2 / R3: structure counts.
r2 = scope_bullets >= NS
r3 = oq_bullets >= NQ

# R4: distinct path-like tokens (dir/file.ext or a/b/c) in the body.
paths = set(re.findall(r"\b[\w.@-]+/[\w./@-]+\b", body))
r4 = len(paths) >= NF

# R5 (weak): blast-radius keywords in Problem + Goal prose.
probe = " ".join(section("problem") + goal_lines).lower()
kw = re.findall(r"\b(auth|migration|schema|security|breaking|public api|exported)\b", probe)
r5 = bool(kw)

# Wave signals (multi-feature / cross-spec / parallel fan-out markers).
w1 = scope_bullets >= NW
wkw = re.findall(
    r"\b(parallel|fan[- ]?out|cross-spec|multi-feature|multiple spec\w*|concurrent\w*|wave)\b",
    body.lower())
w2 = bool(wkw)

tripped = [s for s, hit in
           [("R1", r1), ("R2", r2), ("R3", r3), ("R4", r4), ("R5", r5),
            ("W1", w1), ("W2", w2)] if hit]
wave = [s for s in tripped if s in ("W1", "W2")]
strong = [s for s in tripped if s in ("R1", "R2", "R3", "R4")]
goal_missing = not goal_lines

if wave:
    route, confidence = "wave", "clear"
elif strong:
    route, confidence = "standard", "clear"
elif goal_missing or tripped:          # unclassifiable, or weak-only
    route, confidence = "standard", "borderline"
else:
    route, confidence = "fast", "clear"

print(json.dumps({
    "route": route, "confidence": confidence, "tripped": tripped,
    "signals": {"task_type": mt.group(1) if mt else None,
                "scope_bullets": scope_bullets, "oq_bullets": oq_bullets,
                "path_tokens": len(paths), "keywords": sorted(set(kw)),
                "wave_keywords": sorted(set(wkw)), "goal_missing": goal_missing},
}))
PY
}

self_test() {
    local p=0 f=0 d out err
    ok() { echo "  PASS: $1"; p=$((p+1)); }
    no() { echo "  FAIL: $1"; f=$((f+1)); }
    field() { echo "$1" | command jq -r "$2"; }

    echo "=== goalforge-route.sh --self-test ==="
    d="$(mktemp -d)"
    trap 'rm -rf "$d"' RETURN

    # F1: small clean goal -> fast/clear
    cat > "$d/small.md" <<'EOF'
---
name: tiny-fix
status: draft
---
## Problem

Rename one helper for clarity.

## Goal

helper renamed, callers updated, tests green.

## Scope

**In:** the rename
**Out:** everything else
EOF
    out="$(classify "$d/small.md")"
    if [[ "$(field "$out" .route)" == "fast" && "$(field "$out" .confidence)" == "clear" ]]; then
        ok "F1 small goal -> fast/clear ok"
    else no "F1 small goal -> $out"; fi

    # F2: migration task_type -> standard/clear via R1
    printf -- '---\ntask_type: migration\n---\n## Goal\n\nmove files\n' > "$d/mig.md"
    out="$(classify "$d/mig.md")"
    if [[ "$(field "$out" .route)" == "standard" && "$(field "$out" .tripped[0])" == "R1" ]]; then
        ok "F2 migration -> standard/R1 ok"
    else no "F2 migration -> $out"; fi

    # F3: many open questions -> standard/clear via R3
    printf -- '## Goal\n\nbig thing\n\n## Open Questions\n\n- a?\n- b?\n- c?\n' > "$d/oq.md"
    out="$(classify "$d/oq.md")"
    if [[ "$(field "$out" .route)" == "standard" && "$(field "$out" .tripped[0])" == "R3" ]]; then
        ok "F3 3 OQs -> standard/R3 ok"
    else no "F3 3 OQs -> $out"; fi

    # F4: keyword only -> standard/borderline (weak signal => confirm)
    printf -- '## Problem\n\ntouches auth flow\n\n## Goal\n\nsafer login copy\n' > "$d/kw.md"
    out="$(classify "$d/kw.md")"
    if [[ "$(field "$out" .route)" == "standard" && "$(field "$out" .confidence)" == "borderline" ]]; then
        ok "F4 keyword-only -> standard/borderline ok"
    else no "F4 keyword-only -> $out"; fi

    # F5: missing goal -> standard/borderline (unclassifiable)
    printf -- '## Problem\n\nsomething\n' > "$d/nogoal.md"
    out="$(classify "$d/nogoal.md")"
    if [[ "$(field "$out" .route)" == "standard" && "$(field "$out" .confidence)" == "borderline" ]]; then
        ok "F5 no goal -> standard/borderline ok"
    else no "F5 no goal -> $out"; fi

    # F6: pinned route echoed back
    printf -- '---\nroute: fast\n---\n## Goal\n\nanything at all with auth keyword\n' > "$d/pin.md"
    out="$(classify "$d/pin.md")"
    if [[ "$(field "$out" .route)" == "fast" && "$(field "$out" .confidence)" == "pinned" ]]; then
        ok "F6 pinned fast route -> echoed ok"
    else no "F6 pinned route -> $out"; fi

    # F7: >=5 path tokens -> standard via R4
    printf -- '## Goal\n\ntouch a/b.md c/d.md e/f.md g/h.md i/j.md\n' > "$d/paths.md"
    out="$(classify "$d/paths.md")"
    if [[ "$(field "$out" .route)" == "standard" && "$(field "$out" .tripped[0])" == "R4" ]]; then
        ok "F7 5 paths -> standard/R4 ok"
    else no "F7 5 paths -> $out"; fi

    # F8: parallel fan-out keyword -> wave/clear via W2
    printf -- '## Goal\n\ndeliver via parallel spec authors with cross-spec judge\n' > "$d/wavekw.md"
    out="$(classify "$d/wavekw.md")"
    if [[ "$(field "$out" .route)" == "wave" && "$(field "$out" .confidence)" == "clear" ]]; then
        ok "F8 fan-out keyword -> wave/clear ok"
    else no "F8 fan-out keyword -> $out"; fi

    # F9: >=8 scope bullets -> wave/clear via W1 (multi-feature)
    printf -- '## Goal\n\nbroad program\n\n## Scope\n\n- a\n- b\n- c\n- d\n- e\n- f\n- g\n- h\n' > "$d/wavescope.md"
    out="$(classify "$d/wavescope.md")"
    if [[ "$(field "$out" .route)" == "wave" && "$(field "$out" .confidence)" == "clear" ]]; then
        ok "F9 8 scope bullets -> wave/clear ok"
    else no "F9 8 scope bullets -> $out"; fi

    # F10: legacy pinned full -> normalizes to standard, pinned (idempotent)
    printf -- '---\nroute: full\n---\n## Goal\n\nlegacy plan\n' > "$d/legfull.md"
    out="$(classify "$d/legfull.md")"
    if [[ "$(field "$out" .route)" == "standard" && "$(field "$out" .confidence)" == "pinned" ]]; then
        ok "F10 legacy full -> standard/pinned ok"
    else no "F10 legacy full -> $out"; fi

    # F11: legacy pinned one-go -> normalizes to fast, pinned (idempotent)
    printf -- '---\nroute: one-go\n---\n## Goal\n\nsingle dispatch\n' > "$d/legonego.md"
    out="$(classify "$d/legonego.md")"
    if [[ "$(field "$out" .route)" == "fast" && "$(field "$out" .confidence)" == "pinned" ]]; then
        ok "F11 legacy one-go -> fast/pinned ok"
    else no "F11 legacy one-go -> $out"; fi

    # F12: pinned NEW-vocab standard -> echoed as-is, pinned
    printf -- '---\nroute: standard\n---\n## Goal\n\nanything\n' > "$d/pinstd.md"
    out="$(classify "$d/pinstd.md")"
    if [[ "$(field "$out" .route)" == "standard" && "$(field "$out" .confidence)" == "pinned" ]]; then
        ok "F12 pinned standard -> echoed ok"
    else no "F12 pinned standard -> $out"; fi

    # F13: pinned NEW-vocab wave -> echoed as-is, pinned
    printf -- '---\nroute: wave\n---\n## Goal\n\nanything\n' > "$d/pinwave.md"
    out="$(classify "$d/pinwave.md")"
    if [[ "$(field "$out" .route)" == "wave" && "$(field "$out" .confidence)" == "pinned" ]]; then
        ok "F13 pinned wave -> echoed ok"
    else no "F13 pinned wave -> $out"; fi

    # F14: unrecognized pinned route -> WARN on stderr, pin discarded,
    #      classification still succeeds (small clean goal -> fast/clear).
    printf -- '---\nroute: fsat\n---\n## Goal\n\nrename one helper\n' > "$d/badroute.md"
    err="$(classify "$d/badroute.md" 2>&1 >/dev/null)"
    out="$(classify "$d/badroute.md" 2>/dev/null)"
    if echo "$err" | grep -q "unrecognized route: 'fsat'" \
       && [[ "$(field "$out" .route)" == "fast" && "$(field "$out" .confidence)" == "clear" ]]; then
        ok "F14 unrecognized route -> WARN + reclassify fast/clear ok"
    else no "F14 unrecognized route -> err='$err' out='$out'"; fi

    echo ""
    echo "Results: $p passed, $f failed"
    [[ "$f" -eq 0 ]]
}

case "${1:-}" in
    --self-test) self_test; exit $? ;;
    "")          usage; exit 1 ;;
    *)           classify "$1" ;;
esac
