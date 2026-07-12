#!/usr/bin/env bash
# sdd-archive.sh — deterministic core of the sdd-archive skill. Archives ONE
# completed feature to its terminal `archived` status and moves it to
# _archived/. Fail-closed: refuses unless status: completed. Does NOT commit and
# does NOT run ensure-committed — the CALLER commits, then verifies cleanliness
# (so git records the frontmatter edit + folder rename in one commit).
#
# Usage:  sdd-archive.sh <feature> [--supersedes <old>] [--strict-refs] [--plans-root <root>]
#         sdd-archive.sh <feature> --relocate [--strict-refs] [--plans-root <root>]
#
# Modes:
#   (default)   completed → archived : flips status + moves to _archived/.
#   --relocate  reconcile a STRANDED archived feature — one already at
#               status: archived but still physically at the active root (status
#               set out-of-band, never moved). Move-only; no frontmatter edit.
#               Requires status: archived (the inverse of the default gate).
#
# Exit:  0 archived/relocated ok | 2 usage | 3 refused (wrong status / missing target)
#        4 destination collision | 5 validator failed | 6 reference-gate (--strict-refs)
#
# The sdd-archive SKILL is the human front door (refusal templates, supersede
# explanation, reporting); it delegates these mechanical steps here so a script
# (batch / loop) can drive them deterministically. Skill parity: schema.md.

set -uo pipefail

SD="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VALIDATE="$SD/sdd-validate.sh"

FEATURE=""
OLD=""
ROOT=""
RELOCATE=0
STRICT_REFS=0
while [[ $# -gt 0 ]]; do
    case "$1" in
        --supersedes)  OLD="$2"; shift 2 ;;
        --relocate)    RELOCATE=1; shift ;;
        --strict-refs) STRICT_REFS=1; shift ;;
        --plans-root)  ROOT="$2"; shift 2 ;;
        -*)            echo "sdd-archive: unknown flag: $1" >&2; exit 2 ;;
        *)             FEATURE="$1"; shift ;;
    esac
done
[[ -z "$FEATURE" ]] && { echo "sdd-archive: usage: sdd-archive.sh <feature> [--supersedes <old>] [--plans-root <root>]" >&2; exit 2; }

# Resolve plans root: --plans-root → SDD_PLANS_DIR → git-root/plans → CWD/plans → ~/.claude/plans
if [[ -z "$ROOT" ]]; then
    if [[ -n "${SDD_PLANS_DIR:-}" ]]; then ROOT="$SDD_PLANS_DIR"
    else
        GR=$(git rev-parse --show-toplevel 2>/dev/null) || true
        if [[ -n "${GR:-}" && -d "$GR/plans" ]]; then ROOT="$GR/plans"
        elif [[ -d "$(pwd)/plans" ]]; then ROOT="$(pwd)/plans"
        else ROOT="$HOME/.claude/plans"; fi
    fi
fi
ROOT="$(cd "$ROOT" && pwd)"

FEAT_DIR="$ROOT/$FEATURE"
FEAT_OV="$FEAT_DIR/overview.md"

read_status() {  # $1 = overview.md path
    python3 - "$1" <<'PY' 2>/dev/null || true
import sys, yaml
t = open(sys.argv[1], encoding='utf-8').read().split('\n')
try:
    end = next(i for i in range(1, len(t)) if t[i].strip() == '---')
except StopIteration:
    sys.exit(0)
fm = yaml.safe_load('\n'.join(t[1:end])) or {}
print(fm.get('status', ''))
PY
}

# ── Step 1: fail-closed precondition (mode-dependent) ────────────────────────
[[ -f "$FEAT_OV" ]] || { echo "sdd-archive REFUSED — feature not found: $FEAT_OV" >&2; exit 3; }
ST="$(read_status "$FEAT_OV")"
if [[ $RELOCATE -eq 1 ]]; then
    # Relocate mode: gate is the inverse — the feature must ALREADY be archived
    # (stranded at the active root). --supersedes is meaningless here.
    [[ -n "$OLD" ]] && { echo "sdd-archive: --supersedes is not valid with --relocate" >&2; exit 2; }
    if [[ "$ST" != "archived" ]]; then
        { echo "sdd-archive --relocate REFUSED — not a stranded archived feature:"
          echo "  Feature: $FEATURE"
          echo "  status: ${ST:-<none>}   (required: archived — use plain sdd-archive for a completed feature)"; } >&2
        exit 3
    fi
elif [[ "$ST" != "completed" ]]; then
    { echo "sdd-archive REFUSED — precondition not satisfied:"
      echo "  Feature: $FEATURE"
      echo "  status: ${ST:-<none>}   (required: completed)"; } >&2
    exit 3
fi
if [[ -n "$OLD" ]]; then
    [[ -f "$ROOT/$OLD/overview.md" ]] || { echo "sdd-archive REFUSED — supersedes target not found: $ROOT/$OLD/overview.md" >&2; exit 3; }
fi

