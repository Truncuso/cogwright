#!/usr/bin/env bash
# goalforge-names.test.sh — the child-name oracle (b4, ticket-79 option 1).
#
# Three parts, deliberately separated because only one of them can fail on an
# unmodified tree:
#
#   PART A  a mktemp stub skill tree — one dir that satisfies validate-skill.py
#           IN FULL (name == directory AND a description AND metadata.version,
#           all of which the validator requires) and two offenders (name !=
#           directory; no `name:` key at all). The conformant stub must rate 0
#           and BOTH offenders non-zero. This is the half that proves the
#           validator is actually discriminating rather than rubber-stamping.
#   PART B  the RATCHET: every shipped packages/goalforge/*/SKILL.md rates 0,
#           and `scripts/goalforge-generate.sh --check` exits 0.
#   PART C  every child eval suite discovered by ls -d */evals/run.sh runs and
#           exits 0 — so a renamed child whose sibling suite still pins the old
#           `name: goalforge-<child>` literal turns this test, and therefore
#           the WP's verification command, RED. The top-level harness's own
#           stage loop covers only six stages and would never notice.
#
# The validator is a HOST file (~/.claude/scripts/validate-skill.py). Its
# absence is a REQUIREMENT failure, not a skip: exit 2, the same posture the
# package takes for node/bun. A gate that silently skips is not a gate.
set -uo pipefail

PKG="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
REPO="$(cd "$PKG/../.." && pwd)"
VALIDATOR="${GOALFORGE_VALIDATE_SKILL:-$HOME/.claude/scripts/validate-skill.py}"
GENERATE="$REPO/scripts/goalforge-generate.sh"
PASS=0; FAIL=0
ok()  { echo "  PASS: $1"; PASS=$((PASS+1)); }
bad() { echo "  FAIL: $1"; FAIL=$((FAIL+1)); }

if ! command -v python3 >/dev/null 2>&1; then
    echo "  REQUIREMENT UNMET: python3 not on PATH" >&2
    exit 2
fi
if [ ! -f "$VALIDATOR" ]; then
    echo "  REQUIREMENT UNMET: validate-skill.py not found at $VALIDATOR" >&2
    echo "  (set GOALFORGE_VALIDATE_SKILL to point at it; this is a requirement, not a skip)" >&2
    exit 2
fi

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

rate() { python3 "$VALIDATOR" "$1" >/dev/null 2>&1; printf '%s' "$?"; }

# ── PART A: the stub tree — the half that can fail on an unmodified tree ──
echo "[ PART A: validator discriminates on a stub skill tree ]"

mk_stub() { # <dir-name> <frontmatter body>
    local dir="$WORK/stubs/$1"
    mkdir -p "$dir"
    { echo "---"; printf '%s\n' "$2"; echo "---"; echo ""; echo "Stub."; } > "$dir/SKILL.md"
    printf '%s' "$dir"
}

good="$(mk_stub conformant "$(printf 'name: conformant\ndescription: A stub that satisfies the validator in full.\nmetadata:\n  version: "1.0.0"')")"
wrong="$(mk_stub mismatched "$(printf 'name: something-else\ndescription: A stub whose name does not match its directory.\nmetadata:\n  version: "1.0.0"')")"
missing="$(mk_stub nameless "$(printf 'description: A stub with no name key at all.\nmetadata:\n  version: "1.0.0"')")"

[ "$(rate "$good")" = 0 ]    && ok "conformant stub rates 0" \
    || bad "conformant stub rated $(rate "$good") — the validator rejects a valid skill"
[ "$(rate "$wrong")" != 0 ]  && ok "name != directory rates non-zero" \
    || bad "name != directory rated 0 — the validator is not checking the rule"
[ "$(rate "$missing")" != 0 ] && ok "missing name: key rates non-zero" \
    || bad "missing name: key rated 0 — the validator is not checking the rule"

echo ""

# ── PART B: the ratchet over the shipped tree ────────────────────────────
echo "[ PART B: shipped children + drift gate ]"

for d in "$PKG"/*/; do
    [ -f "$d/SKILL.md" ] || continue
    base="$(basename "$d")"
    if [ "$(rate "${d%/}")" = 0 ]; then
        ok "$base/SKILL.md validates (name == directory)"
    else
        bad "$base/SKILL.md fails validate-skill.py: $(python3 "$VALIDATOR" "${d%/}" 2>&1 | head -n 3)"
    fi
done
if [ "$(rate "$PKG")" = 0 ]; then
    ok "front-door SKILL.md validates"
else
    bad "front-door SKILL.md fails: $(python3 "$VALIDATOR" "$PKG" 2>&1 | head -n 3)"
fi

# T6: the plugin regenerates clean, so the commit needs no skill-validation
# escape hatch. Read-only — this test never regenerates anything itself.
if [ -x "$GENERATE" ] || [ -f "$GENERATE" ]; then
    if bash "$GENERATE" --check >"$WORK/drift.out" 2>&1; then
        ok "scripts/goalforge-generate.sh --check exits 0 (no plugin drift)"
    else
        bad "plugin drift: $(head -n 5 "$WORK/drift.out")"
    fi
else
    bad "scripts/goalforge-generate.sh not found at $GENERATE"
fi

# The git skip seam is gone: the skill-validation escape hatch the earlier WPs
# set on every commit is referenced nowhere in the package. Rung-1 standing
# evidence for the outcome clause "the git skip seam is no longer needed" —
# cheap, and it cannot pass vacuously while the string is there. The literal is
# assembled at runtime so this file is not itself the match it looks for.
SEAM="GIT_HOOK_SKIP""_SKILL"
if grep -rq "$SEAM" "$PKG" 2>/dev/null; then
    bad "the commit skip seam is still referenced in the package: $(grep -rl "$SEAM" "$PKG" | head -n 3)"
else
    ok "no commit skip seam left in the package (validation runs unskipped)"
fi

echo ""

# ── PART C: every discovered child eval suite ───────────────────────────
echo "[ PART C: child eval suites (discovered) ]"

found=0
for suite in "$PKG"/*/evals/run.sh; do
    [ -f "$suite" ] || continue
    found=$((found + 1))
    label="${suite#"$PKG"/}"
    if bash "$suite" >"$WORK/suite.out" 2>&1; then
        ok "$label exits 0"
    else
        bad "$label failed:"
        sed 's/^/        /' "$WORK/suite.out" | tail -n 20
    fi
done
[ "$found" -gt 0 ] && ok "discovered $found child eval suite(s)" \
    || bad "discovered NO child eval suites — the glob is broken, PART C is vacuous"

echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
