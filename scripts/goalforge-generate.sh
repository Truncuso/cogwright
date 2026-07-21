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
#
# Non-package plugin-packaging files (hooks/, commands/, .vendored-allowlist.txt)
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
PRESERVE=(hooks commands .vendored-allowlist.txt)

[ -d "$SRC" ] || { echo "FATAL: source not found: $SRC" >&2; exit 1; }
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
import os, sys

dst = sys.argv[1]
preserve = set(os.environ.get("GF_PRESERVE", "").split(","))

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

# ── 5. --check: drift gate ──
if [ "$MODE" = "--check" ]; then
    if [ -n "$(git -C "$ROOT" status --porcelain plugins/goalforge)" ]; then
        echo "DRIFT: plugins/goalforge/ differs from a fresh generation" >&2
        git -C "$ROOT" status --porcelain plugins/goalforge >&2
        exit 2
    fi
fi
