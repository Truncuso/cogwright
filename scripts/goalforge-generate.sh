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
#   ii.  child->root `../` climbs, RESTRICTED to a known landing site:
#          ../(scripts|references|hooks|commands|workflow-authoring)/        -> ${CLAUDE_PLUGIN_ROOT}[:-<orig>]/<shared-dir>
#          ../<child>/ (a dir with SKILL.md)                                 -> ${CLAUDE_PLUGIN_ROOT}/skills/<child>/
#          any other `../` shape                                             -> left UNREWRITTEN, for the reference lint to see
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
#         Neither shape occurs in the tree today; a new one must be fixed at
#         source, not carved out.
#
# .vendored-allowlist.txt is the last hand-authored, non-package plugin file:
# it is PRESERVED, never regenerated and never deleted by this script.
# commands/ and relations.yaml left that set in wp-03, hooks/ (scripts +
# hooks.json) in wp-04 — all are authored under packages/goalforge/ and ship
# through the ordinary copy pass, so the `diff -rq` tree gate covers them. That
# gate subsumes the byte-pair hooks cmp check wp-04 deleted.
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
# Version authority: packages/goalforge/SKILL.md `metadata.version` is the ONLY
# hand-bumped version in the flow (SKILL.md -> plugin.json -> README catalog).
# There is deliberately no env override — an overridable version reintroduces the
# drift this single authority exists to remove. A version-less manifest fails
# `claude plugin validate --strict`, so an unreadable or non-semver value is a
# hard abort rather than a silently omitted field.
PLUGIN_VERSION="$(awk '/^---$/{f++;next} f==1 && /^  version:/{gsub(/[" ]/,"",$2);print $2;exit}' "$SRC/SKILL.md")"
case "$PLUGIN_VERSION" in
    [0-9]*.[0-9]*.[0-9]*) ;;
    *) echo "FATAL: packages/goalforge/SKILL.md metadata.version is absent or not semver: '$PLUGIN_VERSION'" >&2; exit 1 ;;
esac

# Author attribution is DERIVED from the marketplace owner — one authority, never
# hand-written into the generated manifest. `--strict` warns on a missing author.
PLUGIN_AUTHOR_JSON="$(python3 -c 'import json,sys; print(json.dumps({"name": json.load(open(sys.argv[1]))["owner"]["name"]}))' "$ROOT/.claude-plugin/marketplace.json")" \
    || { echo "FATAL: cannot derive author from .claude-plugin/marketplace.json owner.name" >&2; exit 1; }

# Hand-authored, non-package plugin files preserved across regeneration.
PRESERVE=(.vendored-allowlist.txt)

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
# PYTHONDONTWRITEBYTECODE: the manifest emitter imports scripts/goalforge_refs.py;
# a __pycache__/ beside it would be untracked generator droppings in the repo.
PYTHONDONTWRITEBYTECODE=1 \
GF_PRESERVE="$_preserve_csv" GF_SCRIPTS_DIR="$SCRIPT_DIR" GF_REF_IGNORE="$ROOT/scripts/lint-baselines/reference-ignore.txt" \
python3 - "$DST" <<'PYEOF'
import json, os, re, sys

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

# Shared dirs that sit at the plugin root — the only `../` landing sites the
# restricted class-ii climb rewrites (besides a child skill).
SHARED_ROOT_DIRS = ("scripts", "references", "hooks", "commands",
                    "workflow-authoring")

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
    # (ii) prose child->root climbs via CLAUDE_SKILL_DIR. RESTRICTED, not
    # general: the climb is rewritten only when the segment it lands on is a
    # KNOWN plugin-root address — a shared root dir, or a child skill (which the
    # flat layout puts under skills/<child>/). Any other `../` shape is left
    # UNREWRITTEN so the reference lint sees it, rather than being blessed into
    # a plugin-root path that may not exist.
    for _sd in SHARED_ROOT_DIRS:
        text = text.replace("${CLAUDE_SKILL_DIR}/../%s/" % _sd,
                            "${CLAUDE_PLUGIN_ROOT}/%s/" % _sd)
        text = text.replace("$CLAUDE_SKILL_DIR/../%s/" % _sd,
                            "${CLAUDE_PLUGIN_ROOT}/%s/" % _sd)
    for _ch in children:
        text = text.replace("${CLAUDE_SKILL_DIR}/../%s/" % _ch,
                            "${CLAUDE_PLUGIN_ROOT}/skills/%s/" % _ch)
        text = text.replace("$CLAUDE_SKILL_DIR/../%s/" % _ch,
                            "${CLAUDE_PLUGIN_ROOT}/skills/%s/" % _ch)
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
        # A PRESERVE entry naming a top-level FILE is invisible to the `top`
        # test above (rel_dir is "." there), so it is skipped explicitly —
        # hand-authored content is never rewritten.
        if rel_dir == "." and name in preserve:
            continue
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

# ── Reference manifest (schema 1) ────────────────────────────────
# One authority for "which path does a shipped .md name": ci-lints and the
# wp-07 doctor read this file instead of re-deriving the token grammar, which
# itself lives once in scripts/goalforge_refs.py (shared with the package-side
# lint). Emitted AFTER the rewrite passes above, over the GENERATED tree minus
# every PRESERVE entry, so --check re-runs byte-identical.
_scripts_dir = os.environ.get("GF_SCRIPTS_DIR")
if not _scripts_dir:
    sys.exit("FATAL: GF_SCRIPTS_DIR unset — the manifest emitter cannot locate "
             "goalforge_refs.py (the shared token grammar)")
sys.path.append(_scripts_dir)
import goalforge_refs as gfrefs

refs = gfrefs.collect_refs(
    dst,
    gfrefs.plugin_child_of,
    ignore_pats=gfrefs.load_ignore_list(os.environ["GF_REF_IGNORE"]),
    skip_top=preserve,
)

# A token that climbs out of the plugin tree is a violation, not a manifest
# entry: emitting a manifest without it would launder the escape past every
# consumer. Refuse to emit, naming the source file and the offending token.
_escapes = ["%s -> %s" % (f, p.split(":", 1)[1])
            for f, p in refs if p.startswith(gfrefs.ESCAPE_MARKER + ":")]
if _escapes:
    sys.exit("FATAL: reference escapes the plugin tree (refusing to emit "
             "the manifest):\n  " + "\n  ".join(_escapes))

_manifest = os.path.join(dst, "references", "reference-manifest.json")
os.makedirs(os.path.dirname(_manifest), exist_ok=True)
with open(_manifest, "w", encoding="utf-8", newline="") as fh:
    json.dump({"schema": 1,
               "refs": [{"from": f, "path": p} for f, p in refs]},
              fh, indent=2)
    fh.write("\n")
PYEOF

# ── 4. Generate the plugin manifest (version + author derived; see above) ──
mkdir -p "$DST/.claude-plugin"
printf '%s\n' \
    '{' \
    '  "name": "goalforge",' \
    "  \"version\": \"$PLUGIN_VERSION\"," \
    "  \"author\": $PLUGIN_AUTHOR_JSON," \
    "  \"description\": \"$PLUGIN_DESC\"" \
    '}' > "$DST/.claude-plugin/plugin.json"

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
    exit 0
fi
