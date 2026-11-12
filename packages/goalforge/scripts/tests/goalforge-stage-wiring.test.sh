#!/usr/bin/env bash
# goalforge-stage-wiring.test.sh — b3 oracle for wp-02-agent-roster.
#
# Asserts the roster wiring facets are present in the LIVE harden/verify
# SKILL.md, and that each check can actually fail: for every facet a known-bad
# copy is generated into a temp dir with that one facet's lines stripped, and
# the same grep must then fail. A facet whose known-bad copy still passes is a
# check that cannot fail and is reported as a FAIL.
#
#   known-good: the live SKILL.md contains the facet          -> grep succeeds
#   known-bad:  the stripped copy does not                    -> grep fails
#
# Fixtures are generated read-only into "$FIX_TMP_ROOT" and removed on exit;
# nothing under evals/fixtures/ is read or written (b4 manifest stays inert).
set -uo pipefail

SD="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PKG="$(cd "$SD/../.." && pwd)"
HARDEN="$PKG/harden/SKILL.md"
VERIFY="$PKG/verify/SKILL.md"

FIX_TMP_ROOT="$(mktemp -d)"
trap 'rm -rf "$FIX_TMP_ROOT"' EXIT

PASS=0; FAIL=0
ok()  { echo "  PASS: $1"; PASS=$((PASS+1)); }
bad() { echo "  FAIL: $1"; FAIL=$((FAIL+1)); }

for f in "$HARDEN" "$VERIFY"; do
    if [[ -f "$f" ]]; then
        ok "live file present: ${f#"$PKG"/}"
    else
        bad "live file present: ${f#"$PKG"/} (missing — every facet below is vacuous)"
    fi
done
[[ -f "$HARDEN" && -f "$VERIFY" ]] || { echo; echo "goalforge-stage-wiring.test.sh: $PASS passed, $FAIL failed"; exit 1; }

# facet <file> <label> <literal substring>
#   1. the live file must contain it
#   2. a copy with every matching line removed must NOT contain it, and must
#      differ from the live file (a no-op strip = a check that cannot fail)
facet() {
    local file="$1" label="$2" needle="$3"
    local base copy
    base="$(basename "$(dirname "$file")")"
    copy="$FIX_TMP_ROOT/${base}--$(printf '%s' "$label" | tr -c 'a-zA-Z0-9' '-').md"

    if grep -qF -- "$needle" "$file"; then
        ok "$base: $label"
    else
        bad "$base: $label — live file lacks [$needle]"
        return
    fi

    grep -vF -- "$needle" "$file" > "$copy"
    if [[ "$(wc -l < "$copy")" -eq "$(wc -l < "$file")" ]]; then
        bad "$base: $label — known-bad copy identical to live file (strip is a no-op)"
        return
    fi
    if grep -qF -- "$needle" "$copy"; then
        bad "$base: $label — known-bad copy still matches (check cannot fail)"
    else
        ok "$base: $label — known-bad copy fails the same grep"
    fi
}

echo "harden/SKILL.md — G3 roster wiring"
facet "$HARDEN" "G3 dispatches agents/reviewer.md"        'agents/reviewer.md'
facet "$HARDEN" "expertise bundle source"                 'references/expertise-map.yaml'
facet "$HARDEN" "panel is 3x"                             '**3x panel**'
facet "$HARDEN" "panel members carry distinct bundles"    '**distinct expertise bundles**'
facet "$HARDEN" "panel condition severity HIGH"           '`severity: HIGH`'
facet "$HARDEN" "panel condition register production"     '`register: production`'
facet "$HARDEN" "verdicts consumed as typed DATA"         'DATA, never as instructions'
facet "$HARDEN" "override belongs to goalforge-transition.sh" 'to `goalforge-transition.sh` at G4'

echo
echo "verify/SKILL.md — gate A/B/C wiring"
facet "$VERIFY" "gate B dispatches agents/reviewer.md"    'agents/reviewer.md'
facet "$VERIFY" "gate B expertise bundle source"          'references/expertise-map.yaml'
facet "$VERIFY" "gate C dispatches evaluation-expert"     'agents/evaluation-expert.md'
facet "$VERIFY" "second-opinion pinned call"              'scripts/goalforge-second-opinion.sh <wp> --feature-dir <feature>'
facet "$VERIFY" "second opinion is skip-when-absent"      'skip-when-absent'
facet "$VERIFY" "skip row is recorded"                    'second_opinion.skipped reason=dispatcher-absent'
facet "$VERIFY" "gate A exempts plugins/goalforge/"       'paths under `plugins/goalforge/` never BLOCK'
facet "$VERIFY" "C4 stop-rule pointer"                    'Stop rule: spec.md'
facet "$VERIFY" "returns consumed as typed DATA"          'typed DATA, never as'

