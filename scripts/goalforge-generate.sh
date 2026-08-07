#!/usr/bin/env bash
# goalforge-generate.sh — deterministic, offline generator for the flat
# goalforge plugin artifact.
#
#   SOURCE : packages/goalforge/         (canonical nested v2 package)
#   OUTPUT : plugins/goalforge/          (flat, plugin-discoverable artifact)
#
# Pure file transformation — no LLM calls, no network, byte-stable and
# idempotent: re-running leaves plugins/goalforge/ untouched
# (test -z "$(git status --porcelain plugins/goalforge)").
#
# Mapping
#   packages/goalforge/SKILL.md, README.md            -> plugins/goalforge/<same>
#   packages/goalforge/scripts/, references/          -> plugins/goalforge/<same>   (shared, root-level)
#   packages/goalforge/<child>/  (dir with SKILL.md)  -> plugins/goalforge/skills/<child>/
#   packages/goalforge/<other-dir> (no SKILL.md)      -> plugins/goalforge/<same>   (e.g. workflow-authoring/)
#   packages/goalforge/evals/                         -> EXCLUDED (workspace/pyc pollution; consumers get `claude plugin validate`)
#   **/__pycache__/**, *.pyc                          -> EXCLUDED
#
# Path-rewrite rule table (pinned, wp-17 harden panel — classes i..vii):
#   i.   root-script sibling refs ($SCRIPT_DIR/../references, ../hooks)     -> no-op (depth preserved at plugin root)
#   ii.  child->root /scripts climbs                                        -> ${CLAUDE_PLUGIN_ROOT}[:-<orig>]/scripts
#   iii. ${CLAUDE_SKILL_DIR}/<sub> prose (in a child skill)                 -> ${CLAUDE_PLUGIN_ROOT}/skills/<child>/<sub>
#   iv.  telemetry hook decls (skill-measure.sh / skill-trace.sh)           -> stripped from generated SKILL.md frontmatter
#   v.   skills/sdd refs                                                    -> left verbatim (never rewritten to a dead plugin path; wp-21 retirement)
#   vi.  cross-skill prose (autopilot / idea / capture-learning)            -> left verbatim
#   vii. ${CLAUDE_PLUGIN_ROOT:-<local-fallback>} dual-mode form             -> used for the class-ii executable climbs
#   viii. author install paths (~ | $HOME | ${HOME})/.claude/skills/goalforge
#         -> child-aware: /<child>/... (dir with SKILL.md) becomes
#            ${CLAUDE_PLUGIN_ROOT}/skills/<child>/..., everything else
#            (references/, scripts/, workflow-authoring/, hooks/) becomes
#            ${CLAUDE_PLUGIN_ROOT}/... at the plugin root.
#         SCOPE: the generator rewrites the three ABSOLUTE forms only. The two
#         other author-path shapes the author-paths lint knows about are
#         lint-only and must be fixed AT SOURCE, never here:
#           - the relative `../skills/goalforge` climb (no absolute anchor to
#             rewrite; a generated `${CLAUDE_PLUGIN_ROOT}` would be wrong for
#             prose that is genuinely relative)
#           - `$HOME/dotfiles` (a machine layout, not a goalforge path)
#         Both are carved out in scripts/lint-baselines/author-paths-carveouts.txt
#         for the PRESERVE'd hooks/ tree until wp-04 takes hooks/ out of PRESERVE
#         and fixes them at source.
#
# Non-package plugin-packaging files (hooks/, commands/, relations.yaml,
# .vendored-allowlist.txt)
# are hand-authored and NOT derived from the package; they are PRESERVED, never
# regenerated and never deleted by this script.
#
# Usage:
#   goalforge-generate.sh            regenerate the artifact in place
#   goalforge-generate.sh --check    regenerate, then fail (exit 2) if the tree drifted
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SRC="$ROOT/packages/goalforge"
DST="$ROOT/plugins/goalforge"

MODE="${1:-generate}"

# --check is side-effect-free: it generates into a throwaway staging dir and
# diffs that against the real plugins/goalforge, so it NEVER writes into the
# artifact and NEVER consults git (staged legitimate changes must not false-block).
REAL_DST="$DST"
CHECK=0
if [ "$MODE" = "--check" ]; then
    CHECK=1
    STAGING="$(mktemp -d)"
    trap 'rm -rf "$STAGING"' EXIT
    DST="$STAGING/goalforge"
fi

PLUGIN_DESC="Goal-and-verification-driven development chain for Claude Code — goal-object work packages with a harden/execute/verify lifecycle."
# GF_PLUGIN_VERSION: stamp this "version" field into plugin.json.
# Version experiment (wp-17 task-02, 2026-07-21): a version-LESS manifest passes
# `claude plugin validate` (exit 0, warning only) but FAILS `--strict` (exit 1 —
# the missing-version warning is promoted to an error). Per the pinned decision
# rule (keep version-less only if BOTH pass), the manifest stamps the cogwright
# commit SHA as the version. This is a STATIC literal, not a runtime
# `git rev-parse HEAD` (that would drift after each commit and break the drift
# gate); bump it deliberately when the package changes materially. Use `-` (not
# `:-`) so `GF_PLUGIN_VERSION=` reproduces the version-less experiment.
GF_PLUGIN_VERSION="${GF_PLUGIN_VERSION-33b31eab96c9}"

