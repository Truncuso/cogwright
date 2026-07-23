#!/usr/bin/env bash
# goalforge-learning-route.sh — capture-learning Phase-1 leg for the SDD verify boundary.
#
# At the WP `executing → verified` boundary, goalforge-verify shells out here with the
# verified fix's root-cause/contrast (+ an optional strategic candidate). This
# script does the DETERMINISTIC plumbing only: it emits a tactical detection
# record and flags whether a strategic candidate is present. The SEMANTIC
# L1/L2/L3 classification is capture-learning's job (invoked via goalforge-verify
# prose, NOT here).
#
# Usage:
#   goalforge-learning-route.sh --wp <path> --fix "..." --cause "..." --contrast "..." \
#       [--strategic "..." [--dest <idea-capture|skill-improve|memory|rules>]] [--dry-run]
#   goalforge-learning-route.sh --detect-only --wp <path> --fix "..." ...   # detection record ONLY
#       (pure/stdout-only: runs detect_boundary, no tactical/strategic write — exits 0)
#   goalforge-learning-route.sh --boundary-smoke      # task-01 self-test (detection leg)
#   goalforge-learning-route.sh --self-test           # task-02 self-test (full routing + no-commit)
#
# Args:
#   --wp <path>        Verifying WP folder; its findings.md is the tactical sink.
#   --fix "..."        One-line tactical fix that was verified.
#   --cause "..."      Root cause the fix addresses.
#   --contrast "..."   Passing-vs-failing contrast for the fix.
#   --strategic "..."  OPTIONAL candidate strategic insight (routed propose-only).
#   --dest <...>       OPTIONAL resolved destination for --strategic
#                      (idea-capture|skill-improve|memory|rules). The AGENT supplies it
#                      after capture-learning's classifier resolves the class — this
#                      script does NOT classify. Absent/unknown → OQ-C nudge/surface.
#   --dry-run          Propose-only; ALWAYS the default — there is no --commit flag.
#
# DEGRADE-NOT-BLOCK: a missing optional input, an absent findings.md, an
#   unreachable capture-learning skill, or a missing WP dir all no-op gracefully
#   and exit 0 — this runs at the verify boundary and must NEVER fail the verify.
#   With no fix at the boundary (nothing to detect) it is a clean no-op, exit 0.
#
# Dual-capture (two INDEPENDENT legs — neither ever gates the other): the tactical fix is
#   appended to <wp>/findings.md (the local provenance sink, the same file goalforge-harden/execute
#   append to — NOT a commit) whenever a fix is present; a strategic insight is routed
#   PROPOSE-ONLY (stdout) to the resolved --dest, never mutating a destination file and never
#   running git. Classification (which dest) is capture-learning's job, reused — this script
#   only routes given --dest; an absent/unknown --dest yields a nudge/surface record.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SELF="$SCRIPT_DIR/$(basename "${BASH_SOURCE[0]}")"

usage() {
    # Print the header comment block (lines after the shebang up to `set -euo
    # pipefail`), stripping the leading "# ". Robust to header growth — this is a
    # co-owned two-task file, so a hard-coded line range would drift.
    awk 'NR==1 { next } /^set -euo pipefail$/ { exit } { sub(/^# ?/, ""); print }' "$SELF"
}

# ── Boundary-detection leg ──────────────────────────────────────────────────────
# Deterministic plumbing only: emit the tactical detection record + flag a
# strategic candidate. Never writes (task-02 owns the findings.md/route writes);
# always returns 0 (degrade-not-block — must not fail the verify).
detect_boundary() {
    local wp="$1" fix="$2" cause="$3" contrast="$4" strategic="$5"

    # No fix at the boundary → clean no-op (a WP whose verify carried no bugfix).
    if [[ -z "$fix" && -z "$cause" && -z "$contrast" ]]; then
        echo "learning-route: no tactical fix at this boundary — nothing to detect."
        return 0
    fi

    # Resolve the tactical sink (findings.md) WITHOUT writing it — task-02 writes.
    local sink sink_state
    if [[ -n "$wp" && -d "$wp" ]]; then
        sink="$wp/findings.md"
        if [[ -f "$sink" ]]; then sink_state="present"; else sink_state="absent (degraded)"; fi
    elif [[ -n "$wp" ]]; then
        sink="$wp/findings.md"; sink_state="wp-dir-absent (degraded)"
    else
        sink="(none)"; sink_state="no-wp (degraded)"
    fi

    # Strategic candidate: presence-only flag — semantic L1/L2/L3 is capture-learning's job.
    local strategic_flag="absent"
    [[ -n "$strategic" ]] && strategic_flag="present"

    # capture-learning reachability (informational; routing is task-02). Env override
    # lets the smoke test exercise the unreachable-degrade path.
    local cl="${SDD_CAPTURE_LEARNING_SKILL:-$SCRIPT_DIR/../../capture-learning/SKILL.md}"
    local cl_state="unreachable (degraded)"
    [[ -f "$cl" ]] && cl_state="reachable"

    # Detection record — stdout only; detect_boundary never writes (the route legs do).
    cat <<EOF
## learning-route detection
wp: ${wp:-(none)}
tactical-fix: $fix
root-cause: $cause
contrast: $contrast
strategic-candidate: $strategic_flag
findings-sink: $sink [$sink_state]
capture-learning: $cl_state
route: dual-capture (tactical → findings.md [recorded]; strategic → propose-only [no commit])
EOF
    return 0
}