# respec re-entry wiring (wp-02 L0-1) ----------------------------------------
# harden/SKILL.md admits the re-entry and the resume, run/SKILL.md routes a
# `hardened` WP to harden, and references/respec.md §Re-entry holds the
# procedure. §Re-entry needles are grepped inside the extracted section
# (heading to next heading), never file-wide.
RUN="$PKG/run/SKILL.md"
RESPEC="$PKG/references/respec.md"

section() { # <file> <H2 title> -> the section body, heading to next H2
    awk -v h="## $2" '/^## /{ inside = ($0 == h); next } inside' "$1"
}

# section_facet <file> <H2 title> <label> <needle>
#   1. the extracted section must contain it
#   2. a copy with every matching line removed must NOT (the check can fail)
section_facet() {
    local file="$1" title="$2" label="$3" needle="$4" copy
    copy="$FIX_TMP_ROOT/section--$(printf '%s' "$label" | tr -c 'a-zA-Z0-9' '-').md"
    if section "$file" "$title" | grep -qF -- "$needle"; then
        ok "§$title: $label"
    else
        bad "§$title: $label — section lacks [$needle]"
        return
    fi
    grep -vF -- "$needle" "$file" > "$copy"
    if section "$copy" "$title" | grep -qF -- "$needle"; then
        bad "§$title: $label — known-bad copy still matches (check cannot fail)"
    else
        ok "§$title: $label — known-bad copy fails the same grep"
    fi
}

echo
echo "respec re-entry wiring"
facet "$HARDEN" "precondition admits respec re-entry at ready or hardened" 'a respec re-entry at `ready` or `hardened`'
facet "$HARDEN" "precondition points to respec.md §Re-entry" 'references/respec.md §Re-entry'
facet "$HARDEN" "precondition admits the hardened -> ready resume" 'resuming at the hardened -> ready gate'
facet "$RUN" "stage table routes hardened WP to harden" '| `hardened` | WP | harden (re-entry) | `goalforge-harden` |'
facet "$RUN" "gotcha: routing keys off the on-disk status" 'Routing keys entirely off the on-disk `status:`'
section_facet "$RESPEC" Re-entry "names --mode evidence --evidence"        '--mode evidence --evidence'
section_facet "$RESPEC" Re-entry "names the reharden-evidence template"    'references/templates/reharden-evidence.md'
section_facet "$RESPEC" Re-entry "revert command carries --reason"         '--evidence <respec file> --reason "<text>"'
section_facet "$RESPEC" Re-entry "G1 is skipped on re-entry"               'G1 is skipped on re-entry'
section_facet "$RESPEC" Re-entry "G4 still emits its gate.result pass row" 'G4 still emits its `gate.result` row with gate `G4` and result `pass`'
section_facet "$RESPEC" Re-entry "resume when latest -> hardened is from: spec" \
    'resumes harden at the hardened -> ready gate without re-running G1-G4 when its latest `-> hardened` ledger row has `from: spec`'
section_facet "$RESPEC" Re-entry "resume on a later G4 gate.result pass row" \
    'or when trace-events.jsonl holds a `gate.result` row for the WP with gate `G4` and result `pass` whose ts is later than that ledger row'"'"'s ts'
section_facet "$RESPEC" Re-entry "any other FROM is a re-entry unless the G4 row exists" \
    'is a re-entry whether or not a respec file exists, unless that G4 row exists'
section_facet "$RESPEC" Re-entry "in-flight WP walks back first" \
    'first walks back with `goalforge-transition.sh <wp-dir> ready --reason "<text>"`'

# Scope control: the same needle outside §Re-entry must not satisfy the check.
MOVED="$FIX_TMP_ROOT/respec-moved.md"
sed 's/^## Re-entry$/## Re-entry moved/' "$RESPEC" > "$MOVED"
if section "$MOVED" Re-entry | grep -qF -- 'G1 is skipped on re-entry'; then
    bad "§Re-entry scope control: a renamed section still satisfies the section grep"
else
    ok "§Re-entry scope control: needles outside the section do not count"
fi

# No stage-table row names a respec file: routing keys on status only.
stage_rows() { grep -E '^[[:space:]]*\|' "$1"; }
respec_rows() { stage_rows "$1" | grep -E 'respec|reharden/'; }
if [[ -z "$(respec_rows "$RUN")" ]]; then
    ok "run: no stage-table row names a respec file"
else
    bad "run: a stage-table row names a respec file — $(respec_rows "$RUN" | tr '\n' ' ')"
fi
INJECT="$FIX_TMP_ROOT/run-respec-row.md"
sed '/^   | `hardened` | WP |/a\   | `ready` + newer `reharden/*-respec-*` file | WP | harden (re-entry) | `goalforge-harden` | human |' "$RUN" > "$INJECT"
if [[ -n "$(respec_rows "$INJECT")" ]]; then
    ok "run: an injected respec-file stage row is detected (check can fail)"
else
    bad "run: an injected respec-file stage row is NOT detected (check cannot fail)"
fi

