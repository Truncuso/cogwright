#!/usr/bin/env bash
# selection.test.sh — gates the SELECTION case bar for the six REACHABLE entries.
#
# Doctrine: docs/analysis/goalforge-design-doctrine.md §3 Item 9 (re-scoped
# 2026-09-02). Skill discovery walks one level deep, so only six entries of this
# package are on the model's selection surface: the `goalforge` front door,
# `goalforge-run`, and the four commands /spec /plan /implement /verify.
#
# This asserts case MATERIAL, not model behaviour — it does no model work and is
# safe to run in CI. Two properties per entry:
#   1. at least 3 positives AND at least 3 negatives (Item 9 bar);
#   2. every negative's expected_output names a sibling owner in backticks that
#      the RUNNER can actually put on the selection surface (T5/T6/T7). The
#      predicate mirrors runner.resolve_sibling — a directory carrying SKILL.md —
#      plus the README's command carve-out (a basename under commands/). A
#      basename that is merely a file, or a `skill_name` declared inside a
#      SKILL.md, is NOT installable and does not count: certifying one would
#      green-light a negative the model can only abstain on.
#   3. every negative under the converter's scope (*/evals/evals.json) phrases
#      its expected_output with one of convert-canonical.py's NEGATIVE_PHRASES.
#      should_trigger there is DERIVED from that prose, so a negative that
#      matches no phrase is silently reclassified as a positive on the next
#      converter run — the exact way a load-bearing case gets destroyed.
#
# The commands own no skill dir, so their cases live in evals/selection/<name>.json
# with a top-level skill_name — outside runner discovery, which keeps
# `trigger-run.sh --dry-run` at 13 canonical files.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PKG_ROOT="$(cd "$HERE/.." && pwd)"
fails=0

fail() { printf 'FAIL %s\n' "$*"; fails=$((fails + 1)); }
pass() { printf 'ok   %s\n' "$*"; }

command -v jq >/dev/null 2>&1 || { echo "FAIL jq not installed"; exit 1; }

# --- the INSTALLABLE-owner universe -----------------------------------------
# Exactly what the runner can install: a skill dir (SKILL.md present, addressed
# by its DIRECTORY basename, which is what resolve_skill_dir matches) or a
# command basename already on the surface via --commands.
universe_file="$(mktemp)"
phrase_file="$(mktemp)"
trap 'rm -f "$universe_file" "$phrase_file"' EXIT
{
    find -L "$PKG_ROOT" -mindepth 2 -name SKILL.md -printf '%h\n' 2>/dev/null | xargs -r -n1 basename
    find -L "$PKG_ROOT/commands" -maxdepth 1 -name '*.md' -printf '%f\n' 2>/dev/null | sed 's/\.md$//'
} | sort -u >"$universe_file"

resolves() { grep -qxF "$1" "$universe_file"; }

# --- the converter's negative-phrase list (single source: the converter) -----
sed -n '/^NEGATIVE_PHRASES = ($/,/^)$/p' "$HERE/convert-canonical.py" \
    | grep -o '"[^"]*"' | tr -d '"' >"$phrase_file"
[ -s "$phrase_file" ] || { echo "FAIL could not read NEGATIVE_PHRASES from convert-canonical.py"; exit 1; }

phrased() {
    local hay; hay="$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')"
    while IFS= read -r p; do
        [ -n "$p" ] || continue
        case "$hay" in *"$p"*) return 0 ;; esac
    done <"$phrase_file"
    return 1
}

# --- entry → cases file -----------------------------------------------------
# entry:relative path
entries=(
    "goalforge:evals/evals.json"
    "goalforge-run:run/evals/evals.json"
    "spec:evals/selection/spec.json"
    "plan:evals/selection/plan.json"
    "implement:evals/selection/implement.json"
    "verify:evals/selection/verify.json"
)

for pair in "${entries[@]}"; do
    entry="${pair%%:*}"
    rel="${pair#*:}"
    file="$PKG_ROOT/$rel"

    if [ ! -r "$file" ]; then
        fail "$entry: cases file missing: $rel"
        continue
    fi

    declared="$(jq -r '.skill_name // ""' "$file")"
    if [ "$declared" != "$entry" ]; then
        fail "$entry: $rel declares skill_name '$declared', expected '$entry'"
    fi

    pos="$(jq '[.evals[]? | select(.should_trigger == true)]  | length' "$file")"
    neg="$(jq '[.evals[]? | select(.should_trigger == false)] | length' "$file")"

    if [ "$pos" -ge 3 ]; then pass "$entry: $pos positives"; else fail "$entry: $pos positives (need >= 3)"; fi
    if [ "$neg" -ge 3 ]; then pass "$entry: $neg negatives"; else fail "$entry: $neg negatives (need >= 3)"; fi

    # every negative names a resolvable owner in backticks
    n=-1
    while IFS= read -r line; do
        n=$((n + 1))
        id="${line%%$'\t'*}"
        eo="${line#*$'\t'}"
        owners="$(printf '%s\n' "$eo" | grep -o '`[^`]\+`' | tr -d '`' | sort -u)"
        if [ -z "$owners" ]; then
            fail "$entry/$id: negative names no backticked owner"
            continue
        fi
        hit=0
        while IFS= read -r owner; do
            [ -n "$owner" ] || continue
            resolves "$owner" && { hit=1; break; }
        done <<<"$owners"
        if [ "$hit" -eq 1 ]; then
            pass "$entry/$id: owner installable"
        else
            fail "$entry/$id: no backticked owner is installable ($(printf '%s' "$owners" | tr '\n' ' '))"
        fi

        # under the converter's scope, the polarity is derived from this prose
        case "$rel" in
            */evals/evals.json|evals/evals.json)
                if phrased "$eo"; then
                    pass "$entry/$id: negative phrasing survives conversion"
                else
                    fail "$entry/$id: expected_output matches no NEGATIVE_PHRASE — convert-canonical.py would flip it to a positive"
                fi
                ;;
        esac
    done < <(jq -r '.evals[]? | select(.should_trigger == false)
                    | ((.id // "evals[?]") | tostring) + "\t" + (.expected_output // "")' "$file")
done

printf '\n'
if [ "$fails" -eq 0 ]; then
    echo "PASS selection.test.sh — 6/6 entries meet the 3/3 bar with installable owners"
    exit 0
fi
echo "FAIL selection.test.sh — $fails assertion(s) failed"
exit 1
