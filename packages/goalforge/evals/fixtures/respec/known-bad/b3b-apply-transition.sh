#!/usr/bin/env bash
# goalforge-respec-apply.sh — the ONLY writer of a revised spec.md (the respec
# edge, references/respec.md). Applies a human-ratified proposal.
#
# Usage:   goalforge-respec-apply.sh <feature-dir> <proposal-dir>
#          <proposal-dir> = <feature-dir>/respec/<YYYY-MM-DD>-<slug>/ holding
#          proposed-spec.md, diff.json (goalforge-respec-diff.sh output) and
#          RATIFIED, one line:
#            ratified_by: human date=<YYYY-MM-DD> sha256=<proposed-spec.md>
#              diff_sha256=<diff.json> base_sha256=<spec.md as ratified> reply=<verbatim>
#
# Refuses (exit 1, no write) when RATIFIED is absent or malformed (any of
# date=, sha256=, diff_sha256=, base_sha256= missing), when sha256= or
# diff_sha256= does not bind the current bytes, or when spec.md is neither the
# applied state (== sha256=) nor the ratified base (== base_sha256=). From the
# base it also refuses when a facet in goal_facets_changed has no added
# `## Goal Changelog` row in proposed-spec.md.
#
# Steps, each skip-if-present so a partial apply resumes:
#   1. supersede in place each `verified` WP whose contract_slice names a
#      changed/dropped key (superseded_by: + one ## Supersession note)
#   2. write <wp>/reharden/<date>-respec-<slug>.md for each such `ready` WP
#   3. copy proposed-spec.md over spec.md byte for byte
# Every date written is RATIFIED date=, never the wall clock. `ambiguous` keys
# are reported, never acted on. A rerun on the applied state is an exit-0
# no-op. No status write, no transition. Prints a JSON report on stdout.
set -euo pipefail

FEATURE_DIR="${1:-}"
PROPOSAL_DIR="${2:-}"
if [ -z "$FEATURE_DIR" ] || [ ! -d "$FEATURE_DIR" ] || [ -z "$PROPOSAL_DIR" ] || [ ! -d "$PROPOSAL_DIR" ]; then
  echo "usage: goalforge-respec-apply.sh <feature-dir> <proposal-dir>" >&2
  exit 1
fi

python3 - "$FEATURE_DIR" "$PROPOSAL_DIR" <<'PY'
import hashlib, json, os, re, sys, tempfile
from pathlib import Path

feature = Path(sys.argv[1]).resolve()
proposal = Path(sys.argv[2]).resolve()
SPEC = feature / "spec.md"
PROPOSED = proposal / "proposed-spec.md"
DIFF = proposal / "diff.json"
RAT = proposal / "RATIFIED"
FIELDS = ("date", "sha256", "diff_sha256", "base_sha256")


def refuse(msg):
    sys.stderr.write("goalforge-respec-apply: REFUSED — %s (no file written)\n" % msg)
    sys.exit(1)


def sha(p):
    return hashlib.sha256(p.read_bytes()).hexdigest()


def write_atomic(path, data):
    fd, tmp = tempfile.mkstemp(dir=str(path.parent), suffix=".tmp")
    try:
        with os.fdopen(fd, "wb") as f:
            f.write(data)
        os.replace(tmp, path)
    except Exception:
        try:
            os.unlink(tmp)
        except OSError:
            pass
        raise


def read_marker():
    if not RAT.is_file():
        refuse("no RATIFIED marker in %s (an unattended stage parks; only an attended yes writes it)" % proposal.name)
    lines = [l for l in RAT.read_text(encoding="utf-8").splitlines() if l.strip()]
    if len(lines) != 1 or not lines[0].startswith("ratified_by: human "):
        refuse("RATIFIED must be exactly one line starting 'ratified_by: human '")
    head = lines[0].split(" reply=", 1)[0]  # a verbatim reply can never inject a field
    fields = dict(re.findall(r"(?:^|\s)(date|sha256|diff_sha256|base_sha256)=(\S+)", head))
    for f in FIELDS:
        if f not in fields:
            refuse("RATIFIED is malformed: missing %s=" % f)
    if not re.fullmatch(r"\d{4}-\d{2}-\d{2}", fields["date"]):
        refuse("RATIFIED date= is not YYYY-MM-DD")
    return fields


for p in (SPEC, PROPOSED, DIFF):
    if not p.is_file():
        refuse("missing %s" % p)
m = re.fullmatch(r"\d{4}-\d{2}-\d{2}-([A-Za-z0-9._-]+)", proposal.name)
if not m or proposal.parent != feature / "respec":
    refuse("proposal dir must be <feature>/respec/<YYYY-MM-DD>-<slug>/")
SLUG = m.group(1)
REL = "respec/%s" % proposal.name

marker = read_marker()
DATE = marker["date"]
if sha(PROPOSED) != marker["sha256"]:
    refuse("RATIFIED sha256= does not match proposed-spec.md (edited after ratification)")
if sha(DIFF) != marker["diff_sha256"]:
    refuse("RATIFIED diff_sha256= does not match diff.json (stale or edited diff)")

