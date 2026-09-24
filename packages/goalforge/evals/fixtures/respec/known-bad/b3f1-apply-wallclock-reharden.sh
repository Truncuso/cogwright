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
# `## Goal Changelog` row in proposed-spec.md, and — under flock on
# <feature>/.sdd-transitions.lock, in a read-only pre-pass before the first
# write — when any WP's contract_slice does not parse into C<n> ids, or when a
# WP at hardened|executing|implemented names a changed, dropped or
# ambiguous[].dropped key (in flight: walk it back to `ready` first).
#
# Steps (base state only), each skip-if-present so a partial apply resumes:
#   1. supersede in place each `verified` WP whose contract_slice names a
#      changed/dropped key (superseded_by: <latest proposal> + one dated note
#      per proposal under a single ## Supersession section)
#   2. write <wp>/reharden/<date>-respec-<slug>.md for each such `ready` WP
#   3. copy proposed-spec.md over spec.md byte for byte
# Every date written is RATIFIED date=, never the wall clock. `ambiguous` keys
# are reported, never acted on. On the applied state the WP steps are skipped
# entirely: a rerun is an exit-0 no-op that writes nothing. No status write, no
# transition. Prints a JSON report on stdout.
set -euo pipefail

FEATURE_DIR="${1:-}"
PROPOSAL_DIR="${2:-}"
if [ -z "$FEATURE_DIR" ] || [ ! -d "$FEATURE_DIR" ] || [ -z "$PROPOSAL_DIR" ] || [ ! -d "$PROPOSAL_DIR" ]; then
  echo "usage: goalforge-respec-apply.sh <feature-dir> <proposal-dir>" >&2
  exit 1
fi

python3 - "$FEATURE_DIR" "$PROPOSAL_DIR" <<'PY'
import fcntl, hashlib, json, os, re, sys, tempfile
from pathlib import Path

feature = Path(sys.argv[1]).resolve()
proposal = Path(sys.argv[2]).resolve()
SPEC = feature / "spec.md"
PROPOSED = proposal / "proposed-spec.md"
DIFF = proposal / "diff.json"
RAT = proposal / "RATIFIED"
LOCK = feature / ".sdd-transitions.lock"
FIELDS = ("date", "sha256", "diff_sha256", "base_sha256")
IN_FLIGHT = ("hardened", "executing", "implemented")


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
# A renumber (ambiguous pair) is never acted on, but its dropped id still
# counts as affected for the in-flight refusal (fail-closed).
flight_keys = keys | {a.get("dropped") for a in (diff.get("ambiguous") or []) if isinstance(a, dict)}


def frontmatter(text):
    """(closing-line index, {key: raw value}, frontmatter lines) or (None, {}, [])."""
    lines = text.split("\n")
    if not lines or lines[0].strip() != "---":
        return None, {}, []
    for i in range(1, len(lines)):
        if lines[i].strip() == "---":
            fm = {}
            for ln in lines[1:i]:
                mm = re.match(r"^([A-Za-z0-9_-]+):\s*(.*)$", ln)
                if mm:
                    fm[mm.group(1)] = mm.group(2).strip()
            return i, fm, lines[1:i]
    return None, {}, []


def uncomment(s):
    return re.sub(r"\s+#.*$", "", s).strip()


def unquote(s):
    return s[1:-1].strip() if len(s) >= 2 and s[0] == s[-1] and s[0] in "'\"" else s


def slice_ids(fm_lines):
    """contract_slice as a set of C<n> ids; None when it does not parse fully.

    Accepts a YAML flow list ([C2, 'C3']) or a block list (`contract_slice:`
    then `- C<n>` lines at any indent, zero included); items may be quoted and
    carry a trailing ` # comment`. An absent key is the empty slice.
    """
    for i, ln in enumerate(fm_lines):
        mm = re.match(r"^contract_slice:(.*)$", ln)
        if not mm:
            continue
        raw = uncomment(mm.group(1))
        if raw.startswith("["):
            if not raw.endswith("]"):
                return None
            items = [x.strip() for x in raw[1:-1].split(",")]
            if items == [""]:
                items = []
        elif raw == "":
            items = []
            for c in fm_lines[i + 1:]:
                if c and c[0] not in " \t-":
                    break  # the next top-level key ends the block list
                if not c.strip():
                    continue
                item = re.match(r"^\s*-\s+(.*)$", c)
                if not item:
                    return None
                items.append(uncomment(item.group(1)))
        else:
            return None
        ids = set()
        for it in items:
            it = unquote(it)
            if not re.fullmatch(r"C\d+", it):
                return None
            ids.add(it)
        return ids
    return set()


