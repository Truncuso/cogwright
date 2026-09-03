#!/usr/bin/env bash
# selection.test.sh — gates the SELECTION case bar for the six REACHABLE entries.
#
# Doctrine: docs/analysis/goalforge-design-doctrine.md §3 Item 9 (re-scoped
# 2026-09-02). Skill discovery walks one level deep, so only six entries of this
# package are on the model's selection surface: the `goalforge` front door,
# `goalforge-run`, and the four commands /spec /plan /implement /verify.
#
# This asserts case MATERIAL, not model behaviour — it does no model work and is
# safe to run in CI. Four properties per entry:
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
#   4. every POSITIVE prompt names its argument LITERALLY — a `plans/` path, a
#      `wp-NN` id, or a backticked feature/WP name. This is the twin of rule 2:
#      an owner must be installable, an argument must be literal. The selection
#      surface is cwd=/tmp with `--tools Skill` and no Read, so a prompt that
#      refers to its argument deictically ("the current feature's spec", "the
#      work package I just finished") names something the model cannot resolve;
#      it asks for the missing argument and emits no `Skill` call at all. The
#      2026-09-02 baseline measured that directly: 16 of 20 positives abstained,
#      and substituting a concrete path into plan/sel-pos-decompose-and-harden
#      flipped it from abstain to a `plan` hit. A deictic positive therefore
#      measures the harness's blindness, not the skill's description.
#
# The commands own no skill dir, so their cases live in evals/selection/<name>.json
# with a top-level skill_name — outside runner discovery, which keeps
# `trigger-run.sh --dry-run` at 13 canonical files.
#
# A sixth property is asserted after the four, over the committed reports rather
# than the cases: every report in the NEWEST dated evals/reports/selection-*
# directory must carry the config_dir.content_hash that the current tree emits
# (`trigger-run.sh --suite <n> --dry-run --with-siblings`). A report is a
# measurement of a SURFACE; if the tree moved between the run and the commit, the
# numbers describe a surface no commit reproduces and every gain claimed from them
# is unfalsifiable. Older directories are historical and skipped OUT LOUD.
#
# A fifth property is asserted before any of the four: evals/suites.txt — the
# roster this test and trigger-run.sh --all both read — covers EXACTLY the
# discovered evals.json names ∪ the commands/*.md basenames, with every row
# backed by a real file. That is the staleness gate; the entries scored below are
# derived from it, so the list cannot drift from the tree in silence.
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

# --- the LITERAL-ARGUMENT predicate (positive side) --------------------------
# A positive prompt must carry its argument in the prompt text: a plans/ path, a
# wp-NN id, or a backticked feature/WP name. Nothing else is resolvable on a
# Skill-only surface rooted at an empty cwd.
literal_arg() { printf '%s' "$1" | grep -Eq 'plans/|wp-[0-9]+|`[^`]+`'; }

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

# --- STALENESS GATE: suites.txt vs the live tree -----------------------------
# suites.txt is the roster both this test and trigger-run.sh read. It must cover
# EXACTLY the union of two name sets:
#
#   discovery — every evals/evals.json under the package, named by its
#               dir-two-levels-up basename (runner.py's p.parent.parent.name,
#               which for the package's own evals/ is `goalforge`);
#   commands  — every commands/<name>.md basename.
#
# `spec` and `verify` are in both. The command wins — runner.py:377-378 skips
# installing a same-named skill dir beside a command — so each is ONE name with
# ONE row, and the nested spec/ verify/ case files stay census material under it.
# That is doctrine H1 in operation: under a nested package, "has evals/evals.json"
# is a case-file location convention, not a selectability claim.
#
# A missing row (new child, new command) and a row whose backing file is gone are
# both failures. `wayfind` is the third case: it owns commands/wayfind.md, so it
# IS a claimant, but ships evals/e2e.sh and no trigger cases (doctrine:1015). It
# is allowlisted as status=pending — said out loud, never silence.
SUITES_FILE="$HERE/suites.txt"
roster_file="$(mktemp)"
expected_file="$(mktemp)"
trap 'rm -f "$universe_file" "$phrase_file" "$roster_file" "$expected_file"' EXIT