current = sha(SPEC)
if current == marker["sha256"]:
    state = "applied"
elif current == marker["base_sha256"]:
    state = "unapplied"
else:
    refuse("spec.md is neither the ratified base (base_sha256=) nor the applied proposal (sha256=)")

try:
    diff = json.loads(DIFF.read_text(encoding="utf-8"))
except ValueError as e:
    refuse("diff.json is not valid JSON: %s" % e)
if not isinstance(diff, dict):
    refuse("diff.json must be a JSON object")


def changelog_rows(path, facet):
    n, inside = 0, False
    for ln in path.read_text(encoding="utf-8").splitlines():
        if ln.startswith("## "):
            inside = bool(re.match(r"^##\s+Goal Changelog\s*$", ln))
            continue
        if inside and re.match(r"^-\s+v\d+\s", ln) and re.search(r"\sfacet=%s\s" % re.escape(facet), ln):
            n += 1
    return n


if state == "unapplied":
    for facet in diff.get("goal_facets_changed") or []:
        if changelog_rows(PROPOSED, facet) <= changelog_rows(SPEC, facet):
            refuse("goal facet %s changed but proposed-spec.md adds no ## Goal Changelog row for it" % facet)

keys = set(diff.get("changed") or []) | set(diff.get("dropped") or [])


def frontmatter(text):
    lines = text.split("\n")
    if not lines or lines[0].strip() != "---":
        return None, {}
    for i in range(1, len(lines)):
        if lines[i].strip() == "---":
            fm = {}
            for ln in lines[1:i]:
                mm = re.match(r"^([A-Za-z0-9_-]+):\s*(.*)$", ln)
                if mm:
                    fm[mm.group(1)] = mm.group(2).strip()
            return i, fm
    return None, {}


def slice_ids(raw):
    return {x.strip().strip("'\"") for x in raw.strip().strip("[]").split(",") if x.strip()}


superseded, reharden, other = [], [], []
for ov in sorted(feature.glob("wp-*/overview.md")):
    wp = ov.parent
    text = ov.read_text(encoding="utf-8")
    end, fm = frontmatter(text)
    hit = sorted(keys & slice_ids(fm.get("contract_slice", "")), key=lambda k: int(k[1:]) if k[1:].isdigit() else 0)
    if end is None or not hit:
        continue
    status = fm.get("status", "").strip("'\"")
    if status == "verified":
        superseded.append(wp.name)
        lines = text.split("\n")
        if "superseded_by" not in fm:
            lines.insert(end, 'superseded_by: "%s"' % REL)
        note = "- date=%s respec=%s keys=%s" % (DATE, REL, ",".join(hit))
        if not any(l.startswith(note) for l in lines):
            body = "\n".join(lines).rstrip("\n")
            lines = (body + "\n\n## Supersession\n\n" + note
                     + " — superseded in place by the ratified spec revision; status and evidence kept"
                     + " (diff: %s/diff.json)\n" % REL).split("\n")
        new = "\n".join(lines)
        if new != text:
            write_atomic(ov, new.encode("utf-8"))
    elif status == "ready":
        reharden.append(wp.name)
        ev = wp / "reharden" / ("%s-respec-%s.md" % (DATE, SLUG))
        if not ev.exists():
            ev.parent.mkdir(exist_ok=True)
            write_atomic(ev, (
                "---\n"
                "name: %s-respec-%s\n" % (DATE, SLUG)
                + 'title: "ratified spec revision %s changes this WP\'s contract slice"\n' % REL
                + "kind: execution-learning\n"
                + "locator: %s/diff.json\n" % REL
                + "summary: ratified respec changed contract key(s) %s named by this WP's contract_slice\n" % ",".join(hit)
                + "plan: %s\n" % feature.name
                + "wp: %s\n" % wp.name
                + "created: %s\n" % DATE
                + "---\n\n"
                "<!-- Template: reharden-evidence v4 (frontmatter-first, flat layout) -->\n\n"
                "## Evidence\n\n"
                "Written by goalforge-respec-apply.sh from the human-ratified proposal `%s`.\n\n" % REL
                + "## Goal Impact\n\n"
                "Re-develop the goal facets that depend on %s at `hardened`: the next harden entry\n" % ",".join(hit)
                + "takes `ready -> hardened --mode evidence --evidence <this file>`.\n"
            ).encode("utf-8"))
    else:
        other.append(wp.name)

import subprocess
subprocess.run(["bash", os.environ["RESPEC_TRANSITION"], str(feature), "ready", "--from", "spec", "--mode", "human", "--reason", "respec applied"], check=False)
wrote_spec = False
if state == "unapplied":
    write_atomic(SPEC, PROPOSED.read_bytes())
    wrote_spec = True

print(json.dumps({
    "feature": feature.name,
    "proposal": REL,
    "state": state,
    "superseded": superseded,
    "reharden": reharden,
    "other_affected": other,
    "ambiguous": diff.get("ambiguous") or [],
    "spec_written": wrote_spec,
}))
PY