def c_order(k):
    return int(k[1:])


def in_flight(status, ids):
    return status in IN_FLIGHT and ids & flight_keys


def wp_plan():
    """Read-only pre-pass over every WP: refuses before the first write, else
    returns (overview, text, fm-end, fm, status, ids, hit) per WP whose slice
    names a changed or dropped key."""
    plan, problems = [], []
    for ov in sorted(feature.glob("wp-*/overview.md")):
        wp = ov.parent
        text = ov.read_text(encoding="utf-8")
        end, fm, fm_lines = frontmatter(text)
        if end is None:
            continue
        ids = slice_ids(fm_lines)
        if ids is None:
            problems.append("%s: contract_slice does not parse into C<n> ids (fail-closed)" % wp.name)
            continue
        status = fm.get("status", "").strip("'\"")
        if in_flight(status, ids):
            problems.append("%s is in flight at %s and names %s: walk it back to `ready` first "
                            "(goalforge-transition.sh %s ready --reason \"<respec>\"), then rerun, "
                            "and the reharden step writes its evidence file"
                            % (wp.name, status, ",".join(sorted(ids & flight_keys, key=c_order)), wp.name))
            continue
        hit = sorted(keys & ids, key=c_order)
        if hit:
            plan.append((ov, text, end, fm, status, ids, hit))
    if problems:
        refuse("; ".join(problems))
    return plan


superseded, reharden, other = [], [], []
lock_fd = None
if state == "unapplied":
    # Held through the last write: no status write by goalforge-transition.sh
    # lands between the pre-pass and the writes, and no supersede write
    # reverts a concurrent status write.
    lock_fd = os.open(str(LOCK), os.O_WRONLY | os.O_CREAT | os.O_APPEND, 0o644)
    fcntl.flock(lock_fd, fcntl.LOCK_EX)
    plan = wp_plan()
else:
    plan = []  # applied: the spec copy is the last step, so the WP steps already ran

for ov, text, end, fm, status, ids, hit in plan:
    wp = ov.parent
    if status == "verified":
        superseded.append(wp.name)
        lines = text.split("\n")
        by = 'superseded_by: "%s"' % REL
        if "superseded_by" not in fm:
            lines.insert(end, by)
        else:
            for j in range(1, end):
                if re.match(r"^superseded_by:", lines[j]):
                    lines[j] = by
                    break
        note = "- date=%s respec=%s keys=%s" % (DATE, REL, ",".join(hit))
        if not any(l.startswith(note) for l in lines):
            full = (note + " — superseded in place by the ratified spec revision; status and evidence kept"
                    + " (diff: %s/diff.json)" % REL)
            heads = [j for j, l in enumerate(lines) if re.match(r"^##\s+Supersession\s*$", l)]
            if heads:
                # one section, one note per proposal: append after its last non-blank line
                nxt = next((j for j in range(heads[0] + 1, len(lines)) if lines[j].startswith("## ")), len(lines))
                last = max(j for j in range(heads[0], nxt) if lines[j].strip())
                lines.insert(last + 1, full)
            else:
                body = "\n".join(lines).rstrip("\n")
                lines = (body + "\n\n## Supersession\n\n" + full + "\n").split("\n")
        new = "\n".join(lines)
        if new != text:
            write_atomic(ov, new.encode("utf-8"))
    elif status == "ready":
        reharden.append(wp.name)
        ev = wp / "reharden" / ("%s-respec-%s.md" % (__import__("datetime").date.today().isoformat(), SLUG))
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

if state == "unapplied":
    write_atomic(SPEC, PROPOSED.read_bytes())
if lock_fd is not None:
    os.close(lock_fd)

print(json.dumps({
    "feature": feature.name,
    "proposal": REL,
    "state": state,
    "wp_steps": "run" if state == "unapplied" else "skipped",
    "superseded": superseded,
    "reharden": reharden,
    "other_affected": other,
    "ambiguous": diff.get("ambiguous") or [],
    "spec_written": state == "unapplied",
}))
PY
