#!/usr/bin/env bash
# goalforge-hooks-json.test.sh — the REGISTRATION oracle (b6).
#
# Nothing else in this package asserts what hooks.json contains, so a hook that
# is written, green and never wired passes every other gate in the suite. This
# test closes that hole with an EXPLICIT expected-registration table — not a
# universal quantifier over hooks/goalforge-*.sh, which is false for the three
# files that are deliberately unregistered:
#
#   goalforge-plans-root.sh   a SOURCED library, not a hook
#   goalforge-pre-commit.sh   a git hook, installed by goalforge-install-hooks.sh
#   goalforge-quota-read.sh   the quota adapter, called by the launch gate
#
# "exactly one command entry" means one entry across ALL matcher groups: two
# hooks can share one group's hooks[] array (transition-guard and
# open-questions-gate already do), so counting GROUPS would be wrong.
#
# Every command string carries the literal ${CLAUDE_PLUGIN_ROOT}; the checker
# substitutes the package root for it before resolving the file.
set -uo pipefail

HD="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PKG="$(cd "$HD/.." && pwd)"
JSON="$HD/hooks.json"
PASS=0; FAIL=0
ok()  { echo "  PASS: $1"; PASS=$((PASS+1)); }
bad() { echo "  FAIL: $1"; FAIL=$((FAIL+1)); }

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

CHECKER="$WORK/check_hooks_json.py"
cat > "$CHECKER" <<'PY'
"""Check one hooks.json against the expected-registration table.

argv: <hooks.json> <package-root> <README.md>
Prints one `PASS|<msg>` or `FAIL|<msg>` line per assertion; exits 1 if any
assertion failed, 2 if the file could not be parsed at all.
"""
import json, re, sys, os

MUST_HAVE = {
    # script basename -> (event, matcher) — every matcher is a literal str;
    # no row may reintroduce the old `None` ("don't care") short-circuit.
    "goalforge-launch-gate.sh":        ("PreToolUse",  "Agent|Workflow"),
    "goalforge-context-fill.sh":       ("SessionStart", "startup|resume|clear|compact"),
    "goalforge-session-start.sh":      ("SessionStart", "startup|resume|clear|compact"),
    "goalforge-single-writer.sh":      ("PreToolUse",  "Edit|Write|MultiEdit|mcp__lean-ctx__ctx_patch|mcp__lean-ctx__ctx_call"),
    "goalforge-transition-guard.sh":   ("PreToolUse",  "Edit"),
    "goalforge-open-questions-gate.sh": ("PreToolUse",  "Edit"),
    "goalforge-frontmatter-touch.sh":  ("PostToolUse", "Edit|Write|MultiEdit"),
}
assert all(isinstance(matcher, str) for _event, matcher in MUST_HAVE.values()), \
    "MUST_HAVE matcher must be a literal str, never None"
MUST_NOT_HAVE = (
    "goalforge-plans-root.sh",     # sourced library
    "goalforge-pre-commit.sh",     # git hook
    "goalforge-quota-read.sh",     # adapter called by the launch gate
)
BYPASS_NAMES = ("GOALFORGE_LAUNCH_GATE", "GOALFORGE_LAUNCH_THRESHOLD_PCT")

failed = False
def say(okness, msg):
    global failed
    if not okness:
        failed = True
    print(("PASS|" if okness else "FAIL|") + msg)

path, root = sys.argv[1], sys.argv[2]
readme_path = sys.argv[3] if len(sys.argv) > 3 else None
try:
    with open(path, encoding="utf-8") as fh:
        doc = json.load(fh)
except Exception as exc:                      # noqa: BLE001
    print("FAIL|hooks.json does not parse: %s" % exc)
    sys.exit(2)

# Flatten to (event, matcher, command) — one row per COMMAND ENTRY.
entries = []
for event, groups in (doc.get("hooks") or {}).items():
    for group in groups or []:
        matcher = group.get("matcher")
        for hook in group.get("hooks") or []:
            if hook.get("type") == "command":
                entries.append((event, matcher, hook.get("command") or ""))

say(bool(entries), "hooks.json declares at least one command entry (%d)" % len(entries))

for script, (want_event, want_matcher) in sorted(MUST_HAVE.items()):
    hits = [e for e in entries if script in e[2]]
    if len(hits) != 1:
        say(False, "%s: expected exactly 1 command entry, found %d" % (script, len(hits)))
        continue
    event, matcher, _cmd = hits[0]
    okness = event == want_event and matcher == want_matcher
    say(okness, "%s registered on %s (matcher %r)%s" % (
        script, event, matcher,
        "" if okness else " — want %s / %r" % (want_event, want_matcher)))

for script in MUST_NOT_HAVE:
    hits = [e for e in entries if script in e[2]]
    say(not hits, "%s is NOT registered (it is not a plugin hook)" % script)

