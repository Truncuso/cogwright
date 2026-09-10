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
