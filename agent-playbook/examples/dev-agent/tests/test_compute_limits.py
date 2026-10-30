#!/usr/bin/env python3
"""Tests for acceptance/compute-limits.py. Run: python3 tests/test_compute_limits.py
All figures below are SYNTHETIC and exist only to test the arithmetic. They are not real results."""
import json
import shutil
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SCRIPT = ROOT / "acceptance" / "compute-limits.py"
TEMPLATE = ROOT / "acceptance" / "limits-input-template.json"
ROLES = ["researcher", "designer", "builder", "reviewer"]


def run_entry(brief, passed=True, cost=3.0, minutes=90, interventions=1, turns=None, hit_cap=None):
    entry = {"brief": brief, "passed": passed}
    if passed:
        entry.update(cost=cost, minutes=minutes, interventions=interventions,
                     turns=turns or {"researcher": 10, "designer": 8, "builder": 40, "reviewer": 6},
                     hit_cap=hit_cap or [])
    return entry


class Base(unittest.TestCase):
    def setUp(self):
        self.tmp = Path(tempfile.mkdtemp())
        self.agents = self.tmp / "agents"
        shutil.copytree(ROOT / ".claude" / "agents", self.agents)
        self.record = self.tmp / "record.md"

    def tearDown(self):
        shutil.rmtree(self.tmp, ignore_errors=True)

    def write(self, runs):
        p = self.tmp / "results.json"
        p.write_text(json.dumps({"runs": runs}))
        return p

    def run_script(self, path, *extra):
        return subprocess.run(
            [sys.executable, str(SCRIPT), str(path), "--agents-dir", str(self.agents), "--record", str(self.record), *extra],
            capture_output=True, text=True)

    def snapshot(self):
        return {p.name: p.read_text() for p in self.agents.glob("*.md")}


class TestArithmetic(Base):
    def test_turns_are_1_5x_highest_rounded_up(self):
        r1 = run_entry("01", turns={"researcher": 10, "designer": 7, "builder": 41, "reviewer": 6})
        r2 = run_entry("02", turns={"researcher": 14, "designer": 9, "builder": 52, "reviewer": 9})
        out = self.run_script(self.write([r1, r2]))
        self.assertEqual(out.returncode, 0, out.stderr)
        # 1.5 x 14 = 21, 1.5 x 9 = 13.5 -> 14, 1.5 x 52 = 78, 1.5 x 9 = 13.5 -> 14
        for line in ("researcher", "designer", "builder", "reviewer"):
            self.assertIn(line, out.stdout)
        self.assertRegex(out.stdout, r"researcher\s+\d+\s+21\b")
        self.assertRegex(out.stdout, r"designer\s+\d+\s+14\b")
        self.assertRegex(out.stdout, r"builder\s+\d+\s+78\b")
        self.assertRegex(out.stdout, r"reviewer\s+\d+\s+14\b")

    def test_cost_cap_is_2x_median_of_two(self):
        out = self.run_script(self.write([run_entry("01", cost=2.0), run_entry("02", cost=6.0)]))
        self.assertIn("8.00", out.stdout)  # median of 2 and 6 is 4, x2 = 8

    def test_time_target_kept_when_all_runs_within_two_hours(self):
        out = self.run_script(self.write([run_entry("01", minutes=100), run_entry("02", minutes=120)]))
        self.assertIn("120 minutes", out.stdout)
        self.assertIn("target stands", out.stdout)

    def test_time_target_uses_measured_figure_when_slower(self):
        out = self.run_script(self.write([run_entry("01", minutes=100), run_entry("02", minutes=151)]))
        self.assertIn("165 minutes", out.stdout)  # 151 rounded up to next 15
        self.assertIn("NOT supported", out.stdout)

    def test_intervention_warning(self):
        out = self.run_script(self.write([run_entry("01", interventions=1), run_entry("02", interventions=3)]))
        self.assertIn("WARNING", out.stdout)
        self.assertIn("02", out.stdout.split("WARNING")[1])