if [ ! -r "$SUITES_FILE" ]; then
    fail "suites.txt missing at $SUITES_FILE"
else
    awk 'NF && $1 !~ /^#/ { print $1 }' "$SUITES_FILE" | sort >"$roster_file"
    dupes="$(uniq -d "$roster_file" | tr '\n' ' ')"
    [ -z "${dupes// /}" ] || fail "suites.txt: duplicate rows: $dupes"

    {
        find -L "$PKG_ROOT" -name evals.json -path '*/evals/evals.json' -printf '%h\n' 2>/dev/null \
            | xargs -r -n1 dirname | xargs -r -n1 basename
        find -L "$PKG_ROOT/commands" -maxdepth 1 -name '*.md' -printf '%f\n' 2>/dev/null \
            | sed 's/\.md$//'
    } | sort -u >"$expected_file"

    missing="$(comm -13 "$roster_file" "$expected_file" | tr '\n' ' ')"
    extra="$(comm -23 "$roster_file" "$expected_file" | tr '\n' ' ')"
    if [ -n "${missing// /}" ]; then
        fail "suites.txt: no row for discovered/command name(s): $missing"
    else
        pass "suites.txt: covers every discovered evals.json and every command"
    fi
    if [ -n "${extra// /}" ]; then
        fail "suites.txt: row(s) with no backing child or command: $extra"
    else
        pass "suites.txt: every row is backed by a real name"
    fi

    # every row's cases/commands paths resolve; status is one of three
    while read -r name cases cmds status; do
        case "$status" in
            run|nested)
                if [ -r "$PKG_ROOT/$cases" ]; then
                    pass "suites.txt/$name: cases file present ($cases)"
                else
                    fail "suites.txt/$name: cases file missing: $cases"
                fi
                ;;
            pending)
                if [ "$cases" = "-" ] && [ -r "$PKG_ROOT/commands/$name.md" ]; then
                    pass "suites.txt/$name: pending claimant — commands/$name.md, no cases yet"
                else
                    fail "suites.txt/$name: status=pending needs cases '-' and commands/$name.md"
                fi
                ;;
            *) fail "suites.txt/$name: unknown status '$status' (run|nested|pending)" ;;
        esac
        if [ "$cmds" != "-" ] && [ ! -d "$PKG_ROOT/$cmds" ]; then
            fail "suites.txt/$name: commands dir missing: $cmds"
        fi
    done < <(awk 'NF && $1 !~ /^#/ { print $1, $2, $3, $4 }' "$SUITES_FILE")
fi

# --- entry → cases file -----------------------------------------------------
# Derived from suites.txt (status=run) — one roster, so the 3/3 material bar
# below and `trigger-run.sh --all` always score exactly the same entries.
entries=()
while read -r name cases _cmds status; do
    [ "$status" = "run" ] || continue
    entries+=("$name:$cases")