# ── Tactical leg: append the verified fix to the WP's findings.md ───────────────
# findings.md is the local provenance sink (NOT a commit). The fix/cause/contrast may
# carry newlines or markdown metacharacters; they are FLATTENED to single lines so they
# can never inject a `## ` header or a `---` frontmatter rule and corrupt the file. The
# entry is keyed on a hash of the fix and UPSERTED — a re-run updates in place, never
# duplicate-appends. Absent findings.md → propose-only (do NOT create; goalforge-harden owns
# creation). Any write failure degrades to a note — never fails the verify.
route_tactical() {
    local wp="$1" fix="$2" cause="$3" contrast="$4"
    local sink="$wp/findings.md"
    if [[ -z "$wp" || ! -d "$wp" || ! -f "$sink" ]]; then
        echo "## learning-route tactical (propose-only)"
        echo "proposed-append: ${sink:-<wp>/findings.md} — findings.md absent; NOT written (degrade-not-block)"
        echo "fix: ${fix//$'\n'/\\n}"
        return 0
    fi
    if ! python3 - "$sink" "$(date +%F)" "$fix" "$cause" "$contrast" <<'PY'
import sys, re, hashlib
from pathlib import Path

sink = Path(sys.argv[1]); today = sys.argv[2]
fix, cause, contrast = sys.argv[3], sys.argv[4], sys.argv[5]

def flat(s):
    # Collapse to one line so an embedded "## " / "---" cannot corrupt findings.md.
    return s.replace("\r\n", "\n").replace("\r", "\n").replace("\n", "\\n").strip()

fixf, causef, contrastf = flat(fix), flat(cause), flat(contrast)
key = hashlib.sha1(fixf.encode("utf-8")).hexdigest()[:8]

block = "\n".join([
    "## [%s] Learning (tactical): %s" % (today, key),
    "fix: %s" % fixf,
    "root-cause: %s" % causef,
    "contrast: %s" % contrastf,
])

text = sink.read_text(encoding="utf-8")
flines = text.split("\n")
hdr = re.compile(r"^##\s+\[[^\]]*\]\s+Learning \(tactical\):\s+" + re.escape(key) + r"\s*$")
start = None
for i, l in enumerate(flines):
    if hdr.match(l):
        start = i; break
if start is None:
    body = text.rstrip("\n")
    new = (body + "\n\n" + block + "\n") if body else (block + "\n")
else:
    end = len(flines)
    for j in range(start + 1, len(flines)):
        if flines[j].startswith("## "):
            end = j; break
    before, after = flines[:start], flines[end:]
    while before and before[-1].strip() == "": before.pop()
    while after and after[0].strip() == "": after.pop(0)
    chunks = []
    if before: chunks.append("\n".join(before))
    chunks.append(block)
    if after: chunks.append("\n".join(after))
    new = "\n\n".join(chunks) + "\n"
sink.write_text(new, encoding="utf-8")
print("learning-route tactical: recorded fix [%s] to %s" % (key, sink))
PY
    then
        echo "learning-route tactical: write skipped (findings.md unwritable) — degrade-not-block." >&2
    fi
    return 0
}