class TestTrustworthiness(Base):
    def test_needs_two_successful_runs(self):
        out = self.run_script(self.write([run_entry("01"), run_entry("02", passed=False)]))
        self.assertEqual(out.returncode, 2)
        self.assertIn("at least 2 successful", out.stderr)

    def test_failed_run_is_excluded_not_averaged_in(self):
        runs = [run_entry("01", cost=2.0), run_entry("02", cost=6.0), run_entry("03", passed=False)]
        out = self.run_script(self.write(runs))
        self.assertEqual(out.returncode, 0, out.stderr)
        self.assertIn("Excluded failed runs: 03", out.stdout)
        self.assertIn("8.00", out.stdout)

    def test_hit_cap_flagged_as_lower_bound(self):
        out = self.run_script(self.write([run_entry("01", hit_cap=["builder"]), run_entry("02")]))
        self.assertEqual(out.returncode, 0)
        self.assertIn("LOWER BOUND", out.stdout)
        self.assertIn("NOT SAFE TO APPLY", out.stdout)

    def test_apply_refused_when_a_role_hit_its_cap(self):
        before = self.snapshot()
        out = self.run_script(self.write([run_entry("01", hit_cap=["builder"]), run_entry("02")]), "--apply")
        self.assertEqual(out.returncode, 2)
        self.assertEqual(before, self.snapshot(), "agent files must be untouched")
        self.assertFalse(self.record.exists())


class TestInputValidation(Base):
    def test_blank_template_is_rejected(self):
        out = self.run_script(TEMPLATE)
        self.assertEqual(out.returncode, 1)
        self.assertIn("passed", out.stderr)

    def test_null_field_in_passed_run_is_rejected(self):
        r = run_entry("01")
        r["cost"] = None
        out = self.run_script(self.write([r, run_entry("02")]))
        self.assertEqual(out.returncode, 1)
        self.assertIn("cost", out.stderr)

    def test_missing_role_turns_rejected(self):
        r = run_entry("01")
        del r["turns"]["builder"]
        out = self.run_script(self.write([r, run_entry("02")]))
        self.assertEqual(out.returncode, 1)
        self.assertIn("builder", out.stderr)

    def test_zero_or_negative_numbers_rejected(self):
        out = self.run_script(self.write([run_entry("01", cost=0), run_entry("02")]))
        self.assertEqual(out.returncode, 1)

    def test_bad_hit_cap_role_rejected(self):
        out = self.run_script(self.write([run_entry("01", hit_cap=["lead"]), run_entry("02")]))
        self.assertEqual(out.returncode, 1)

    def test_missing_file_and_bad_json(self):
        self.assertEqual(self.run_script(self.tmp / "nope.json").returncode, 1)
        bad = self.tmp / "bad.json"
        bad.write_text("{not json")
        self.assertEqual(self.run_script(bad).returncode, 1)


class TestApply(Base):
    def test_report_only_changes_nothing(self):
        before = self.snapshot()
        out = self.run_script(self.write([run_entry("01"), run_entry("02")]))
        self.assertEqual(out.returncode, 0)
        self.assertEqual(before, self.snapshot())
        self.assertFalse(self.record.exists())
        self.assertIn("nothing was changed", out.stdout)

    def test_apply_writes_only_maxturns_and_a_record(self):
        before = self.snapshot()
        r1 = run_entry("01", turns={"researcher": 10, "designer": 8, "builder": 40, "reviewer": 6})
        r2 = run_entry("02", turns={"researcher": 12, "designer": 9, "builder": 50, "reviewer": 8})
        out = self.run_script(self.write([r1, r2]), "--apply")
        self.assertEqual(out.returncode, 0, out.stderr)
        expected = {"researcher": 18, "designer": 14, "builder": 75, "reviewer": 12}
        after = self.snapshot()
        for role, value in expected.items():
            old, new = before[f"{role}.md"], after[f"{role}.md"]
            self.assertIn(f"maxTurns: {value}", new)
            # everything except the maxTurns line must be byte-identical
            strip = lambda t: "\n".join(l for l in t.splitlines() if not l.startswith("maxTurns:"))
            self.assertEqual(strip(old), strip(new), f"{role}.md changed beyond maxTurns")
        record = self.record.read_text()
        self.assertIn("builder | 75", record)
        self.assertIn("01, 02", record)

    def test_apply_is_all_or_nothing_if_an_agent_file_lacks_maxturns(self):
        p = self.agents / "reviewer.md"
        p.write_text(p.read_text().replace("maxTurns: 20\n", ""))
        before = self.snapshot()
        out = self.run_script(self.write([run_entry("01"), run_entry("02")]), "--apply")
        self.assertEqual(out.returncode, 1)
        self.assertEqual(before, self.snapshot(), "no file may be modified when any file is invalid")

    def test_real_agent_files_all_have_maxturns(self):
        for role in ROLES:
            text = (ROOT / ".claude" / "agents" / f"{role}.md").read_text()
            self.assertRegex(text, r"(?m)^maxTurns:\s*\d+\s*$", f"{role}.md needs a maxTurns line")


if __name__ == "__main__":
    unittest.main(verbosity=1)