done < <(awk 'NF && $1 !~ /^#/ { print $1, $2, $3, $4 }' "$SUITES_FILE" 2>/dev/null)
[ "${#entries[@]}" -gt 0 ] || fail "suites.txt: no status=run suites to score"

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

    # every positive names its argument literally — deixis is unresolvable here
    while IFS= read -r line; do
        id="${line%%$'\t'*}"
        prompt="${line#*$'\t'}"
        if literal_arg "$prompt"; then
            pass "$entry/$id: positive argument is literal"
        else
            fail "$entry/$id: positive prompt is deictic — no plans/ path, wp-NN id, or backticked name"
        fi
    done < <(jq -r '.evals[]? | select(.should_trigger == true)
                    | ((.id // "evals[?]") | tostring) + "\t" + (.prompt // "")' "$file")

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

# --- REPORT SURFACE PROVENANCE GATE -----------------------------------------
# A committed report is a measurement of a SURFACE, not of a commit. The runner
# stamps that surface as config_dir.content_hash. If the tree moved between the
# run and the commit — a transient uncommitted edit live during the run, a later
# description change — the numbers in the report describe a surface no commit
# reproduces, and every gain claimed from them is unfalsifiable.
#
# The rule, deliberately simple: reports in the NEWEST dated selection-* directory
# are the "after" record for their suite and MUST carry the hash the current tree
# emits. Older directories are historical and skipped OUT LOUD — a skip line per
# file, never silence.
#
# The current-tree hash is the one `trigger-run.sh --suite <n> --dry-run
# --with-siblings` prints: same suite roster, same sibling install, no model work,
# no cost. When the shared runner is absent trigger-run.sh degrades to a gap, so
# this gate degrades with it (a `gap:` line, no failure) rather than going red on
# a plumbing problem.
REPORTS_DIR="$HERE/reports"
if [ ! -d "$REPORTS_DIR" ]; then
    pass "provenance: no reports/ directory — nothing to gate"
else
    newest_dir="$(find -L "$REPORTS_DIR" -mindepth 1 -maxdepth 1 -type d -name 'selection-*' -printf '%f\n' 2>/dev/null | sort | tail -1)"
    if [ -z "$newest_dir" ]; then
        pass "provenance: no selection-* report directories — nothing to gate"
    else
        pass "provenance: newest report directory is $newest_dir"

        # every older directory is historical: said out loud, one line per file
        while IFS= read -r old_dir; do
            [ -n "$old_dir" ] || continue
            [ "$old_dir" = "$newest_dir" ] && continue
            for rf in "$REPORTS_DIR/$old_dir"/*.json; do
                [ -e "$rf" ] || continue
                printf 'skip stale: historical — %s/%s (superseded by %s)\n' \
                    "$old_dir" "$(basename "$rf")" "$newest_dir"
            done
        done < <(find -L "$REPORTS_DIR" -mindepth 1 -maxdepth 1 -type d -name 'selection-*' -printf '%f\n' 2>/dev/null | sort)

        # roster of scorable suite names — the only stems with a current-tree hash
        run_suites_file="$(mktemp)"
        awk 'NF && $1 !~ /^#/ && $4 == "run" { print $1 }' "$SUITES_FILE" 2>/dev/null | sort >"$run_suites_file"

        for rf in "$REPORTS_DIR/$newest_dir"/*.json; do
            [ -e "$rf" ] || continue
            stem="$(basename "$rf" .json)"
            if ! grep -qxF "$stem" "$run_suites_file"; then
                printf 'skip stale: not a roster suite — %s/%s has no current-tree hash to compare\n' \
                    "$newest_dir" "$stem"
                continue
            fi
            got="$(jq -r '.config_dir.content_hash // ""' "$rf")"
            want="$("$HERE/trigger-run.sh" --suite "$stem" --dry-run --with-siblings 2>/dev/null \
                    | grep -o 'sha256:[0-9a-f]\{64\}' | head -1)"
            if [ -z "$want" ]; then
                printf 'gap: no current-tree hash for suite %s (shared runner absent?) — %s/%s not gated\n' \
                    "$stem" "$newest_dir" "$stem"
                continue
            fi
            if [ -z "$got" ]; then
                fail "provenance/$newest_dir/$stem: report carries no config_dir.content_hash"
            elif [ "$got" = "$want" ]; then
                pass "provenance/$newest_dir/$stem: surface hash matches the current tree ($want)"
            else
                fail "provenance/$newest_dir/$stem: surface hash $got does not match the current tree $want — the report measures a surface no commit reproduces"
            fi
        done
        rm -f "$run_suites_file"
    fi
fi

printf '\n'
if [ "$fails" -eq 0 ]; then
    echo "PASS selection.test.sh — suites.txt matches the tree; ${#entries[@]}/${#entries[@]} entries meet the 3/3 bar: literal positives, installable owners"
    exit 0
fi
echo "FAIL selection.test.sh — $fails assertion(s) failed"
exit 1
