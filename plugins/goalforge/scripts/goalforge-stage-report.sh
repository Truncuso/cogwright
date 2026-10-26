#!/usr/bin/env bash
# goalforge-stage-report.sh — emit ONE stage.report event and render it for the
# human through references/templates/stage-report.md (spec.md C6/C7, wp-07).
#
# The payload is validated against references/schema/stage-report.schema.json
# using goalforge-trace-emit's own `_validate` — imported, never re-implemented,
# so the schema, the emitter and this renderer cannot drift apart. There is no
# JSON-Schema library in this environment; that validator is the oracle.
#
# Usage:
#   goalforge-stage-report.sh <stage> <wp> --json <payload.json>
#       [--feature-dir <dir>]   emit the trace row (omit: render only)
#       [--repo <dir>]          repo root for reader resolution (default: git)
#       [--previous <file>]     render only what changed against that report
#                               (spec `revise` rounds — never the whole draft)
#
# Exit codes:
#   0  rendered (and, with --feature-dir, one row appended)
#   2  payload invalid — nothing emitted, nothing rendered
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec python3 - "$HERE" "$@" <<'PY'
import json
import subprocess
import sys
from importlib.machinery import SourceFileLoader
from pathlib import Path

MAX_LINES = 40                      # the whole render budget (C7 / template)
HERE = Path(sys.argv[1]).resolve()
argv = sys.argv[2:]
EMIT = HERE / "goalforge-trace-emit"
READER = HERE / "goalforge-reader.sh"
SCHEMA = HERE.parent / "references" / "schema" / "stage-report.schema.json"


def die(msg: str) -> None:
    print(f"goalforge-stage-report: {msg}", file=sys.stderr)
    raise SystemExit(2)


def opt(name: str):
    if name in argv:
        i = argv.index(name)
        if i + 1 >= len(argv):
            die(f"{name} needs a value")
        return argv[i + 1]
    return None


positional = [a for i, a in enumerate(argv) if not a.startswith("--")
              and (i == 0 or not argv[i - 1].startswith("--"))]
if len(positional) < 2:
    die("usage: goalforge-stage-report.sh <stage> <wp> --json <payload.json>")
stage, wp = positional[0], positional[1]

json_path = opt("--json")
if not json_path:
    die("--json <payload.json> is required")
feature_dir = opt("--feature-dir")
previous_path = opt("--previous")

try:
    payload = json.loads(Path(json_path).read_text(encoding="utf-8"))
except (OSError, json.JSONDecodeError) as exc:
    die(f"cannot read payload: {exc}")
if not isinstance(payload, dict):
    die("payload is not a JSON object")

payload["stage"] = stage
payload["wp"] = wp


# ── reader (C8) ─────────────────────────────────────────────────────────────
def reader_call(*flags) -> str:
    cmd = ["bash", str(READER), *flags]
    if opt("--repo"):
        cmd += ["--repo", opt("--repo")]
    if feature_dir:
        cmd += ["--feature-dir", feature_dir]
    try:
        res = subprocess.run(cmd, capture_output=True, text=True)
    except OSError:
        return ""
    if res.returncode != 0:
        # A refused slug is the reader's own hard error; surface it verbatim.
        sys.stderr.write(res.stderr)
        raise SystemExit(2)
    return res.stdout.strip()


payload["reader"] = reader_call("--slug") or "anonymous"
seen = [s for s in reader_call("--seen").splitlines() if s.strip()]