# ── Strategic leg: propose-only routing record (stdout) ─────────────────────────
# NEVER mutates a destination file; NEVER runs git. A resolved --dest names the
# destination + describes the proposed write; an absent/unknown --dest emits the OQ-C
# nudge/surface record instead of guessing a destination. The script does no L1/L2/L3
# classification — capture-learning resolves the class and the agent passes --dest.
route_strategic() {
    local strategic="$1" dest="$2" dest_ok="$3"
    local insight="${strategic//$'\r'/}"; insight="${insight//$'\n'/\\n}"
    echo "## learning-route strategic (propose-only)"
    echo "insight: $insight"
    if [[ "$dest_ok" -eq 1 ]]; then
        local proposed
        case "$dest" in
            idea-capture)  proposed="plans/ideas/<slug>.md — capture an idea stub (idea-capture)" ;;
            skill-improve) proposed="/skill-improve — fold into a skill's gotchas/evals/description" ;;
            memory)        proposed=".memory/{project,global}/<type>/<slug>.md — a typed memory fact" ;;
            rules)         proposed="rules/ (L2) or a CLAUDE.md guardrail — a durable project rule" ;;
        esac
        echo "destination: $dest"
        echo "proposed-write: $proposed"
    else
        echo "destination: (unresolved)"
        echo "proposed-write: NUDGE — review-and-route this insight (OQ-C: no/unknown --dest; capture-learning resolves the class)"
    fi
    echo "no-commit: propose-only — no destination file mutated, no git action taken"
    return 0
}

# ── route mode: detection record (task-01) + dual-capture legs (task-02) ────────
# Always exits 0 (degrade-not-block — must not fail the verify).
do_route() {
    local wp="$1" fix="$2" cause="$3" contrast="$4" strategic="$5" dest="$6"
    local dest_ok=0
    case "$dest" in idea-capture|skill-improve|memory|rules) dest_ok=1 ;; esac

    # 1) detection record — always emitted.
    detect_boundary "$wp" "$fix" "$cause" "$contrast" "$strategic"

    # 2) tactical leg → record the fix to findings.md. INDEPENDENT of the strategic leg:
    #    the tactical log is written whenever there is a fix, never gated on strategic
    #    routing (the dual-capture goal requires the two legs to be orthogonal).
    if [[ -n "$fix" ]]; then
        route_tactical "$wp" "$fix" "$cause" "$contrast"
    fi

    # 3) strategic leg → propose-only routing record (or nudge when --dest is unresolved).
    if [[ -n "$strategic" ]]; then
        route_strategic "$strategic" "$dest" "$dest_ok"
    fi
    return 0
}

