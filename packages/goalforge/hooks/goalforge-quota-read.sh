#!/usr/bin/env bash
# goalforge-quota-read.sh — the ONE quota adapter. Prints a single JSON object
# on stdout and NEVER fails:
#
#   {"five_h_remaining_pct": N, "seven_d_remaining_pct": N}   when known
#   {}                                                        when unknown
#
# NOT a hook — it is registered nowhere in hooks.json and is called only by
# goalforge-launch-gate.sh. Isolating the source behind this file is what makes
# the gate testable on a host that exposes no quota at all.
#
# ── Source research (wp-04 T2 step 1, 2026-09-13) ──────────────────────────
# The installed Claude Code exposes NO remaining-quota percentage locally.
# What was checked, and what was found:
#   - `~/.claude/settings.json`, `~/.claude/*.json`: no quota/usage keys. The
#     one `rate_limit` hit is `agent-dispatch.json`'s per-provider request
#     budget ("40/60s"), unrelated to the Anthropic session window.
#   - no usage cache, statusline data file, or `~/.claude/data/*` stream
#     carries a session-window figure.
#   - the ONLY local trace of the limit is a `quotaLimits` object embedded in
#     assistant rows of the session transcripts under
#     `~/.claude/projects/<slug>/**/*.jsonl`, with fields:
#       status, resetsAt (unix seconds), rateLimitType ("five_hour"),
#       overageStatus, overageDisabledReason, upgradePaths, isUsingOverage,
#       unifiedRateLimitFallbackAvailable, lowPriority*
#     Every observed instance has `status: "rejected"` — the block is written
#     at the moment the 429 lands, carries no remaining percentage, and is
#     therefore a post-mortem record, not a pre-flight signal. Reading it
#     would tell the gate the quota is gone only after the dispatch it was
#     supposed to prevent has already failed.
# Conclusion: NOT EXPOSED. This adapter prints `{}` on this host, the launch
# gate exits 0 silently (OQ1), and the fixture override below is what the
# sabotage pair drives. If a future Claude Code publishes a remaining figure,
# this file is the only one that changes.
#
# ── Override ───────────────────────────────────────────────────────────────
#   GOALFORGE_QUOTA_FIXTURE=<path>   read the JSON object from that file
# An unset, missing, unreadable or unparseable fixture yields `{}` — the same
# unknown as no source at all. A quota source that cannot be read must never
# block the user's work.
#
# Usage:
#   goalforge-quota-read.sh               # prints the JSON object
#   goalforge-quota-read.sh --self-test
#
# ZERO-BREAKAGE: always exits 0.
set -uo pipefail

emit_unknown() { printf '{}\n'; }

# Print the fixture's JSON object iff it parses as an object; else `{}`.
read_fixture() {
    local path="$1"
    [ -n "$path" ] && [ -f "$path" ] || { emit_unknown; return 0; }
    command -v python3 >/dev/null 2>&1 || { emit_unknown; return 0; }
    GF_QUOTA_PATH="$path" python3 - <<'PY' 2>/dev/null || emit_unknown
import json, os, sys
try:
    with open(os.environ["GF_QUOTA_PATH"], encoding="utf-8") as fh:
        data = json.load(fh)
except Exception:
    print("{}"); sys.exit(0)
if not isinstance(data, dict):
    print("{}"); sys.exit(0)
out = {}
for key in ("five_h_remaining_pct", "seven_d_remaining_pct"):
    val = data.get(key)
    if isinstance(val, bool):
        continue                      # bool is an int in python; not a pct
    if isinstance(val, (int, float)):
        out[key] = val
print(json.dumps(out))
PY
}

self_test() {
    local p=0 f=0 d out
    ok() { echo "  PASS: $1"; p=$((p+1)); }
    no() { echo "  FAIL: $1"; f=$((f+1)); }
    echo "=== goalforge-quota-read.sh --self-test ==="
    d="$(mktemp -d)"
    trap 'rm -rf "$d"' RETURN

    printf '{"five_h_remaining_pct": 4, "seven_d_remaining_pct": 61}\n' > "$d/ok.json"
    out="$(GOALFORGE_QUOTA_FIXTURE="$d/ok.json" bash "$SELF")"
    case "$out" in *'"five_h_remaining_pct": 4'*) ok "fixture pct passed through" ;;
        *) no "fixture pct passed through -> '$out'" ;; esac

    printf 'not json at all\n' > "$d/bad.json"
    out="$(GOALFORGE_QUOTA_FIXTURE="$d/bad.json" bash "$SELF")"
    [ "$out" = "{}" ] && ok "unparseable fixture -> {}" || no "unparseable fixture -> '$out'"

    out="$(GOALFORGE_QUOTA_FIXTURE="$d/absent.json" bash "$SELF")"
    [ "$out" = "{}" ] && ok "absent fixture -> {}" || no "absent fixture -> '$out'"

    out="$(env -u GOALFORGE_QUOTA_FIXTURE bash "$SELF")"
    [ "$out" = "{}" ] && ok "no source on this host -> {}" || no "no source -> '$out'"

    echo ""
    echo "Results: $p passed, $f failed"
    [ "$f" -eq 0 ]
}

HOOK_DIR="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}" 2>/dev/null || printf '%s' "${BASH_SOURCE[0]}")")" && pwd)"
SELF="$HOOK_DIR/$(basename "${BASH_SOURCE[0]}")"

if [ "${1:-}" = "--self-test" ]; then
    self_test
    exit $?
fi

read_fixture "${GOALFORGE_QUOTA_FIXTURE:-}"
exit 0
