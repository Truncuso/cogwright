#!/usr/bin/env bash
# goalforge-route.sh — capture-time chain-route classifier (fast|standard).
#
# Reads a feature overview.md and emits one JSON object:
#   {"route":"fast"|"standard","confidence":"clear"|"borderline"|"pinned",
#    "tripped":["R1",...],"signals":{...}}
#
# Baseline is FAST (small clean goal). Route escalates to STANDARD when ANY
# strong signal trips:
#   R1  frontmatter task_type is migration or ops            (strong)
#   R2  bullets under ## Scope In >= SDD_ROUTE_NS (default 4) (strong)
#   R3  bullets under ## Open Questions >= SDD_ROUTE_NQ (3)  (strong)
#   R4  distinct path-like tokens in body >= SDD_ROUTE_NF (5)(strong)
#   R5  blast-radius keyword in Problem/Goal text             (weak)
#   R6  parallel/fan-out keyword in Goal + Scope In text       (strong)
# R2 counts only bullets before a bold **Out:** sub-heading under ## Scope;
# exclusions are not scope work. The wave route is retired (2026-09-27,
# ticket-84): its former signals — >=8 scope bullets (subsumed by R2) and the
# parallel/fan-out keywords (now R6) — classify `standard`, never `fast`.
#
# Confidence:
#   pinned     — a legacy plan's frontmatter still carries route: (read only;
#                capture no longer stamps it). Legacy vocab normalizes on read:
#                full->standard, one-go->fast, and the retired wave->standard
#                with one WARN line to stderr (never a silent echo). fast and
#                standard echo as-is. A route: line with an UNRECOGNIZED value (e.g. a
#                `route: fsat` typo) is not a valid pin: one WARN line to stderr,
#                the pin is discarded, and classification proceeds normally.
#   clear      — no signal (fast), or >=1 strong signal (standard).
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
    SDD_ROUTE_NF="${SDD_ROUTE_NF:-5}" \
    python3 - "$1" <<'PY'
import json, os, re, sys

path = sys.argv[1]
try:
    text = open(path, encoding="utf-8").read()
except OSError as e:
    print(f"goalforge-goal-route: cannot read {path}: {e}", file=sys.stderr)
    sys.exit(1)

NS = int(os.environ.get("SDD_ROUTE_NS", 4))
NQ = int(os.environ.get("SDD_ROUTE_NQ", 3))
NF = int(os.environ.get("SDD_ROUTE_NF", 5))

# Split frontmatter / body.
fm, body = "", text
m = re.match(r"^---\n(.*?)\n---\n(.*)$", text, re.DOTALL)
if m:
    fm, body = m.group(1), m.group(2)

# Pinned route (legacy plans only): echo back, no re-classification. Legacy
# vocab normalizes on read (full->standard, one-go->fast); the retired wave
# route remaps to standard with a WARN, never a silent echo (ticket-84).
mr = re.search(r"^route:\s*['\"]?(fast|standard|wave|full|one-go)", fm, re.MULTILINE)
if mr:
    LEGACY = {"full": "standard", "one-go": "fast", "wave": "standard"}
    route = LEGACY.get(mr.group(1), mr.group(1))
    if mr.group(1) == "wave":
        print("WARN: pinned route: 'wave' is retired (ticket-84) — remapped to "
              "standard", file=sys.stderr)
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

def in_scope_lines(lines):
    """Lines under ## Scope before a bold **Out** sub-heading. Exclusions are
    not scope work: counting them inflates R2
    (goalforge-route-scope-bullet-overcount.md:53-55)."""
    out = []
    for ln in lines:
        if re.match(r"^\s*\*\*Out:?\*\*", ln, re.IGNORECASE):
            break
        out.append(ln)
    return out

goal_lines = [l for l in section("goal") if l.strip() and not l.strip().startswith("<")]
scope_section = section("scope")
in_scope = in_scope_lines(scope_section)
scope_bullets = len(bullets(in_scope))
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

# R6: parallel/fan-out keywords (the retired wave route's W2 signal, now a
# strong standard signal). Probes Goal + Scope-In prose only, matching how R5
# probes only Problem + Goal — a hazard noted elsewhere in the body (e.g.
# Notes) is not a fan-out signal (goalforge-route-scope-bullet-overcount.md:56-58).
fanout_probe = " ".join(goal_lines + in_scope).lower()
fkw = re.findall(
    r"\b(parallel|fan[- ]?out|cross-spec|multi-feature|multiple spec\w*|concurrent\w*)\b",
    fanout_probe)
r6 = bool(fkw)

