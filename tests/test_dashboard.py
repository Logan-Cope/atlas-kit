"""Tests for bin/build-dashboard.py."""

import importlib.util
import json
import pathlib
import subprocess
import sys
import tempfile
import unittest

ROOT = pathlib.Path(__file__).resolve().parent.parent
SCRIPT = ROOT / "bin" / "build-dashboard.py"
EXAMPLE = ROOT / "examples" / "state"

spec = importlib.util.spec_from_file_location("build_dashboard", SCRIPT)
dash = importlib.util.module_from_spec(spec)
spec.loader.exec_module(dash)


class ExampleState(unittest.TestCase):
    def setUp(self):
        self.data = dash.load_state(EXAMPLE)
        self.page = dash.render(self.data, note="Example state")

    def test_counts_every_status(self):
        for label, n in [("Blocked", 1), ("In progress", 3), ("Backlog", 2), ("Done", 2)]:
            self.assertIn(f'<span class="n">{n}</span> {label}', self.page)

    def test_parses_the_fleet_ledger(self):
        batch = self.data["fleet"][0]
        self.assertEqual(batch["batch"], "2026-11-14-docs-sprint")
        self.assertEqual([t["task"] for t in batch["tasks"]],
                         ["pantry-readme", "trailmap-readme", "field-notes-readme"])
        self.assertEqual(batch["tasks"][0]["status"], "done (verified)")
        self.assertIn("3 tasks · 2 running", self.page)
        self.assertIn('class="pill pill-done-verified"', self.page)

    def test_shows_latest_wraps_first(self):
        first = self.page.index("Docs sprint: pantry README")
        older = self.page.index("Elevation profile under each route")
        self.assertLess(first, older)

    def test_blocker_and_decision_reasons_render(self):
        self.assertIn("No public sample file from the third exporter", self.page)
        self.assertIn("Why: A parser written from a forum description", self.page)

    def test_no_script_and_no_em_dash(self):
        self.assertNotIn("<script", self.page)
        self.assertNotIn("\u2014", self.page)


class Hostile(unittest.TestCase):
    def test_state_text_is_escaped(self):
        with tempfile.TemporaryDirectory() as d:
            state = pathlib.Path(d)
            (state / "missions.json").write_text(json.dumps({"missions": [{
                "id": "x", "title": "<script>alert(1)</script>", "project": "<b>p</b>",
                "status": "in_progress", "next_action": '" onmouseover="x', "blocker": None,
                "updated": "2026-11-14"}]}))
            (state / "worklog.jsonl").write_text(
                '{"ts":"2026-11-14T10:00:00","project":"p","summary":"<img src=x onerror=1>"}\n'
                "not json at all\n")
            page = dash.render(dash.load_state(state))
        self.assertNotIn("<script>alert", page)
        self.assertIn("&lt;script&gt;alert(1)&lt;/script&gt;", page)
        self.assertNotIn("<img src=x", page)
        self.assertIn("&quot; onmouseover=&quot;x", page)

    def test_bad_bytes_and_bad_ledger_do_not_abort(self):
        with tempfile.TemporaryDirectory() as d:
            state = pathlib.Path(d)
            (state / "worklog.jsonl").write_bytes(
                b'{"ts":"2026-11-14T10:00:00","project":"p","summary":"caf\xe9 ok"}\n'
                b'{"ts":"2026-11-14T11:00:00","project":"p","summary":"second"}\n')
            (state / "fleet").mkdir()
            (state / "fleet" / "b.md").write_bytes(b"| Task | Status |\n|---|---|\n| t\xff | running |\n")
            page = dash.render(dash.load_state(state))
        self.assertIn("second", page)
        self.assertIn("b", page)

    def test_empty_state_renders(self):
        with tempfile.TemporaryDirectory() as d:
            page = dash.render(dash.load_state(pathlib.Path(d)))
        self.assertIn("No fleet batches yet.", page)
        self.assertIn("No wraps yet.", page)
        self.assertIn('<span class="n">0</span> Blocked', page)


class Cli(unittest.TestCase):
    def test_writes_reproducible_output(self):
        with tempfile.TemporaryDirectory() as d:
            out = pathlib.Path(d) / "site" / "index.html"
            args = [sys.executable, str(SCRIPT), "--state", str(EXAMPLE), "--out", str(out), "--no-timestamp"]
            subprocess.run(args, check=True, capture_output=True)
            first = out.read_text()
            subprocess.run(args, check=True, capture_output=True)
            self.assertEqual(first, out.read_text())
            self.assertNotIn("Generated", first)


if __name__ == "__main__":
    unittest.main()
