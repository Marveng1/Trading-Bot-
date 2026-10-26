#!/usr/bin/env python3
"""Package the V062 cash-pricing repair as a single-file MT5 research candidate."""
from pathlib import Path
import hashlib
import json
import re
import zipfile

ROOT = Path(__file__).resolve().parents[1]
NAME = "MarvGoldScalper_V062_CashFix_Standalone"


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def build():
    source_path = ROOT / "source/MarvGoldScalper_V062_CashFix.mq5"
    source = source_path.read_text()
    flattened = source
    hashes = {source_path.name: sha(source_path)}
    for name in ("MGSCore.mqh", "MGSCashSearch.mqh"):
        marker = f'#include "{name}"'
        if flattened.count(marker) != 1:
            raise RuntimeError(f"Unexpected include count for {name}")
        header = ROOT / "source" / name
        flattened = flattened.replace(marker, header.read_text())
        hashes[name] = sha(header)
    if re.search(r'^\s*#include\s+"', flattened, re.M):
        raise RuntimeError("A custom include remains unexpanded")
    if flattened.count("void OnTick()") != 1:
        raise RuntimeError("Unexpected EA callbacks")
    prefix = ("// SINGLE-FILE V062 CASHFIX RESEARCH CANDIDATE. DEMO ONLY.\n"
              "// Supporting policy/search code embedded. MT5 compilation UNVERIFIED.\n")
    target = ROOT / "downloads" / (NAME + ".mq5")
    target.write_text(prefix + flattened, encoding="utf-8")
    hashes[target.name] = sha(target)
    enums = dict(re.findall(r"^\s*(MGS_\w+)\s*=\s*(\d+)", source, re.M))
    defaults = {}
    for name, value in re.findall(r"^input\s+\w+\s+(\w+)\s*=\s*([^;]+);", source, re.M):
        value = value.strip()
        defaults[name] = enums.get(value, value.strip('"'))
    if len(defaults) != len(re.findall(r"^input\s", source, re.M)) or len(defaults) < 60:
        raise RuntimeError("Incomplete input discovery")
    files = [target]
    for exit_mode, label in ((0, "Legacy"), (3, "Hybrid")):
        values = dict(defaults, InpMode="0", InpExitMode=str(exit_mode),
                      InpEnableDemoOrders="true", InpMaxHoldingSeconds="0",
                      InpUseFixedTP="false", InpCSVLog="true")
        preset = ROOT / "downloads" / f"DEMO_TESTER_V062_EMA_{label}.set"
        text = ("; V062 CASHFIX DEMO/TESTER ONLY. Orders enabled. Not MT5-tested.\r\n"
                "; Set GOLD/M1, GBP1000, 12-16Oct2026, real ticks, optimization OFF separately.\r\n"
                f"; Standalone SHA256 {hashes[target.name]}\r\n")
        text += "".join(f"{key}={value}\r\n" for key, value in values.items())
        preset.write_bytes(text.encode("utf-16"))
        files.append(preset)
        hashes[preset.name] = sha(preset)
    manifest = ROOT / "downloads" / "V062_CashFix_manifest.json"
    manifest.write_text(json.dumps({
        "build": "1.062 CASHFIX research candidate",
        "mt5_compilation": "not_run_here",
        "mt5_backtest": "not_run_for_this_build",
        "performance_claim": None,
        "hashes": hashes,
    }, indent=2) + "\n")
    files.append(manifest)
    notes = ROOT / "docs/v062-cashfix.md"
    package = ROOT / "downloads" / (NAME + ".zip")
    with zipfile.ZipFile(package, "w", zipfile.ZIP_DEFLATED) as archive:
        for path in files:
            archive.write(path, path.name)
        archive.write(notes, "INSTALL_AND_TEST.md")
    with zipfile.ZipFile(package) as archive:
        assert archive.testzip() is None
        assert archive.read(target.name) == target.read_bytes()
    print(f"Generated {target.name}, two matched presets, manifest and ZIP")


if __name__ == "__main__":
    build()