# ── --previous: render the DIFF, never the whole draft again (C7) ───────────
if previous_path:
    try:
        prev = json.loads(Path(previous_path).read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        die(f"cannot read --previous: {exc}")
    prev_changed = {(c.get("text"), c.get("ref")) for c in prev.get("changed", [])}
    prev_issues = {(i.get("id"), i.get("text"), i.get("ref"))
                   for i in prev.get("issues", [])}
    payload["changed"] = [c for c in payload.get("changed", [])
                          if (c.get("text"), c.get("ref")) not in prev_changed]
    payload["issues"] = [i for i in payload.get("issues", [])
                         if (i.get("id"), i.get("text"), i.get("ref"))
                         not in prev_issues]

# ── assumed_known: shrink context, never a gate (OQ1) ───────────────────────
assumed = list(payload.get("assumed_known", []))
kept = []
for issue in payload.get("issues", []):
    ident = issue.get("id")
    if ident and ident in seen:
        if ident not in assumed:
            assumed.append(ident)
    else:
        kept.append(issue)
payload["issues"] = kept
if assumed:
    payload["assumed_known"] = assumed

# ── validate (the oracle) ───────────────────────────────────────────────────
try:
    emitter = SourceFileLoader("goalforge_trace_emit", str(EMIT)).load_module()
    schema = json.loads(SCHEMA.read_text(encoding="utf-8"))
except (OSError, ValueError) as exc:
    die(f"cannot load the stage.report schema or validator: {exc}")

errs = emitter._validate(payload, schema)
if errs:
    for err in errs:
        print(f"goalforge-stage-report: invalid payload: {err}", file=sys.stderr)
    raise SystemExit(2)

# ── emit exactly one row, appended never rewritten ──────────────────────────
trace_ref = "trace-events.jsonl#pending"
if feature_dir:
    event = {"type": "stage.report", **payload}
    res = subprocess.run(
        [sys.executable, str(EMIT), "--feature-dir", feature_dir,
         "--event", json.dumps(event), "--print-row"],
        capture_output=True, text=True)
    if res.returncode != 0:
        sys.stderr.write(res.stderr)
        raise SystemExit(2)
    try:
        trace_ref = f"trace-events.jsonl#seq-{json.loads(res.stdout)['seq']}"
    except (ValueError, KeyError):
        pass


# ── render (references/templates/stage-report.md) ───────────────────────────
def issue_lines(issue: dict) -> list[str]:
    ident = issue.get("id")
    head = f"- [{ident}] " if ident else "- "
    out = [f"{head}{issue['text']} — {issue['ref']}"]
    if issue.get("evidence"):
        out.append(f"  evidence: {issue['evidence']}")
    for option in issue.get("options", []):
        out.append(f"  option {option['label']}: "
                   f"pro {option['pro']} / con {option['con']}")
    tail = []
    if issue.get("recommended"):
        tail.append(f"recommended: {issue['recommended']}")
    tail.append(f"owner: {issue['owner']}")
    out.append("  " + "  |  ".join(tail))
    return out


def section(title: str, body: list[str]) -> list[str]:
    return ["", f"## {title}", *(body or ["- (none)"])]


head = [f"# {stage} report — {wp}"]
changed = section("Changed", [f"- {c['text']} — {c['ref']}"
                              for c in payload.get("changed", [])])
# `Next gate` is built BEFORE the issue budget and is never collapsed (OQ1).
gate = payload["next_gate"]
gate_block = section("Next gate", [f"- {gate['ask']} — {gate['ref']}"])
known = section("Assumed known",
                [f"- {i} — already seen; see {trace_ref}"
                 for i in payload.get("assumed_known", [])])

issues = payload.get("issues", [])
rendered = [issue_lines(i) for i in issues]
fixed = len(head) + len(changed) + len(gate_block) + len(known) + 2  # + heading

if fixed + sum(len(r) for r in rendered) <= MAX_LINES:
    body = [line for block in rendered for line in block]
else:
    budget = MAX_LINES - fixed - 1          # one line reserved for the overflow
    body, used, collapsed = [], 0, []
    for issue, block in zip(issues, rendered):
        if not collapsed and used + len(block) <= budget:
            body.extend(block)
            used += len(block)
        else:
            collapsed.append(issue.get("id") or issue["ref"])
    body.append(f"- +{len(collapsed)} more ({', '.join(collapsed)}) "
                f"— see {trace_ref}")

print("\n".join(head + changed + section("Issues", body)
                + gate_block + known))
PY