for event, matcher, cmd in entries:
    if "${CLAUDE_PLUGIN_ROOT}" not in cmd:
        say(False, "command does not use ${CLAUDE_PLUGIN_ROOT}: %s" % cmd)
        continue
    resolved = cmd.replace("${CLAUDE_PLUGIN_ROOT}", root)
    target = None
    for token in resolved.replace('"', " ").split():
        if token.endswith(".sh"):
            target = token
            break
    say(target is not None and os.path.isfile(target),
        "registered command resolves to an existing file: %s" % (target or resolved))

# A guardrail must never name its own bypass switch on the surface the model
# reads (hooks.json reaches the model same as stderr does) — scan the whole
# serialized document, not just group descriptions.
serialized_doc = json.dumps(doc)
for name in BYPASS_NAMES:
    hit = name in serialized_doc
    say(not hit, "no hooks.json document names %s" % name)

# README `Hooks the plugin registers` table must match hooks.json row for
# row, as (hook, event, matcher) triples — README cells escape pipes as
# `\|`, so unescape before comparing.
if readme_path is not None:
    try:
        with open(readme_path, encoding="utf-8") as fh:
            readme = fh.read()
    except Exception as exc:                  # noqa: BLE001
        say(False, "README.md could not be read: %s" % exc)
    else:
        row_re = re.compile(
            r"^\|\s*`([^`]+)`\s*\|\s*([A-Za-z]+)\s*\|\s*`([^`]+)`\s*\|\s*$",
            re.MULTILINE)
        readme_triples = {
            (hook, event, matcher.replace("\\|", "|"))
            for hook, event, matcher in row_re.findall(readme)
        }
        json_triples = set()
        for event, matcher, cmd in entries:
            target = None
            for token in cmd.replace('"', " ").split():
                if token.endswith(".sh"):
                    target = os.path.basename(token)
                    break
            if target:
                json_triples.add((target, event, matcher))
        say(bool(readme_triples), "README table has at least one hook row")
        missing = json_triples - readme_triples
        extra = readme_triples - json_triples
        say(not missing and not extra,
            "README table matches hooks.json row for row%s%s" % (
                "" if not missing else " — README missing: %s" % sorted(missing),
                "" if not extra else " — README has extra: %s" % sorted(extra)))
        for name in BYPASS_NAMES:
            say(name in readme, "README §Install still documents %s" % name)

sys.exit(1 if failed else 0)
PY

run_checker() { # <hooks.json> [readme.md]
    python3 "$CHECKER" "$1" "$PKG" "${2:-$PKG/README.md}" 2>&1
}

# ── the shipped hooks.json ────────────────────────────────────────────────
OUT="$(run_checker "$JSON")"; rc=$?
while IFS='|' read -r verdict msg; do
    [ -n "$msg" ] || continue
    [ "$verdict" = "PASS" ] && ok "$msg" || bad "$msg"
done <<<"$OUT"
[ "$rc" -eq 0 ] || bad "shipped hooks.json failed the registration table (exit $rc)"

# ── sabotage: mutated copies, each must be REJECTED ────────────────────────
mutate() { # <label> <sed program editing $JSON syntactically>
    local label="$1" prog="$2" copy="$WORK/mutant.json" mrc=0 out
    sed "$prog" "$JSON" > "$copy"
    if cmp -s "$JSON" "$copy"; then
        bad "sabotage setup failed (no change applied): $label"
        return
    fi
    out="$(run_checker "$copy" 2>&1)"; mrc=$?
    if [ "$mrc" -eq 2 ] && grep -q "does not parse" <<<"$out"; then
        bad "sabotage setup produced invalid JSON: $label"
        return
    fi
    [ "$mrc" -ne 0 ] && ok "sabotage caught: $label" || bad "sabotage NOT caught: $label"
}

# 1. the launch-gate row removed
python3 - "$JSON" "$WORK/no-gate.json" <<'PY'
import json, sys
doc = json.load(open(sys.argv[1], encoding="utf-8"))
doc["hooks"]["PreToolUse"] = [g for g in doc["hooks"]["PreToolUse"]
                              if not any("launch-gate" in h.get("command", "")
                                         for h in g.get("hooks", []))]
json.dump(doc, open(sys.argv[2], "w", encoding="utf-8"))
PY
run_checker "$WORK/no-gate.json" >/dev/null 2>&1 \
    && bad "sabotage NOT caught: launch-gate row removed" \
    || ok "sabotage caught: launch-gate row removed"

# 2. matcher Task instead of Agent|Workflow
mutate "launch gate wired to matcher Task" 's#"matcher": "Agent|Workflow"#"matcher": "Task"#'

# 3. a command naming a file that does not exist
mutate "registered command names a missing file" \
    's#hooks/goalforge-launch-gate.sh#hooks/goalforge-does-not-exist.sh#'