# ── Frontmatter editor (targeted, minimal-diff) ──────────────────────────────
edit_fm() {  # $1=file  $2=edge(''|supersedes|superseded_by)  $3=edge-target
    python3 - "$1" "$2" "$3" <<'PY'
import sys, re, datetime
f, edge, target = sys.argv[1], sys.argv[2], sys.argv[3]
today = datetime.date.today().isoformat()
text = open(f, encoding='utf-8').read()
lines = text.split('\n')
end = next(i for i in range(1, len(lines)) if lines[i].strip() == '---')
fm = lines[1:end]
rest = lines[end:]                      # includes the closing ---

def set_field(key, val):
    for i, l in enumerate(fm):
        if re.match(rf'^{re.escape(key)}:(\s|$)', l):
            fm[i] = f'{key}: {val}'
            return True
    return False

set_field('status', 'archived')
if not set_field('updated', today):
    for i, l in enumerate(fm):
        if l.startswith('status:'):
            fm.insert(i + 1, f'updated: {today}')
            break

if edge and target:
    item = f'  - {edge}: [[{target}]]'
    ri = next((i for i, l in enumerate(fm) if re.match(r'^relationships:', l)), None)
    if ri is None:
        fm.append('relationships:')
        fm.append(item)
    elif re.match(r'^relationships:\s*\[\s*\]\s*$', fm[ri]):
        fm[ri] = 'relationships:'
        fm.insert(ri + 1, item)
    else:
        fm.insert(ri + 1, item)

open(f, 'w', encoding='utf-8').write('\n'.join(['---'] + fm + rest))
PY
}

# ── Step 2/3: frontmatter edits (BEFORE the move, so git sees edit+rename together)
# Relocate mode skips this entirely — the feature is already status: archived.
if [[ $RELOCATE -eq 0 ]]; then
    if [[ -n "$OLD" ]]; then
        edit_fm "$FEAT_OV" supersedes "$OLD"
        edit_fm "$ROOT/$OLD/overview.md" superseded_by "$FEATURE"
    else
        edit_fm "$FEAT_OV" "" ""
    fi
fi

# ── Step 4: validate the edited feature(s) IN PLACE, scoped (before the move) ─
# --feature scopes the gate to the archived feature(s): the validator still
# WALKS the whole tree (so cross-feature supersede/depends_on edges resolve), but
# only THIS feature's errors gate. Pre-existing drift in unrelated, out-of-scope
# features therefore never blocks the archive (the tree legitimately carries
# deferred drift). Each per-feature commit is independently re-validated by the
# pre-commit hook, which is likewise per-feature scoped.
validate_feature() {  # $1 = slug
    if ! "$VALIDATE" --feature "$1" --strict "$ROOT" >/dev/null 2>&1; then
        echo "sdd-archive: validator FAILED for $1 — run: sdd-validate.sh --feature $1 --strict --show $ROOT" >&2
        return 5
    fi
}
validate_feature "$FEATURE" || exit 5
if [[ -n "$OLD" ]]; then validate_feature "$OLD" || exit 5; fi

# ── Step 4b: reference-gate (warn; REFUSE under --strict-refs) ────────────────
# Before moving <slug>/ into _archived/, find references that point INTO the
# feature dir from OUTSIDE it -- a cross-cited findings.md/playbook, or a
# frontmatter `locator:`. Those use the active `<slug>/` path and DANGLE after
# the move (they would need `_archived/<slug>/`). Relationship wikilinks
# `[[<slug>]]` are graph edges (the validator resolves archived targets) and are
# NOT flagged -- only PATH refs (`<slug>/`) are. Lesson: a blind archive of a
# cross-cited wp findings.md broke ~12 links and was reverted.
DOCS="$(dirname "$ROOT")/docs"
ref_gate() {  # $1 = slug
    local slug="$1" hits
    local -a search=("$ROOT")
    [[ -d "$DOCS" ]] && search+=("$DOCS")
    hits=$(grep -rInF --exclude-dir=_archived --exclude-dir=.git "$slug/" "${search[@]}" 2>/dev/null \
           | grep -vF "$ROOT/$slug/" | grep -vF "/_archived/" || true)
    [[ -z "$hits" ]] && return 0
    echo "sdd-archive REFERENCE-GATE: inbound path refs to '$slug/' (will dangle after move to _archived/):" >&2
    echo "$hits" | sed 's/^/  /' >&2
    echo "  -> relocate the cross-cited artifact + repoint these refs BEFORE archiving, or re-point them" >&2
    echo "     to _archived/$slug/. (A blind archive of a cross-cited findings.md broke ~12 links once.)" >&2
    if [[ "$STRICT_REFS" == "1" ]]; then
        echo "sdd-archive: --strict-refs set -> REFUSING (exit 6). Resolve the refs above, or drop --strict-refs." >&2
        return 6
    fi
    echo "  (warning only; pass --strict-refs to make this a hard gate)" >&2
    return 0
}
ref_gate "$FEATURE" || exit 6
if [[ -n "$OLD" ]]; then ref_gate "$OLD" || exit 6; fi

# ── Step 2b: physical move (AFTER edit+validate, so git records edit+rename together)
mkdir -p "$ROOT/_archived"
move_one() {  # $1 = slug
    local dest="$ROOT/_archived/$1"
    if [[ -e "$dest" ]]; then
        echo "sdd-archive HALT — destination already exists: $dest (no overwrite)" >&2
        return 4
    fi
    mv "$ROOT/$1" "$dest"
}
move_one "$FEATURE" || exit 4
if [[ -n "$OLD" ]]; then move_one "$OLD" || exit 4; fi

if [[ $RELOCATE -eq 1 ]]; then
    echo "sdd-archive: relocated stranded archived $FEATURE -> _archived/$FEATURE"
else
    echo "sdd-archive: archived $FEATURE -> _archived/$FEATURE${OLD:+ (supersedes $OLD, also archived)}"
fi
exit 0
