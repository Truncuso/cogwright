#!/usr/bin/env bash
# goalforge-prototype-retain.sh — manage a prototype's retention folder + gitignore.
#
# The retention substrate for goalforge's prototype layer. Given a feature slug,
# a prototype slug, and a retention tier, it idempotently ensures the folder
# `prototype/<feature>/<slug>/` exists and that `prototype/.gitignore` carries
# the correct ignore/un-ignore lines for the tier, then emits the contracted
# JSON so a caller can record `prototype_path` + `retention` in a findings doc.
#
# Usage:
#   goalforge-prototype-retain.sh <feature-slug> <prototype-slug> <discard|keep|share>
#
# Tiers (git semantics):
#   discard  folder stays ignored (default `*`); scratch, never committed.
#   keep     identical git treatment to discard — ignored in place; the tier
#            string is the only difference (a caller-facing retain intent).
#   share    folder is un-ignored so it can be committed: appends
#            `!<feature>/`, `!<feature>/<slug>/`, `!<feature>/<slug>/**`.
#            (A child cannot be re-included until its parent dir is, hence the
#            three lines in parent-first order; `*` has no slash so it matches
#            at every depth — all three are required.)
#
# Output (stdout, single line):
#   {"path":"prototype/<feature>/<slug>/","tier":"<tier>","gitignore_updated":true|false}
#
# Root resolution: the enclosing git worktree (`git rev-parse --show-toplevel`),
#   falling back to the current directory when not in a repo.
#
# Zero-breakage: a missing/invalid argument writes a note to stderr and exits 0;
#   the script only ever creates the folder and *appends* absent gitignore lines,
#   so it never rewrites or corrupts an existing `prototype/` tree. Idempotent:
#   a re-run appends nothing and reports `gitignore_updated:false`.
set -uo pipefail

note() { printf 'goalforge-prototype-retain: %s\n' "$1" >&2; }

# ── Args (zero-breakage: tolerable errors note + exit 0) ─────────────────────
if [[ $# -lt 3 ]]; then
    note "usage: $(basename "$0") <feature-slug> <prototype-slug> <discard|keep|share>"
    exit 0
fi
FEATURE="$1"; SLUG="$2"; TIER="$3"

if [[ -z "$FEATURE" || -z "$SLUG" ]]; then
    note "feature-slug and prototype-slug must be non-empty"
    exit 0
fi

# Reject path-traversal / unexpected characters in either slug before they reach
# mkdir, the un-ignore lines, or the JSON path. Must match ^[a-z0-9][a-z0-9._-]*$
# and contain no '/' or '..' (belt-and-suspenders against traversal).
valid_slug() { # $1=value
    local v="$1"
    [[ "$v" == *"/"* || "$v" == *".."* ]] && return 1
    [[ "$v" =~ ^[a-z0-9][a-z0-9._-]*$ ]]
}
if ! valid_slug "$FEATURE"; then
    note "invalid feature-slug '$FEATURE' (must match ^[a-z0-9][a-z0-9._-]*\$, no '/' or '..')"
    exit 0
fi
if ! valid_slug "$SLUG"; then
    note "invalid prototype-slug '$SLUG' (must match ^[a-z0-9][a-z0-9._-]*\$, no '/' or '..')"
    exit 0
fi
case "$TIER" in
    discard|keep|share) ;;
    *) note "invalid tier '$TIER' (expected discard|keep|share)"; exit 0 ;;
esac

# ── Root resolution: enclosing worktree, else cwd ────────────────────────────
ROOT="$(git rev-parse --show-toplevel 2>/dev/null || true)"
[[ -n "$ROOT" ]] || ROOT="$PWD"

REL="prototype/$FEATURE/$SLUG/"
mkdir -p "$ROOT/$REL"

GITIGNORE="$ROOT/prototype/.gitignore"
UPDATED=0

# Append a whole line only if that exact line is not already present. Only ever
# grows the file (never rewrites), so an existing tree is never corrupted.
append_if_absent() { # $1=file $2=line
    local file="$1" line="$2"
    if [[ -f "$file" ]] && grep -qxF "$line" "$file"; then
        return 0
    fi
    printf '%s\n' "$line" >> "$file"
    UPDATED=1
}

# Default contents for every tier: ignore all, keep the gitignore itself.
append_if_absent "$GITIGNORE" '*'
append_if_absent "$GITIGNORE" '!.gitignore'

# share un-ignores the folder (parent-first so children are reachable).
if [[ "$TIER" == "share" ]]; then
    append_if_absent "$GITIGNORE" "!$FEATURE/"
    append_if_absent "$GITIGNORE" "!$FEATURE/$SLUG/"
    append_if_absent "$GITIGNORE" "!$FEATURE/$SLUG/**"
fi

if [[ "$UPDATED" -eq 1 ]]; then GITIGNORE_UPDATED="true"; else GITIGNORE_UPDATED="false"; fi
printf '{"path":"%s","tier":"%s","gitignore_updated":%s}\n' "$REL" "$TIER" "$GITIGNORE_UPDATED"
