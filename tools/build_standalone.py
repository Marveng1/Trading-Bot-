#!/usr/bin/env python3
"""Build a single-file EA from the frozen, committed V061 research ZIP.

Only the local MGSCore include is expanded. Trading logic is unchanged.
This is packaging, not MQL5 compilation or an MT5 execution test.
"""
from pathlib import Path
import hashlib
import zipfile

ROOT = Path(__file__).resolve().parents[1]
PACKAGE = ROOT / "downloads/MarvGoldScalper_V061_Research_Candidate.zip"
DESTINATION = ROOT / "downloads"
NAME = "MarvGoldScalper_V061_Standalone"
SOURCE_PATH = "MarvGoldScalper_V061/source/MarvGoldScalper_V061.mq5"
CORE_PATH = "MarvGoldScalper_V061/source/MGSCore.mqh"
MARKER = '#include "MGSCore.mqh"'
BANNER = (
    "// SINGLE-FILE V061 RESEARCH CANDIDATE: supporting code embedded.\n"
    "// DEMO ONLY. Still requires MetaEditor compilation and MT5 validation.\n"
    "// No separate MGSCore.mqh file is required.\n"
)


def build():
    with zipfile.ZipFile(PACKAGE) as archive:
        if archive.testzip() is not None:
            raise RuntimeError("Original archive integrity check failed")
        source = archive.read(SOURCE_PATH).decode("utf-8")
        core = archive.read(CORE_PATH).decode("utf-8")
    if source.count(MARKER) != 1 or '#include <Trade/Trade.mqh>' not in source:
        raise RuntimeError("Unexpected source layout; refusing to build")
    flattened = BANNER + source.replace(MARKER, core)
    if MARKER in flattened or flattened.count("void OnTick()") != 1:
        raise RuntimeError("Unexpected generated source")
    destination = DESTINATION / (NAME + ".mq5")
    destination.write_text(flattened, encoding="utf-8")
    instructions = f"""MarvGoldScalper V061 - SINGLE FILE

This package fixes the missing MGSCore.mqh installation dependency by embedding
that code in the EA. No trading strategy or safety policy was changed.
It has NOT been compiled in MetaEditor or backtested here. DEMO ONLY.

INSTALL ON WINDOWS FXPRO MT5
1. In MT5 choose File > Open Data Folder.
2. Open MQL5 > Experts.
3. Copy {NAME}.mq5 into that Experts folder.
4. Press F4 from the same MT5 terminal.
5. In MetaEditor choose File > Open and open this standalone file from Experts.
6. Press F7. The active tab must say {NAME}.mq5.
7. Compilation must finish with 0 errors before an .ex5 EA is generated.
8. Return to MT5: Ctrl+N > Expert Advisors > right-click > Refresh.

PASTE INSTEAD OF COPYING A FILE
1. Copy the complete standalone source from its GitHub code page.
2. In MetaEditor choose File > New > Expert Advisor (template).
3. Name it {NAME}; complete the wizard without adding extra event handlers.
4. Ctrl+A in the generated source, paste the ENTIRE standalone code, Ctrl+S, F7.

No separate MGSCore.mqh is needed. MT5's standard Trade/Trade.mqh remains required
and is normally supplied with MT5. Do not delete the standard include.

Orders default OFF. Use Strategy Tester/demo only after compilation. Close or
detach the older EA instances before running this one: its account ownership
lock does not coordinate legacy versions. Dedicated hedging demo account only.

If compilation fails, share the COMPLETE Errors panel and filename. A message
about compiling is not proof of success: check the final error count.

Generated file SHA256: {hashlib.sha256(destination.read_bytes()).hexdigest()}
"""
    guide = DESTINATION / (NAME + "_INSTALL.txt")
    guide.write_text(instructions, encoding="utf-8")
    package = DESTINATION / (NAME + ".zip")
    with zipfile.ZipFile(package, "w", zipfile.ZIP_DEFLATED) as archive:
        archive.write(destination, destination.name)
        archive.write(guide, "INSTALL.txt")
    with zipfile.ZipFile(package) as archive:
        assert archive.testzip() is None
        assert archive.read(destination.name) == destination.read_bytes()
    print(f"Generated {destination.name}: {destination.stat().st_size} bytes")
    print(f"Generated {package.name}; no separate custom header needed")


if __name__ == "__main__":
    build()
