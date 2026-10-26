"""Compile extracted MQL cash functions against explicit host mocks, not MetaEditor.

The broker mock rounds total cash P/L to pennies at a fixed conversion rate.
It demonstrates a possible numerical failure; it does not reproduce broker fills.
"""
import pathlib
import re
import shutil
import subprocess
import tempfile
import unittest
import zipfile

ROOT = pathlib.Path(__file__).resolve().parents[1]


def function(source, name):
    match = re.search(r"^(?:bool|double) " + re.escape(name) + r"\(", source, re.MULTILINE)
    if match is None:
        raise ValueError("function absent: " + name)
    opening = source.index("{", match.start())
    depth = 1
    cursor = opening + 1
    while depth:
        depth += (source[cursor] == "{") - (source[cursor] == "}")
        cursor += 1
    return source[match.start():cursor] + "\n"


@unittest.skipUnless(shutil.which("g++"), "g++ needed for extracted-function host tests")
class CashSearch(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        # The committed archive pins the original candidate even on fresh
        # checkouts that do not retain its extracted source directory.
        with zipfile.ZipFile(ROOT / "downloads/MarvGoldScalper_V061_Research_Candidate.zip") as archive:
            original = archive.read("MarvGoldScalper_V061/source/MarvGoldScalper_V061.mq5").decode("utf-8-sig")
        revised = (ROOT / "source/MarvGoldScalper_V062_CashFix.mq5").read_text()
        estimate = function(original, "EstimateNetExit")
        if estimate != function(revised, "EstimateNetExit"):
            raise AssertionError("valuation changed: fixtures must separately extract both versions")
        cls.folder = tempfile.TemporaryDirectory()
        cls.addClassCleanup(cls.folder.cleanup)
        directory = pathlib.Path(cls.folder.name)
        extracted = "\n".join([
            estimate,
            function(original, "CashStopPrice").replace("CashStopPrice(", "OldCashStopPrice(", 1),
            function(original, "BreakevenPrice").replace("BreakevenPrice(", "OldBreakevenPrice(", 1),
            function(revised, "FindNetStop"),
            function(revised, "CashStopPrice"),
            function(revised, "BreakevenPrice"),
        ])
        (directory / "cash_functions_extracted.inc").write_text(extracted)
        cls.binary = directory / "cash-search-test"
        compiled = subprocess.run([
            "g++", "-std=c++17", "-Wall", "-Wextra", "-Werror", "-pedantic",
            "-I", str(directory), "-I", str(ROOT / "source"),
            str(ROOT / "tests/cash_search_test.cpp"), "-o", str(cls.binary),
        ], capture_output=True, text=True)
        if compiled.returncode:
            raise AssertionError(compiled.stderr)

    def scenario(self, name):
        result = subprocess.run([str(self.binary), name], capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("cash-search host assertions passed", result.stdout)

    def test_archived_rounding_defects_and_repaired_targets(self):
        self.scenario("old")

    def test_long_short_minimal_tick_grid_targets(self):
        self.scenario("targets")

    def test_zero_rounded_single_tick_still_reaches_cash_target(self):
        self.scenario("zero_tick")

    def test_broker_and_final_revalidation_failures(self):
        self.scenario("failures")

    def test_nonfinite_and_invalid_inputs(self):
        self.scenario("invalid")

    def test_unreachable_and_short_positive_price_bounds(self):
        self.scenario("bounded")

    def test_zero_positive_and_negative_swap(self):
        self.scenario("swaps")

    def test_breakeven_covers_costs_slippage_and_extra_ticks(self):
        self.scenario("breakeven")

    def test_actual_shared_helper_minimality_and_observation_budget(self):
        self.scenario("helper")


if __name__ == "__main__":
    unittest.main()