# Hand-authored, non-package plugin files preserved across regeneration.
PRESERVE=(hooks commands relations.yaml .vendored-allowlist.txt)

[ -d "$SRC" ] || { echo "FATAL: source not found: $SRC" >&2; exit 1; }

# ── 0. Pre-flight: child-skill names must not collide with plugin-root dirs ──
# The class-viii rewrite routes a path segment to skills/<child>/ iff it names a
# child skill, and to the plugin root otherwise. That dispatch is only sound
# while the two namespaces are disjoint — a child skill named e.g. "scripts"
# would silently shadow the shared root dir. Checked BEFORE anything is written,
# so a clash aborts without leaving a half-generated artifact behind.
ROOT_NAMES=(references scripts hooks commands workflow-authoring .claude-plugin)
_clash=""
for entry in "$SRC"/*; do
    [ -d "$entry" ] && [ -f "$entry/SKILL.md" ] || continue
    base="$(basename "$entry")"
    for r in "${ROOT_NAMES[@]}"; do
        [ "$base" = "$r" ] && _clash="$_clash $base"
    done
done
if [ -n "$_clash" ]; then
    echo "FATAL: child skill name(s) collide with a plugin-root directory:$_clash" >&2
    echo "       the class-viii author-path rewrite cannot disambiguate them." >&2
    exit 1
fi

mkdir -p "$DST"

# ── 1. Clear generated content (keep the preserve list + the plugin dir itself) ──
_keep_expr=()
for k in "${PRESERVE[@]}"; do _keep_expr+=( ! -name "$k" ); done
find "$DST" -mindepth 1 -maxdepth 1 "${_keep_expr[@]}" -exec rm -rf {} +

# ── 2. Structural copy: package -> flat plugin (excluding evals/, __pycache__, *.pyc) ──
copy_filtered() { # src_dir dst_dir
    local s="$1" d="$2" f rel
    while IFS= read -r -d '' f; do
        rel="${f#"$s"/}"
        case "/$rel/" in */evals/*|*/__pycache__/*) continue;; esac
        case "$rel" in *.pyc) continue;; esac
        mkdir -p "$d/$(dirname "$rel")"
        cp "$f" "$d/$rel"
    done < <(find "$s" -type f -print0)
}

for entry in "$SRC"/*; do
    base="$(basename "$entry")"
    [ "$base" = "evals" ] && continue
    if [ -f "$entry" ]; then
        cp "$entry" "$DST/$base"                 # root file (SKILL.md, README.md)
    elif [ -d "$entry" ] && [ -f "$entry/SKILL.md" ]; then
        copy_filtered "$entry" "$DST/skills/$base"   # child skill -> skills/<child>/
    else
        copy_filtered "$entry" "$DST/$base"          # shared dir (scripts/, references/, workflow-authoring/)
    fi
done

# ── 3. Path-rewrite + telemetry-strip pass over the generated tree ──
_preserve_csv="$(IFS=,; echo "${PRESERVE[*]}")"
GF_PRESERVE="$_preserve_csv" python3 - "$DST" <<'PYEOF'
import os, re, sys

dst = sys.argv[1]
preserve = set(os.environ.get("GF_PRESERVE", "").split(","))

# Child set, enumerated at generation time with the copy-loop predicate
# (a package dir is a child skill iff it holds a SKILL.md); never hardcoded.
_skills_dir = os.path.join(dst, "skills")
children = {
    d for d in (os.listdir(_skills_dir) if os.path.isdir(_skills_dir) else [])
    if os.path.isfile(os.path.join(_skills_dir, d, "SKILL.md"))
}
# Disjointness of `children` vs the plugin-root dir names is a precondition of
# the class-viii dispatch below; it is asserted in the generator's step-0
# pre-flight, before anything is written.

def strip_telemetry(text):
    """Remove the top-level `hooks:` frontmatter block (100% skill-measure/
    skill-trace telemetry decls) from a generated SKILL.md. Byte-stable:
    only the hooks: line and its indented children are dropped."""
    lines = text.split("\n")
    if not lines or lines[0].strip() != "---":
        return text
    out = [lines[0]]
    i, in_fm, skipping = 1, True, False
    while i < len(lines):
        ln = lines[i]
        if in_fm and ln.strip() == "---":
            out.append(ln)
            out.extend(lines[i + 1:])
            return "\n".join(out)
        if in_fm:
            if not skipping and ln.rstrip() == "hooks:":
                skipping = True
                i += 1
                continue
            if skipping:
                if ln[:1] in (" ", "\t"):
                    i += 1
                    continue
                skipping = False
            out.append(ln)
            i += 1
            continue
    return "\n".join(out)

def rewrite_paths(text, child):
    # (ii) executable child->root /scripts climbs — dual-mode fallback (vii)
    text = text.replace("$SCRIPT_DIR/../../scripts",
                        "${CLAUDE_PLUGIN_ROOT:-$SCRIPT_DIR/../..}/scripts")
    text = text.replace("$SCRIPT_DIR/../scripts",
                        "${CLAUDE_PLUGIN_ROOT:-$SCRIPT_DIR/..}/scripts")
    # (ii) prose child->root /scripts climbs via CLAUDE_SKILL_DIR
    text = text.replace("${CLAUDE_SKILL_DIR}/../scripts", "${CLAUDE_PLUGIN_ROOT}/scripts")
    text = text.replace("$CLAUDE_SKILL_DIR/../scripts", "${CLAUDE_PLUGIN_ROOT}/scripts")
    # (iii) ${CLAUDE_SKILL_DIR}/<sub> prose within a child skill
    if child:
        text = text.replace("${CLAUDE_SKILL_DIR}/",
                            "${CLAUDE_PLUGIN_ROOT}/skills/%s/" % child)
    return text

# (viii) author install paths — all three absolute forms in one regex pass.
# The optional first path segment decides where the reference lands: a child
# skill goes under skills/<child>/, anything else at the plugin root.
# The segment may not END in `.` or `-`, so a sentence-final period or an
# em-dash-ish trailing hyphen in prose stays outside the match instead of being
# swallowed into the segment (which would break the `seg in children` lookup).
_AUTHOR_RE = re.compile(
    r"(?:~|\$HOME|\$\{HOME\})/\.claude/skills/goalforge"
    r"(?:/([A-Za-z0-9_][A-Za-z0-9_.-]*[A-Za-z0-9_]|[A-Za-z0-9_]))?")

def rewrite_author_paths(text, children):
    def _sub(m):
        seg = m.group(1)
        if seg is None:
            return "${CLAUDE_PLUGIN_ROOT}"
        if seg in children:
            return "${CLAUDE_PLUGIN_ROOT}/skills/" + seg
        return "${CLAUDE_PLUGIN_ROOT}/" + seg
    return _AUTHOR_RE.sub(_sub, text)

for base, dirs, files in os.walk(dst):
    rel_dir = os.path.relpath(base, dst)
    top = rel_dir.split(os.sep)[0] if rel_dir != "." else ""
    if top in preserve:
        dirs[:] = []
        continue
    for name in files:
        path = os.path.join(base, name)
        rel = os.path.relpath(path, dst)
        parts = rel.split(os.sep)
        child = parts[1] if len(parts) >= 3 and parts[0] == "skills" else None
        try:
            with open(path, "r", encoding="utf-8", newline="") as fh:
                text = fh.read()
        except (UnicodeDecodeError, IsADirectoryError):
            continue
        new = text
        if name == "SKILL.md":
            new = strip_telemetry(new)
        new = rewrite_paths(new, child)
        new = rewrite_author_paths(new, children)
        if new != text:
            with open(path, "w", encoding="utf-8", newline="") as fh:
                fh.write(new)
PYEOF

# ── 4. Generate the plugin manifest (commit-SHA version; see version experiment above) ──
mkdir -p "$DST/.claude-plugin"
if [ -n "$GF_PLUGIN_VERSION" ]; then
    printf '%s\n' \
        '{' \
        '  "name": "goalforge",' \
        "  \"version\": \"$GF_PLUGIN_VERSION\"," \
        "  \"description\": \"$PLUGIN_DESC\"" \
        '}' > "$DST/.claude-plugin/plugin.json"
else
    printf '%s\n' \
        '{' \
        '  "name": "goalforge",' \
        "  \"description\": \"$PLUGIN_DESC\"" \
        '}' > "$DST/.claude-plugin/plugin.json"
fi

# ── 5. --check: drift gate (side-effect-free, git-independent) ──
# Compare the freshly-generated staging tree against the committed-or-not real
# artifact, excluding the hand-authored PRESERVE entries (absent from staging).
# Exit 2 on any divergence; 0 when byte-identical. No writes into plugins/,
# no git status/HEAD consulted, staging cleaned up by the EXIT trap.
if [ "$CHECK" = 1 ]; then
    _excl=()
    for k in "${PRESERVE[@]}"; do _excl+=( --exclude="$k" ); done
    if diff_out="$(diff -rq "${_excl[@]}" "$REAL_DST" "$DST" 2>&1)"; then
        :
    else
        echo "DRIFT: plugins/goalforge/ differs from a fresh generation" >&2
        printf '%s\n' "$diff_out" >&2
        exit 2
    fi
    # hooks/ is on the PRESERVE list (hooks.json is plugin-specific), so the
    # tree diff above cannot see it — but the goalforge-*.sh guardrail hooks
    # MUST stay byte-identical to their packages/ source. Explicit pair check:
    hooks_drift=0
    for h in "$SRC/hooks/"goalforge-*.sh; do
        [ -f "$h" ] || continue
        base="$(basename "$h")"
        if ! cmp -s "$h" "$REAL_DST/hooks/$base"; then
            echo "DRIFT: plugins/goalforge/hooks/$base differs from packages/goalforge/hooks/$base" >&2
            hooks_drift=1
        fi
    done
    [ "$hooks_drift" = 0 ] || exit 2
    exit 0
fi