# ── --self-test (task-02): full routing suite + no-commit proof ─────────────────
_ST2_TMP=""
self_test() {
    local t_pass=0 t_fail=0 d
    local _OUT _RC
    _ST2_TMP="$(mktemp -d)"
    trap '[[ -n "${_ST2_TMP:-}" ]] && rm -rf "$_ST2_TMP"' EXIT
    d="$_ST2_TMP"

    ok() { echo "$1: PASS"; t_pass=$((t_pass+1)); }
    no() { echo "$1: FAIL — $2"; t_fail=$((t_fail+1)); }
    run_cap() { if _OUT="$("$@" 2>&1)"; then _RC=0; else _RC=$?; fi; }
    # findings v4 seed with a trailing sentinel that must survive every append.
    seed_findings() {
        cat > "$1" << 'EOF'
<!-- Template: findings v4 (frontmatter-first, flat layout) -->
---
name: fixture-findings
title: fixture findings
updated: 2026-06-24
---

## [2026-06-24] Sentinel: keep-me
Decision: this trailing entry must survive every tactical append intact.
EOF
    }

    echo "=== goalforge-learning-route.sh --self-test ==="

    # ── (a) tactical append ACTUALLY lands the entry in findings.md ──
    local wpT="$d/wp-tactical"; mkdir -p "$wpT"; seed_findings "$wpT/findings.md"
    run_cap bash "$SELF" --wp "$wpT" \
        --fix "added null-guard before deref" \
        --cause "pointer was nil on the empty-input path" \
        --contrast "non-empty input never reached the deref"
    if [[ "$_RC" -eq 0 ]] \
        && grep -q '^## \[.*\] Learning (tactical):' "$wpT/findings.md" \
        && grep -q '^fix: added null-guard before deref$' "$wpT/findings.md" \
        && grep -q '^root-cause: pointer was nil on the empty-input path$' "$wpT/findings.md" \
        && grep -q '^contrast: non-empty input never reached the deref$' "$wpT/findings.md" \
        && grep -q '^## \[2026-06-24\] Sentinel: keep-me$' "$wpT/findings.md"; then
        ok "tactical-append-lands"
    else
        no "tactical-append-lands" "rc=$_RC findings=$(tr '\n' '|' < "$wpT/findings.md")"
    fi

    # ── (b) multiline fix/cause/contrast must NOT corrupt findings.md (wp-06 regression) ──
    # Embed a header-like and a frontmatter-like line; run TWICE (idempotent-safe).
    local wpM="$d/wp-multiline"; mkdir -p "$wpM"; seed_findings "$wpM/findings.md"
    local ml_fix=$'line one\n## injected header\n---\nline three'
    run_cap bash "$SELF" --wp "$wpM" --fix "$ml_fix" --cause $'cause\nwith newline' --contrast "single line"
    run_cap bash "$SELF" --wp "$wpM" --fix "$ml_fix" --cause $'cause\nwith newline' --contrast "single line"
    # grep -c exits 1 when the count is 0 (the expected case for `inj`); `|| true`
    # keeps set -e from aborting — grep still prints the count on stdout.
    local fm inj sentinel keyed
    fm="$(grep -c '^---$' "$wpM/findings.md" || true)"                          # exactly 2 (frontmatter pair only)
    inj="$(grep -c '^## injected header$' "$wpM/findings.md" || true)"          # 0 (flattened, not a header)
    sentinel="$(grep -c '^## \[2026-06-24\] Sentinel: keep-me$' "$wpM/findings.md" || true)"  # 1 (survives)
    keyed="$(grep -c '^## \[.*\] Learning (tactical):' "$wpM/findings.md" || true)"           # 1 (idempotent re-run)
    if [[ "$_RC" -eq 0 && "$fm" == "2" && "$inj" == "0" && "$sentinel" == "1" && "$keyed" == "1" ]] \
        && grep -q 'fix: line one\\n## injected header\\n---\\nline three' "$wpM/findings.md"; then
        ok "tactical-multiline-no-corruption"
    else
        no "tactical-multiline-no-corruption" "fm=$fm inj=$inj sentinel=$sentinel keyed=$keyed rc=$_RC"
    fi

    # ── tactical degrade: findings.md absent → propose-only, no write, exit 0 ──
    local wpN="$d/wp-nofindings"; mkdir -p "$wpN"
    run_cap bash "$SELF" --wp "$wpN" --fix "f" --cause "c" --contrast "k"
    if [[ "$_RC" -eq 0 ]] && grep -q 'tactical (propose-only)' <<<"$_OUT" && [[ ! -f "$wpN/findings.md" ]]; then
        ok "tactical-absent-findings-proposes"
    else
        no "tactical-absent-findings-proposes" "rc=$_RC created=$([[ -f "$wpN/findings.md" ]] && echo yes || echo no)"
    fi

    # ── (c) each --dest value emits the correct propose-only routing record ──
    local dest
    for dest in idea-capture skill-improve memory rules; do
        run_cap bash "$SELF" --wp "$wpT" --fix "f" --cause "c" --contrast "k" \
            --strategic "extract a reusable guard helper" --dest "$dest"
        if [[ "$_RC" -eq 0 ]] \
            && grep -q '^## learning-route strategic (propose-only)$' <<<"$_OUT" \
            && grep -q "^destination: $dest$" <<<"$_OUT" \
            && grep -q '^proposed-write: ' <<<"$_OUT" \
            && grep -q '^no-commit: propose-only' <<<"$_OUT"; then
            ok "strategic-dest-$dest-propose-record"
        else
            no "strategic-dest-$dest-propose-record" "rc=$_RC out=$(printf '%s' "$_OUT" | tr '\n' '|')"
        fi
    done

    # ── (d) --dest absent → nudge/surface record; unknown --dest → same. In BOTH the
    #        tactical leg is INDEPENDENT and must still land its entry (pins BLOCK-1: the
    #        removed hold can never silently return — strategic ambiguity ≠ tactical hold). ──
    run_cap bash "$SELF" --wp "$wpT" --fix "nodest-tactical-fix" --cause "c" --contrast "k" \
        --strategic "some ambiguous insight"
    if [[ "$_RC" -eq 0 ]] && grep -q '^destination: (unresolved)$' <<<"$_OUT" && grep -q 'NUDGE' <<<"$_OUT" \
        && grep -q '^fix: nodest-tactical-fix$' "$wpT/findings.md"; then
        ok "strategic-no-dest-nudges-and-tactical-lands"
    else
        no "strategic-no-dest-nudges-and-tactical-lands" "rc=$_RC out=$(printf '%s' "$_OUT" | tr '\n' '|')"
    fi
    run_cap bash "$SELF" --wp "$wpT" --fix "unknowndest-tactical-fix" --cause "c" --contrast "k" \
        --strategic "x" --dest bogus-destination
    if [[ "$_RC" -eq 0 ]] && grep -q '^destination: (unresolved)$' <<<"$_OUT" && grep -q 'NUDGE' <<<"$_OUT" \
        && grep -q '^fix: unknowndest-tactical-fix$' "$wpT/findings.md"; then
        ok "strategic-unknown-dest-nudges-and-tactical-lands"
    else
        no "strategic-unknown-dest-nudges-and-tactical-lands" "rc=$_RC out=$(printf '%s' "$_OUT" | tr '\n' '|')"
    fi

    # ── (e) NO-COMMIT proof: strategic routing mutates NOTHING outside <wp>/findings.md
    #        and never commits. The fixture HAS a findings.md, so the tactical leg DOES
    #        write it (expected, allowed — the local sink). The proof asserts (i) commit
    #        count unchanged, (ii) NO new files created under the destination dirs
    #        (full listing diff, catches a brand-new file the seed-md5 check would miss),
    #        (iii) seed destination files byte-unchanged. ──
    if command -v git >/dev/null 2>&1; then
        local repo="$d/repo"; mkdir -p "$repo/plans/ideas" "$repo/.memory"
        printf 'pre-existing idea stub\n' > "$repo/plans/ideas/seed.md"
        printf 'pre-existing memory fact\n' > "$repo/.memory/seed.md"
        seed_findings "$repo/findings.md"   # tactical WILL write here — expected, not a violation
        ( git -C "$repo" init -q \
            && git -C "$repo" config user.email t@example.com \
            && git -C "$repo" config user.name tester \
            && git -C "$repo" add -A \
            && git -C "$repo" commit -qm "seed" ) >/dev/null 2>&1 || true
        local commits_before listing_before md5_before commits_after listing_after md5_after
        commits_before="$(git -C "$repo" rev-list --count HEAD 2>/dev/null || echo 0)"
        listing_before="$(find "$repo/plans/ideas" "$repo/.memory" -type f | sort)"
        md5_before="$(md5sum "$repo/plans/ideas/seed.md" "$repo/.memory/seed.md")"
        ( cd "$repo" && bash "$SELF" --wp "$repo" --fix "f" --cause "c" --contrast "k" \
            --strategic "should stay propose-only" --dest idea-capture ) >/dev/null 2>&1 || true
        ( cd "$repo" && bash "$SELF" --wp "$repo" --fix "f2" --cause "c2" --contrast "k2" \
            --strategic "also propose-only" --dest memory ) >/dev/null 2>&1 || true
        commits_after="$(git -C "$repo" rev-list --count HEAD 2>/dev/null || echo 0)"
        listing_after="$(find "$repo/plans/ideas" "$repo/.memory" -type f | sort)"
        md5_after="$(md5sum "$repo/plans/ideas/seed.md" "$repo/.memory/seed.md")"
        if [[ "$commits_before" == "$commits_after" \
              && "$listing_before" == "$listing_after" \
              && "$md5_before" == "$md5_after" ]] \
            && grep -q '^## \[.*\] Learning (tactical):' "$repo/findings.md"; then
            ok "no-commit-no-dest-mutation"
        else
            no "no-commit-no-dest-mutation" "commits $commits_before->$commits_after; new-dest-files=$([[ "$listing_before" == "$listing_after" ]] && echo no || echo yes); seed-md5-changed=$([[ "$md5_before" == "$md5_after" ]] && echo no || echo yes)"
        fi
    else
        ok "no-commit-no-dest-mutation (skipped: git unavailable)"
    fi

    echo ""
    echo "Results: $t_pass passed, $t_fail failed"
    [[ "$t_fail" -eq 0 ]]
}

