#!/usr/bin/env bash
# goalforge-archive.sh — deterministic core of the sdd-archive skill. Archives ONE
# completed feature to its terminal `archived` status and moves it to
# _archived/. Fail-closed: refuses unless status: completed. Does NOT commit and
# does NOT run ensure-committed — the CALLER commits, then verifies cleanliness
# (so git records the frontmatter edit + folder rename in one commit).
#
# Usage:  goalforge-archive.sh <feature> [--supersedes <old>] [--strict-refs] [--plans-root <root>]
#         goalforge-archive.sh <feature> --relocate [--strict-refs] [--plans-root <root>]
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
# Gate ordering invariant: every gate that can REFUSE (status precondition,
# destination collision, reference-gate) runs BEFORE the first frontmatter
# write, and the validator gate rolls the frontmatter edits back on failure —
# a refusal at any exit code leaves the tree byte-identical to the
# pre-invocation state. (Strand bug 2026-07-16: --strict-refs refusal after
# the status stamp left wayfind `archived` at the active root; recovery
# needed --relocate.)
#
# The sdd-archive SKILL is the human front door (refusal templates, supersede
# explanation, reporting); it delegates these mechanical steps here so a script
# (batch / loop) can drive them deterministically. Skill parity: schema.md.

set -uo pipefail

SD="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VALIDATE="${GOALFORGE_VALIDATE:-$SD/goalforge-validate.sh}"

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
[[ -z "$FEATURE" ]] && { echo "sdd-archive: usage: goalforge-archive.sh <feature> [--supersedes <old>] [--plans-root <root>]" >&2; exit 2; }

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

# ── Step 1b: destination-collision pre-check (before any write — gate ordering
# invariant: an exit-4 halt after the status stamp would strand the feature).
precheck_dest() {  # $1 = slug
    if [[ -e "$ROOT/_archived/$1" ]]; then
        echo "sdd-archive HALT — destination already exists: $ROOT/_archived/$1 (no overwrite)" >&2
        return 4
    fi
}
precheck_dest "$FEATURE" || exit 4
if [[ -n "$OLD" ]]; then precheck_dest "$OLD" || exit 4; fi

# ── Step 2: reference-gate (warn; REFUSE under --strict-refs) ─────────────────
# Runs BEFORE any frontmatter write (gate ordering invariant above). Finds
# references that point INTO the feature dir from OUTSIDE it — those use the
# active `<slug>/` path and DANGLE after the move (they would need
# `_archived/<slug>/`). Relationship wikilinks `[[<slug>]]` are graph edges
# (the validator resolves archived targets) and are NOT flagged — only PATH
# refs (`<slug>/`) are.
#
# Hits are classified HARD vs PROSE:
#   HARD  — machine-followed locators that break: frontmatter pointer fields
#           (locator:, promoted_to:, source:, path:, Resume:) and markdown
#           link targets `](...<slug>/...)`. These gate under --strict-refs.
#   PROSE — a plain textual mention of the path (discussion, changelog line,
#           dir-name coincidence). Informational only; never refuses.
# (Wayfind 2026-07-16: the unclassified gate flagged prose mentions and the
# unrelated `wayfind/` ticket-subdir concept alongside the two real locators.)
DOCS="$(dirname "$ROOT")/docs"
ref_gate() {  # $1 = slug
    local slug="$1" hits hard prose
    local -a search=("$ROOT")
    [[ -d "$DOCS" ]] && search+=("$DOCS")
    hits=$(grep -rInF --exclude-dir=_archived --exclude-dir=.git "$slug/" "${search[@]}" 2>/dev/null \
           | grep -vF "$ROOT/$slug/" | grep -vF "/_archived/" || true)
    [[ -z "$hits" ]] && return 0
    # HARD: content (after file:line:) is a frontmatter pointer field naming
    # the slug-path, or a markdown link whose TARGET contains the slug-path.
    hard=$(echo "$hits" | grep -E ":[0-9]+:[[:space:]]*-?[[:space:]]*(locator|promoted_to|source|path|resume|Resume):.*${slug}/|\]\([^)]*${slug}/" || true)
    prose=$(echo "$hits" | grep -vxF "$hard" || true)
    if [[ -n "$prose" ]]; then
        echo "sdd-archive ref-gate INFO: prose mentions of '$slug/' (not gating):" >&2
        echo "$prose" | sed 's/^/  /' >&2
    fi
    [[ -z "$hard" ]] && return 0
    echo "sdd-archive REFERENCE-GATE: inbound HARD path refs to '$slug/' (will dangle after move to _archived/):" >&2
    echo "$hard" | sed 's/^/  /' >&2
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

# ── Step 3: frontmatter edits, backed up for rollback (BEFORE the move, so git
# sees edit+rename together). Relocate mode skips this entirely — the feature
# is already status: archived.
BAK=""
rollback() {  # restore pre-edit frontmatter on a post-edit refusal
    [[ -z "$BAK" ]] && return 0
    cp -p "$BAK/feat.orig" "$FEAT_OV"
    [[ -n "$OLD" && -f "$BAK/old.orig" ]] && cp -p "$BAK/old.orig" "$ROOT/$OLD/overview.md"
    rm -rf "$BAK"
    BAK=""
}
if [[ $RELOCATE -eq 0 ]]; then
    BAK="$(mktemp -d)"
    cp -p "$FEAT_OV" "$BAK/feat.orig"
    [[ -n "$OLD" ]] && cp -p "$ROOT/$OLD/overview.md" "$BAK/old.orig"
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
# A validator FAILURE rolls the frontmatter edits back (gate ordering invariant).
validate_feature() {  # $1 = slug
    if ! "$VALIDATE" --feature "$1" --strict "$ROOT" >/dev/null 2>&1; then
        echo "sdd-archive: validator FAILED for $1 — run: goalforge-validate.sh --feature $1 --strict --show $ROOT" >&2
        echo "sdd-archive: frontmatter edits rolled back — feature left at its pre-invocation status." >&2
        return 5
    fi
}
validate_feature "$FEATURE" || { rollback; exit 5; }
if [[ -n "$OLD" ]]; then validate_feature "$OLD" || { rollback; exit 5; }; fi
[[ -n "$BAK" ]] && { rm -rf "$BAK"; BAK=""; }

# ── Step 5: physical move (AFTER edit+validate, so git records edit+rename together)
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