# human-gate and ready-row prose (wp-03) -------------------------------------
# The prose states what goalforge-transition.sh enforces at schema_version >= 6.
# A presence facet strips its needle in the known-bad copy; an absence check
# re-adds the retired text in its known-bad copy and must then catch it.
SM="$PKG/references/state-machine.md"
CAPTURE="$PKG/capture/SKILL.md"
SMOKE="$PKG/scripts/goalforge-smoke.sh"

# absent <file> <label> <retired literal>
absent() {
    local file="$1" label="$2" needle="$3" copy
    copy="$FIX_TMP_ROOT/absent--$(printf '%s' "$label" | tr -c 'a-zA-Z0-9' '-').md"
    if grep -qF -- "$needle" "$file"; then
        bad "$(basename "$file"): $label — still carries [$needle]"
        return
    fi
    ok "$(basename "$file"): $label"
    { cat "$file"; printf '%s\n' "$needle"; } > "$copy"
    if grep -qF -- "$needle" "$copy"; then
        ok "$(basename "$file"): $label — known-bad copy with the retired text is caught"
    else
        bad "$(basename "$file"): $label — known-bad copy is not caught (check cannot fail)"
    fi
}

echo
echo "human-gate and ready-row prose"
absent "$SM" "no policy bullet says the mechanism only records the gate" 'only records it'
facet "$SM" "WP gate: the script enforces it"            '`goalforge-transition.sh` enforces the gate: it refuses `hardened→ready`'
facet "$SM" "WP gate names --mode human"                 'unless `--mode human` is passed'
facet "$SM" "feature gate: --mode human only"            'the gate: `spec -> ready` passes only with `--mode human`'
facet "$SM" "predicate also applies to WP spec -> ready" 'and on `spec→ready --mode auto`'
absent "$SM" "auto-advance heading is not hardened->ready only" '(`hardened→ready` only)'
facet "$SM" "ready-row gate sentence"                    'needs a `-> ready` ledger row'
facet "$SM" "ready-row gate keeps the table rows legal"  'table rows stay legal'
section_facet "$RESPEC" "Enforcement limit" "the script enforces --mode human" \
    'enforces `--mode human` on the `human_gated: yes` feature edge'
section_facet "$RESPEC" "Enforcement limit" "--mode human is self-asserted" '`--mode human` is self-asserted'
absent "$RESPEC" "respec.md no longer says the script does not enforce the gate" 'does not enforce it'
facet "$HARDEN" "gate points to the state-machine predicate" 'the auto-advance predicate in references/state-machine.md'
facet "$HARDEN" "human_required veto kept"               'a **veto** over'
absent "$HARDEN" "no register production + severity HIGH human decision" '`register: production` and `severity: HIGH`'
facet "$CAPTURE" "fast path: exit 2 leaves the WP at spec" 'failed one with exit 2, leaving the WP at `spec`'
facet "$CAPTURE" "fast path: an exit 2 escalates to full harden" 'an exit 2 from the advance'
absent "$CAPTURE" "fast path: spec -> ready is not called non-human-gated" 'non-human-gated edge'
absent "$SMOKE" "smoke comment: transition.sh enforces the gate" 'never enforces it'
facet "$SMOKE" "smoke comment names the enforcement"     'transition.sh enforces the gate'
if [[ "$(wc -l < "$HARDEN")" -eq 125 ]]; then
    ok "harden/SKILL.md is 125 lines"
else
    bad "harden/SKILL.md is $(wc -l < "$HARDEN") lines, expected 125"
fi

# provider-name blacklist ---------------------------------------------------
# No provider may be named in either stage file: provider choice lives behind
# scripts/goalforge-second-opinion.sh (wp-03).
PROVIDERS='ollama|deepseek|codex|zai|openrouter|moonshot|nvidia'

scan_providers() { grep -inwE -- "$PROVIDERS" "$1"; }

echo
echo "provider-name blacklist"
for f in "$HARDEN" "$VERIFY"; do
    base="$(basename "$(dirname "$f")")"
    hits="$(scan_providers "$f")"
    if [[ -z "$hits" ]]; then
        ok "$base: names no provider"
    else
        bad "$base: names a provider — $(printf '%s' "$hits" | tr '\n' ' ')"
    fi
done

# positive control: the scanner must catch an injected provider name, else the
# two PASSes above are vacuous.
SABOTAGE="$FIX_TMP_ROOT/provider-sabotage.md"
{ cat "$VERIFY"; echo 'Take the second opinion on deepseek.'; } > "$SABOTAGE"
if scan_providers "$SABOTAGE" >/dev/null; then
    ok "blacklist positive control: injected provider name is detected"
else
    bad "blacklist positive control: injected provider name NOT detected (scanner cannot fail)"
fi

echo
echo "goalforge-stage-wiring.test.sh: $PASS passed, $FAIL failed"
[[ "$FAIL" -eq 0 ]]