# ── --boundary-smoke self-test (task-01) ────────────────────────────────────────
_ST_TMP=""
boundary_smoke() {
    local t_pass=0 t_fail=0 d
    local _OUT _RC
    _ST_TMP="$(mktemp -d)"
    trap '[[ -n "${_ST_TMP:-}" ]] && rm -rf "$_ST_TMP"' EXIT
    d="$_ST_TMP"

    ok() { echo "$1: PASS"; t_pass=$((t_pass+1)); }
    no() { echo "$1: FAIL — $2"; t_fail=$((t_fail+1)); }
    # run_cap <args...> — capture stdout+stderr in _OUT, exit code in _RC; never aborts.
    run_cap() { if _OUT="$("$@" 2>&1)"; then _RC=0; else _RC=$?; fi; }

    echo "=== goalforge-learning-route.sh --boundary-smoke ==="

    # ── Fixture A: a WP dir WITH findings.md (mirrors the real layout) ──
    local wpA="$d/wp-01-fixture"
    mkdir -p "$wpA"
    cat > "$wpA/findings.md" << 'EOF'
<!-- Template: findings v4 (frontmatter-first, flat layout) -->
---
name: wp-01-fixture-findings
title: wp-01-fixture findings
updated: 2026-06-24
---
EOF

    # A reachable (existing) capture-learning skill fixture, so the detection test
    # exercises the `reachable` branch (not just the unreachable-degrade one below).
    local clOK="$d/capture-learning/SKILL.md"
    mkdir -p "$d/capture-learning"; : > "$clOK"

    # ── (i) detection leg (--detect-only) fires + emits the expected record ──
    # The detection invariant lives in the dedicated --detect-only mode: detect_boundary
    # is pure/stdout-only. Capture findings.md md5 around the SAME --detect-only run to
    # prove purity (this no longer depends on route-mode behavior — route DOES write now).
    local pre post
    pre="$(md5sum "$wpA/findings.md")"
    run_cap env SDD_CAPTURE_LEARNING_SKILL="$clOK" bash "$SELF" --detect-only --wp "$wpA" \
        --fix "guard nil sink before append" \
        --cause "findings.md absent on first verify" \
        --contrast "passing run had the file; failing run did not" \
        --strategic "verify boundary should own sink creation"
    post="$(md5sum "$wpA/findings.md")"
    if [[ "$_RC" -eq 0 ]] \
        && grep -q '^## learning-route detection$' <<<"$_OUT" \
        && grep -q '^tactical-fix: guard nil sink before append$' <<<"$_OUT" \
        && grep -q '^root-cause: findings.md absent on first verify$' <<<"$_OUT" \
        && grep -q '^contrast: passing run had the file' <<<"$_OUT" \
        && grep -q '^strategic-candidate: present$' <<<"$_OUT" \
        && grep -q '^capture-learning: reachable' <<<"$_OUT"; then
        ok "detection-leg-fires-emits-record"
    else
        no "detection-leg-fires-emits-record" "rc=$_RC out=$(printf '%s' "$_OUT" | tr '\n' '|')"
    fi

    # ── purity guard: the --detect-only leg must not mutate findings.md ──
    if [[ "$pre" == "$post" ]]; then
        ok "detection-never-writes-findings"
    else
        no "detection-never-writes-findings" "findings.md mutated by --detect-only (must be stdout-only)"
    fi

    # ── tactical-only: --strategic omitted → strategic-candidate: absent ──
    run_cap bash "$SELF" --wp "$wpA" --fix "f" --cause "c" --contrast "k"
    if [[ "$_RC" -eq 0 ]] && grep -q '^strategic-candidate: absent$' <<<"$_OUT"; then
        ok "strategic-flag-absent-when-omitted"
    else
        no "strategic-flag-absent-when-omitted" "rc=$_RC out=$(printf '%s' "$_OUT" | tr '\n' '|')"
    fi

    # ── (ii) degrade-not-block: findings.md MISSING → still exit 0, sink flagged absent ──
    local wpB="$d/wp-02-no-findings"
    mkdir -p "$wpB"
    run_cap bash "$SELF" --wp "$wpB" --fix "f" --cause "c" --contrast "k"
    if [[ "$_RC" -eq 0 ]] && grep -q '^findings-sink: .*\[absent' <<<"$_OUT"; then
        ok "degrade-missing-findings-exits-0"
    else
        no "degrade-missing-findings-exits-0" "rc=$_RC out=$(printf '%s' "$_OUT" | tr '\n' '|')"
    fi

    # ── degrade-not-block: capture-learning skill unreachable → still exit 0 ──
    run_cap env SDD_CAPTURE_LEARNING_SKILL="$d/does-not-exist/SKILL.md" \
        bash "$SELF" --wp "$wpA" --fix "f" --cause "c" --contrast "k"
    if [[ "$_RC" -eq 0 ]] && grep -q '^capture-learning: unreachable' <<<"$_OUT"; then
        ok "degrade-capture-learning-unreachable-exits-0"
    else
        no "degrade-capture-learning-unreachable-exits-0" "rc=$_RC out=$(printf '%s' "$_OUT" | tr '\n' '|')"
    fi

    # ── degrade-not-block: WP dir absent → still exit 0 (never crash the verify) ──
    run_cap bash "$SELF" --wp "$d/no-such-wp" --fix "f" --cause "c" --contrast "k"
    if [[ "$_RC" -eq 0 ]] && grep -q 'wp-dir-absent' <<<"$_OUT"; then
        ok "degrade-missing-wp-dir-exits-0"
    else
        no "degrade-missing-wp-dir-exits-0" "rc=$_RC out=$(printf '%s' "$_OUT" | tr '\n' '|')"
    fi

    # ── degrade-not-block: no --wp flag at all → still exit 0, sink flagged no-wp ──
    run_cap bash "$SELF" --fix "f" --cause "c" --contrast "k"
    if [[ "$_RC" -eq 0 ]] && grep -q 'no-wp' <<<"$_OUT"; then
        ok "degrade-no-wp-flag-exits-0"
    else
        no "degrade-no-wp-flag-exits-0" "rc=$_RC out=$(printf '%s' "$_OUT" | tr '\n' '|')"
    fi

    # ── no fix at the boundary → clean no-op, exit 0 ──
    run_cap bash "$SELF" --wp "$wpA"
    if [[ "$_RC" -eq 0 ]] && grep -q 'nothing to detect' <<<"$_OUT"; then
        ok "no-fix-clean-noop-exits-0"
    else
        no "no-fix-clean-noop-exits-0" "rc=$_RC out=$(printf '%s' "$_OUT" | tr '\n' '|')"
    fi

    echo ""
    echo "Results: $t_pass passed, $t_fail failed"
    [[ "$t_fail" -eq 0 ]]
}

