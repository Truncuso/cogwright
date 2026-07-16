#!/usr/bin/env python3
"""Tests for goalforge-archive-sweep.py — pre/post-archive hygiene sweep.

Runs the sweep against a throwaway fixture tree (never the live plans root).
The sweep is READ-ONLY / propose-only: a fixture-tree hash before/after every
invocation asserts nothing was written.
"""
import hashlib
import json
import os
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

SWEEP = Path(__file__).resolve().parent.parent / "goalforge-archive-sweep.py"


def tree_digest(root: Path) -> str:
    h = hashlib.sha256()
    for p in sorted(root.rglob("*")):
        if p.is_file():
            h.update(str(p.relative_to(root)).encode())
            h.update(p.read_bytes())
    return h.hexdigest()


def write(p: Path, text: str) -> None:
    p.parent.mkdir(parents=True, exist_ok=True)
    p.write_text(text, encoding="utf-8")


class SweepFixture(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        root = Path(self.tmp.name)
        self.plans = root / "plans"
        self.docs = root / "docs"
        self.memory = root / ".memory"

        # The feature being archived, with one open blocker in findings.md
        write(self.plans / "feat-x/overview.md",
              "---\nname: feat-x\nstatus: completed\n---\n# feat-x\n")
        write(self.plans / "feat-x/wp-01/findings.md",
              "# Findings\n- [x] resolved item\n- [ ] OPEN: flaky eval on CI\n")

        # Ideas: one live referencing feat-x, one terminal referencing it, one unrelated
        write(self.plans / "ideas/live-idea.md",
              "---\nname: live-idea\nstatus: captured\n---\nBuilds on plans/feat-x/ output.\n")
        write(self.plans / "ideas/done-idea.md",
              "---\nname: done-idea\nstatus: promoted\n---\nPromoted from feat-x/ work.\n")
        write(self.plans / "ideas/other-idea.md",
              "---\nname: other-idea\nstatus: captured\n---\nNothing related here.\n")

        # Another feature with a hard locator ref into feat-x
        write(self.plans / "feat-y/overview.md",
              '---\nname: feat-y\nstatus: active\nlocator: "plans/feat-x/overview.md"\n---\n# feat-y\n')

        # Handoffs: one ready referencing feat-x, one ready unrelated, one archived referencing
        write(self.docs / "handoffs/some-thread/2026-07-10-handoff.md",
              "---\nslug: some-thread\nstatus: ready\n---\nDepends on feat-x/ outcome.\n")
        write(self.docs / "handoffs/other-thread/2026-07-11-handoff.md",
              "---\nslug: other-thread\nstatus: ready\n---\nUnrelated.\n")
        write(self.docs / "handoffs/_archived/old/2026-06-01-handoff.md",
              "---\nslug: old\nstatus: picked_up\n---\nfeat-x/ mention in archive.\n")

        # Memory: fact file + MEMORY.md pointer line
        write(self.memory / "project/handoff_feat-x.md",
              "---\nname: handoff_feat-x\ntype: project\n---\nfeat-x/ execution in flight.\n")
        write(self.memory / "MEMORY.md",
              "- [feat-x handoff](project/handoff_feat-x.md) — feat-x/ in flight\n"
              "- [unrelated](project/other.md) — nothing\n")

        self.root = root
        self.digest_before = tree_digest(root)

    def tearDown(self):
        self.tmp.cleanup()

    def run_sweep(self, *extra):
        return subprocess.run(
            [sys.executable, str(SWEEP), "feat-x",
             "--plans-root", str(self.plans),
             "--docs-root", str(self.docs),
             "--memory-root", str(self.memory),
             "--json", *extra],
            capture_output=True, text=True)

    def report(self, *extra):
        r = self.run_sweep(*extra)
        self.assertIn(r.returncode, (0, 2), r.stderr)
        return json.loads(r.stdout), r

    def test_read_only(self):
        self.report()
        self.assertEqual(self.digest_before, tree_digest(self.root),
                         "sweep must never write to the scanned tree")

    def test_ideas_split_live_vs_terminal(self):
        rep, _ = self.report()
        ideas = rep["categories"]["ideas"]
        names = {i["name"]: i for i in ideas}
        self.assertIn("live-idea", names)
        self.assertIn("done-idea", names)
        self.assertNotIn("other-idea", names)
        self.assertFalse(names["live-idea"]["terminal"])
        self.assertEqual(names["live-idea"]["action"], "triage")
        self.assertTrue(names["done-idea"]["terminal"])
        self.assertEqual(names["done-idea"]["action"], "idea-archive")

    def test_feature_refs_lists_owner(self):
        rep, _ = self.report()
        refs = rep["categories"]["feature_refs"]
        self.assertTrue(any(r["owner"] == "feat-y" for r in refs))
        # never lists the feature's own files
        self.assertFalse(any(r["owner"] == "feat-x" for r in refs))

    def test_handoffs_ready_only(self):
        rep, _ = self.report()
        hs = rep["categories"]["handoffs"]
        slugs = {h["slug"] for h in hs}
        self.assertEqual(slugs, {"some-thread"})  # archived + unrelated excluded

    def test_memory_facts_and_pointers(self):
        rep, _ = self.report()
        mem = rep["categories"]["memory"]
        kinds = {m["kind"] for m in mem}
        self.assertIn("fact", kinds)
        self.assertIn("pointer", kinds)
        # pointer entries carry the MEMORY.md line number for a propose-only diff
        self.assertTrue(all("line" in m for m in mem if m["kind"] == "pointer"))

    def test_findings_open_items(self):
        rep, _ = self.report()
        open_items = rep["categories"]["findings_open"]
        self.assertEqual(len(open_items), 1)
        self.assertIn("flaky eval", open_items[0]["text"])

    def test_gate_exit_code(self):
        _, r = self.report("--gate")
        self.assertEqual(r.returncode, 2,
                         "--gate must exit 2 when open findings/blockers exist")

    def test_gate_clean_feature(self):
        # remove the open item -> gate passes
        f = self.plans / "feat-x/wp-01/findings.md"
        f.write_text("# Findings\n- [x] resolved item\n", encoding="utf-8")
        rep, r = self.report("--gate")
        self.assertEqual(rep["categories"]["findings_open"], [])
        self.assertEqual(r.returncode, 0)

    def test_summary_counts(self):
        rep, _ = self.report()
        s = rep["summary"]
        for k in ("ideas", "feature_refs", "handoffs", "memory", "findings_open"):
            self.assertEqual(s[k], len(rep["categories"][k]))


if __name__ == "__main__":
    unittest.main(verbosity=2)