tripped = [s for s, hit in
           [("R1", r1), ("R2", r2), ("R3", r3), ("R4", r4), ("R5", r5),
            ("R6", r6)] if hit]
strong = [s for s in tripped if s in ("R1", "R2", "R3", "R4", "R6")]
goal_missing = not goal_lines

if strong:
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
                "fanout_keywords": sorted(set(fkw)), "goal_missing": goal_missing},
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

    # F8: parallel fan-out keyword (the retired wave route's W2) -> standard/clear
    #     via R6 — remapped to standard, never falling through to fast
    printf -- '## Goal\n\ndeliver via parallel spec authors with cross-spec judge\n' > "$d/fanoutkw.md"
    out="$(classify "$d/fanoutkw.md")"
    if [[ "$(field "$out" .route)" == "standard" && "$(field "$out" .confidence)" == "clear" \
          && "$(field "$out" '.tripped | index("R6")')" != "null" ]]; then
        ok "F8 fan-out keyword -> standard/clear (R6) ok"
    else no "F8 fan-out keyword -> $out"; fi

    # F9: >=8 scope bullets (the retired wave route's W1) -> standard/clear
    printf -- '## Goal\n\nbroad program\n\n## Scope\n\n- a\n- b\n- c\n- d\n- e\n- f\n- g\n- h\n' > "$d/widescope.md"
    out="$(classify "$d/widescope.md")"
    if [[ "$(field "$out" .route)" == "standard" && "$(field "$out" .confidence)" == "clear" ]]; then
        ok "F9 8 scope bullets -> standard/clear ok"
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

    # F13: pinned legacy wave (route retired, ticket-84) -> WARN + remapped
    #      to standard, pinned — never a silent echo of the retired value
    printf -- '---\nroute: wave\n---\n## Goal\n\nanything\n' > "$d/pinwave.md"
    err="$(classify "$d/pinwave.md" 2>&1 >/dev/null)"
    out="$(classify "$d/pinwave.md" 2>/dev/null)"
    if echo "$err" | grep -q "route: 'wave' is retired" \
       && [[ "$(field "$out" .route)" == "standard" && "$(field "$out" .confidence)" == "pinned" ]]; then
        ok "F13 pinned wave -> WARN + standard/pinned ok"
    else no "F13 pinned wave -> err='$err' out='$out'"; fi

    # F14: unrecognized pinned route -> WARN on stderr, pin discarded,
    #      classification still succeeds (small clean goal -> fast/clear).
    printf -- '---\nroute: fsat\n---\n## Goal\n\nrename one helper\n' > "$d/badroute.md"
    err="$(classify "$d/badroute.md" 2>&1 >/dev/null)"
    out="$(classify "$d/badroute.md" 2>/dev/null)"
    if echo "$err" | grep -q "unrecognized route: 'fsat'" \
       && [[ "$(field "$out" .route)" == "fast" && "$(field "$out" .confidence)" == "clear" ]]; then
        ok "F14 unrecognized route -> WARN + reclassify fast/clear ok"
    else no "F14 unrecognized route -> err='$err' out='$out'"; fi

    # F15: regression for handoff-thread-layout false positive
    #      (plans/ideas/goalforge-route-scope-bullet-overcount.md). 6 In +
    #      5 Out scope bullets (In-scope alone trips R2, not W1) and a
    #      coordination-hazard sentence with "parallel" outside Goal/Scope
    #      (in Notes). Must route standard/clear with R6 untripped.
    cat > "$d/handoff.md" <<'EOF'
## Goal

ship a layout in four sequential steps

## Scope

**In:**

- item1
- item2
- item3
- item4
- item5
- item6

**Out:**

- excl1
- excl2
- excl3
- excl4
- excl5

## Notes

A parallel session was appending to this file; confirm no live session holds
it before migrating.
EOF
    out="$(classify "$d/handoff.md")"
    if [[ "$(field "$out" .route)" == "standard" && "$(field "$out" .confidence)" == "clear" \
          && "$(field "$out" .signals.scope_bullets)" == "6" \
          && "$(field "$out" '.tripped | index("R6")')" == "null" ]]; then
        ok "F15 handoff-thread-layout regression -> standard/clear (In-only scope, R6 scoped) ok"
    else no "F15 handoff-thread-layout regression -> $out"; fi

    echo ""
    echo "Results: $p passed, $f failed"
    [[ "$f" -eq 0 ]]
}

case "${1:-}" in
    --self-test) self_test; exit $? ;;
    "")          usage; exit 1 ;;
    *)           classify "$1" ;;
esac