# ── Argument parsing ──────────────────────────────────────────────────────────
MODE="route"
WP="" FIX="" CAUSE="" CONTRAST="" STRATEGIC="" DEST=""
DRY_RUN=1   # propose-only is ALWAYS the default; the strategic leg honors it. No --commit exists.

while [[ $# -gt 0 ]]; do
    case "$1" in
        --wp)             shift; WP="${1:-}"; shift ;;
        --fix)            shift; FIX="${1:-}"; shift ;;
        --cause)          shift; CAUSE="${1:-}"; shift ;;
        --contrast)       shift; CONTRAST="${1:-}"; shift ;;
        --strategic)      shift; STRATEGIC="${1:-}"; shift ;;
        --dest)           shift; DEST="${1:-}"; shift ;;
        --dry-run)        DRY_RUN=1; shift ;;
        --detect-only)    MODE="detect-only"; shift ;;
        --boundary-smoke) MODE="boundary-smoke"; shift ;;
        --self-test)      MODE="self-test"; shift ;;
        -h|--help)        usage; exit 0 ;;
        --*)              echo "ERROR: unknown flag: $1" >&2; exit 1 ;;
        *)                echo "ERROR: unexpected argument: $1" >&2; exit 1 ;;
    esac
done

case "$MODE" in
    boundary-smoke) boundary_smoke; exit $? ;;
    self-test)      self_test; exit $? ;;
    # detect-only: pure detection record, no tactical/strategic write — isolates the
    # detection invariant (detect_boundary is stdout-only). Always exits 0.
    detect-only)    detect_boundary "$WP" "$FIX" "$CAUSE" "$CONTRAST" "$STRATEGIC" || true; exit 0 ;;
    # route always exits 0 — degrade-not-block, must never fail the verify boundary.
    route)          do_route "$WP" "$FIX" "$CAUSE" "$CONTRAST" "$STRATEGIC" "$DEST" || true; exit 0 ;;
esac
