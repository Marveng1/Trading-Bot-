"""Host-compile the actual exporter bar validator; no MetaEditor or CSV API mock.

These synthetic cases test acceptance/rejection of bar records, not broker
history completeness, native file export, account specifications or tick quality.
"""
import pathlib
import re
import shutil
import subprocess
import tempfile
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[1]


def extract_bar_validator(source):
    match = re.search(r"^bool IsValidResearchBar\(", source, re.MULTILINE)
    if match is None:
        raise ValueError("exporter IsValidResearchBar definition is absent")
    opening = source.index("{", match.start())
    cursor, depth = opening + 1, 1
    while depth:
        depth += (source[cursor] == "{") - (source[cursor] == "}")
        cursor += 1
    return source[match.start():cursor]


STUB = r'''
#include <algorithm>
#include <cmath>
#include <iostream>
#include <limits>
#include <stdexcept>
#include <string>
using datetime=long;
struct MqlRates {
    datetime time;
    double open, high, low, close;
    long tick_volume;
    int spread;
    long real_volume;
};
bool MathIsValidNumber(double value) { return std::isfinite(value); }
double MathMax(double a,double b) { return std::max(a,b); }
double MathMin(double a,double b) { return std::min(a,b); }
'''

SCENARIOS = r'''
void check(bool accepted,const char* message) {
    if(!accepted) throw std::runtime_error(message);
}
MqlRates valid(datetime time=100) {
    return {time,100,102,99,101,25,15,0};
}
int main(int argc,char** argv) {
    try {
        const std::string scenario=argc==2?argv[1]:"";
        if(scenario=="boundaries") {
            MqlRates bar=valid(100);
            check(IsValidResearchBar(bar,100,200,99),"from is inclusive");
            bar.time=199;
            check(IsValidResearchBar(bar,100,200,100),"last timestamp before to accepted");
            bar.time=200;
            check(!IsValidResearchBar(bar,100,200,100),"to is exclusive");
            bar.time=99;
            check(!IsValidResearchBar(bar,100,200,0),"before from rejected");
            bar.time=201;
            check(!IsValidResearchBar(bar,100,200,100),"after to rejected");
        } else if(scenario=="order") {
            MqlRates bar=valid(100);
            check(IsValidResearchBar(bar,100,200,0),"first bar without predecessor accepted");
            check(!IsValidResearchBar(bar,100,200,100),"duplicate timestamp rejected");
            check(!IsValidResearchBar(bar,100,200,101),"out-of-order bar rejected");
            check(IsValidResearchBar(bar,100,200,99),"strictly increasing bar accepted");
        } else if(scenario=="ohlc") {
            MqlRates flat=valid();
            flat.open=flat.high=flat.low=flat.close=100;
            check(IsValidResearchBar(flat,100,200,0),"flat positive OHLC accepted");
            MqlRates bearish=valid(); bearish.open=101; bearish.close=100;
            check(IsValidResearchBar(bearish,100,200,0),"bearish OHLC accepted");
            MqlRates bar=valid(); bar.high=100;
            check(!IsValidResearchBar(bar,100,200,0),"high below close rejected");
            bar=valid(); bar.high=99.5;
            check(!IsValidResearchBar(bar,100,200,0),"high below open rejected");
            bar=valid(); bar.low=100.5;
            check(!IsValidResearchBar(bar,100,200,0),"low above open rejected");
            bar=valid(); bar.low=101.5;
            check(!IsValidResearchBar(bar,100,200,0),"low above close rejected");
            bar=valid(); bar.high=98; bar.low=103;
            check(!IsValidResearchBar(bar,100,200,0),"inverted range rejected");
        } else if(scenario=="nonpositive") {
            for(int field=0;field<4;field++) {
                for(double bad:{0.0,-1.0}) {
                    MqlRates bar=valid();
                    double* values[]={&bar.open,&bar.high,&bar.low,&bar.close};
                    *values[field]=bad;
                    check(!IsValidResearchBar(bar,100,200,0),"nonpositive price rejected");
                }
            }
        } else if(scenario=="nonfinite") {
            for(int field=0;field<4;field++) {
                for(double bad:{std::numeric_limits<double>::quiet_NaN(),
                                std::numeric_limits<double>::infinity(),
                                -std::numeric_limits<double>::infinity()}) {
                    MqlRates bar=valid();
                    double* values[]={&bar.open,&bar.high,&bar.low,&bar.close};
                    *values[field]=bad;
                    check(!IsValidResearchBar(bar,100,200,0),"nonfinite price rejected");
                }
            }
        } else if(scenario=="metadata") {
            MqlRates bar=valid(); bar.tick_volume=-1;
            check(!IsValidResearchBar(bar,100,200,0),"negative tick volume rejected");
            bar=valid(); bar.real_volume=-1;
            check(!IsValidResearchBar(bar,100,200,0),"negative real volume rejected");
            bar=valid(); bar.spread=-1;
            check(!IsValidResearchBar(bar,100,200,0),"negative spread rejected");
        } else throw std::runtime_error("unknown scenario");
        std::cout<<scenario<<": actual exporter validator host checks passed\n";
    } catch(const std::exception& error) {
        std::cerr<<error.what()<<"\n";
        return 1;
    }
}
'''


@unittest.skipUnless(shutil.which("g++"), "g++ needed for exported-function host checks")
class ResearchBarValidation(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        source = (ROOT / "tools/MGS_ExportResearchData.mq5").read_text()
        cls.folder = tempfile.TemporaryDirectory()
        cls.addClassCleanup(cls.folder.cleanup)
        directory = pathlib.Path(cls.folder.name)
        cpp = directory / "research-validator.cpp"
        cpp.write_text(STUB + extract_bar_validator(source) + SCENARIOS)
        cls.binary = directory / "research-validator"
        result = subprocess.run([
            "g++", "-std=c++17", "-Wall", "-Wextra", "-Werror", "-pedantic",
            str(cpp), "-o", str(cls.binary),
        ], capture_output=True, text=True)
        if result.returncode:
            raise AssertionError(result.stderr)

    def scenario(self, name):
        result = subprocess.run([str(self.binary), name], capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("actual exporter validator host checks passed", result.stdout)

    def test_date_interval_from_inclusive_to_exclusive(self):
        self.scenario("boundaries")

    def test_duplicates_and_out_of_order_bars(self):
        self.scenario("order")

    def test_ohlc_range_consistency_accepts_bull_bear_and_flat_bars(self):
        self.scenario("ohlc")

    def test_every_price_field_must_be_positive(self):
        self.scenario("nonpositive")

    def test_every_price_field_must_be_finite(self):
        self.scenario("nonfinite")

    def test_negative_volume_and_spread_metadata_rejected(self):
        self.scenario("metadata")


if __name__ == "__main__":
    unittest.main()