# 4. the sourced library registered as a hook
python3 - "$JSON" "$WORK/lib-wired.json" <<'PY'
import json, sys
doc = json.load(open(sys.argv[1], encoding="utf-8"))
doc["hooks"]["PreToolUse"].append({
    "matcher": "Edit",
    "hooks": [{"type": "command",
               "command": 'bash "${CLAUDE_PLUGIN_ROOT}/hooks/goalforge-plans-root.sh"',
               "timeout": 5}],
})
json.dump(doc, open(sys.argv[2], "w", encoding="utf-8"))
PY
run_checker "$WORK/lib-wired.json" >/dev/null 2>&1 \
    && bad "sabotage NOT caught: goalforge-plans-root.sh registered as a hook" \
    || ok "sabotage caught: goalforge-plans-root.sh registered as a hook"

# 5. (b1 i) SessionStart matcher narrowed back to pre-wp-09 (drops resume)
python3 - "$JSON" "$WORK/sessionstart-narrowed.json" <<'PY'
import json, sys
doc = json.load(open(sys.argv[1], encoding="utf-8"))
for group in doc["hooks"]["SessionStart"]:
    if group.get("matcher") == "startup|resume|clear|compact":
        group["matcher"] = "startup|clear|compact"
json.dump(doc, open(sys.argv[2], "w", encoding="utf-8"))
PY
run_checker "$WORK/sessionstart-narrowed.json" >/dev/null 2>&1 \
    && bad "sabotage NOT caught: SessionStart matcher back to startup|clear|compact" \
    || ok "sabotage caught: SessionStart matcher back to startup|clear|compact"

# 6. (b1 ii) mcp__lean-ctx__ctx_call dropped from the single-writer matcher
python3 - "$JSON" "$WORK/singlewriter-narrowed.json" <<'PY'
import json, sys
doc = json.load(open(sys.argv[1], encoding="utf-8"))
suffix = "|mcp__lean-ctx__ctx_call"
for group in doc["hooks"]["PreToolUse"]:
    matcher = group.get("matcher") or ""
    if matcher.endswith(suffix):
        group["matcher"] = matcher[: -len(suffix)]
json.dump(doc, open(sys.argv[2], "w", encoding="utf-8"))
PY
run_checker "$WORK/singlewriter-narrowed.json" >/dev/null 2>&1 \
    && bad "sabotage NOT caught: mcp__lean-ctx__ctx_call dropped from the single-writer matcher" \
    || ok "sabotage caught: mcp__lean-ctx__ctx_call dropped from the single-writer matcher"

# 7. (b1 iii) the PostToolUse matcher altered
python3 - "$JSON" "$WORK/posttooluse-altered.json" <<'PY'
import json, sys
doc = json.load(open(sys.argv[1], encoding="utf-8"))
for group in doc["hooks"]["PostToolUse"]:
    if group.get("matcher") == "Edit|Write|MultiEdit":
        group["matcher"] = "Edit|Write"
json.dump(doc, open(sys.argv[2], "w", encoding="utf-8"))
PY
run_checker "$WORK/posttooluse-altered.json" >/dev/null 2>&1 \
    && bad "sabotage NOT caught: PostToolUse matcher altered" \
    || ok "sabotage caught: PostToolUse matcher altered"

# 8. (b3) hooks.json with the pre-wp-09 :13 description restored (names both
#    bypass switches again)
python3 - "$JSON" "$WORK/old-desc.json" <<'PY'
import json, sys
doc = json.load(open(sys.argv[1], encoding="utf-8"))
for group in doc["hooks"]["PreToolUse"]:
    if any("launch-gate" in h.get("command", "") for h in group.get("hooks", [])):
        group["description"] = (
            "goalforge launch gate: refuses a NEW Agent/Workflow dispatch when "
            "the remaining 5h quota is below GOALFORGE_LAUNCH_THRESHOLD_PCT "
            "(default 10) — a dispatch launched below it dies on the rate "
            "limit and loses its work. Quota comes from "
            "hooks/goalforge-quota-read.sh, which is an adapter and is "
            "deliberately NOT registered here. Unknown quota, or "
            "GOALFORGE_LAUNCH_GATE=0, exits 0 silently; the explanatory WARN "
            "prints once per session."
        )
json.dump(doc, open(sys.argv[2], "w", encoding="utf-8"))
PY
run_checker "$WORK/old-desc.json" >/dev/null 2>&1 \
    && bad "sabotage NOT caught: pre-wp-09 :13 description restored" \
    || ok "sabotage caught: pre-wp-09 :13 description restored"

# 9. (b3) README table carrying the pre-wp-09 SessionStart matcher
README="$PKG/README.md"
sed 's#startup\\|resume\\|clear\\|compact#startup\\|clear\\|compact#' \
    "$README" > "$WORK/old-readme.md"
run_checker "$JSON" "$WORK/old-readme.md" >/dev/null 2>&1 \
    && bad "sabotage NOT caught: README carrying the pre-wp-09 SessionStart matcher" \
    || ok "sabotage caught: README carrying the pre-wp-09 SessionStart matcher"

echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
