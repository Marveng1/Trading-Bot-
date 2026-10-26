# Export FxPro research data without running an EA

`tools/MGS_ExportResearchData.mq5` is a read-only MT5 **script**, not a trading EA.
It requests historical bars and writes local CSV files. It contains no trade
requests and does not read credentials, account login, balance or API keys.
Compilation in MetaEditor and execution in MT5 remain **UNVERIFIED** in this
cloud environment. Host tests of the validation function do not establish MT5
runtime compatibility.

## Install and run

1. In the connected FxPro desktop MT5 terminal, select **File → Open Data Folder**.
2. Copy `MGS_ExportResearchData.mq5` into `MQL5/Scripts`. It is a single file and
   needs no custom includes, Python installation or Gemini key.
3. Press **F4**, open that script in MetaEditor, and press **F7**. Require zero
   errors; review any warnings. Keep the complete compiler output if it fails.
4. Return to MT5, refresh Navigator, open the GOLD chart, and run the script from
   **Navigator → Scripts**. No trading EA needs to be running. The script does
   not need Algo Trading enabled because it performs no trading operations.
5. Check the exact FxPro names in Market Watch. Defaults are `InpSymbol=GOLD`
   and `InpConversionSymbol=GBPUSD`; change them if your server uses suffixes.
   The exporter selects those symbols in Market Watch and reads their history.
6. Keep `InpFrom=2026.05.22 00:00:00` and `InpTo=2026.10.16 00:00:00` for the
   first export. **To is exclusive.** These defaults reflect the earliest real
   GOLD tick date observed in the supplied logs and the existing research end;
   the script exports **M1 bars**, not those underlying real ticks. The broker
   may have earlier bar history, which does not establish earlier tick coverage.
7. Read the final line in the Experts log. It identifies
   `MQL5/Files/MGS_Research_<local-clock-seconds>_<tickcount>` and both row counts.
   No previous export is overwritten. Requests use seven-day chunks, with at
   most three attempts and two one-second waits for a failed chunk. If history
   is not synchronized, finish loading it in MT5 and rerun as a **new** export.
8. Use **File → Open Data Folder → MQL5 → Files**, zip the entire reported
   `MGS_Research_...` folder, and upload that ZIP. Include the final Experts-log
   status line. Do not include terminal configuration, account passwords or
   unrelated files.

## Files and interpretation

| File | Contents |
| --- | --- |
| `metadata.csv` | Status, requested date bounds, symbol/file mapping, broker company/server, account currency/leverage, local export clock, row counts and interpretation notes. No login or balance. |
| `specs.csv` | Current contract size, tick size, point, digits, minimum/maximum/step volume, tick values for profit/loss, profit/margin currencies, stops/freeze distances and execution/calculation mode codes. Current tick values are account-currency snapshots, not historical conversions. |
| `GOLD_M1.csv` | The chosen gold symbol's M1 timestamp, OHLC, tick volume, bar spread in points and real volume. |
| `GBPUSD_M1.csv` | The chosen conversion symbol with the same schema. Fixed filenames remain unchanged when broker symbols have suffixes; metadata records the actual mapping. |
| `chunks.csv` | Each requested symbol/window, returned and written counts, invalid counts, first/last written timestamps, copy error, attempts and status. |

All bar timestamps and requested date bounds are **broker clock values without
a known UTC offset**. The numeric `broker_time_seconds` field encodes that same
broker timestamp; do not treat it as independently verified UTC. Supply a
broker-time/DST mapping before comparing calendar events or London/NY sessions.
`export_started_local_clock` instead describes the computer's local clock.

The script writes only finite, positive OHLC records with consistent high/low
bounds, nonnegative volumes/spread, in-window timestamps and strict ascending
order. Invalid records are skipped and make the export incomplete. It does
not fill absent minutes or create synthetic market data.
The interval filters **bar-open timestamps**. Keep date bounds aligned to whole
minutes; an arbitrary cutoff inside a minute does not truncate that bar's OHLC.

- **`EXPORTED_COVERAGE_UNVERIFIED`**: requested operations and record checks
  succeeded. Missing minutes, session closures and history completeness still
  require review. This does not mean complete tick history.
- **`COVERAGE_UNDETERMINED`**: at least one chunk or required dataset was empty.
  An empty chunk might reflect missing history or a market closure; inspect it.
- **`INCOMPLETE`**: a file, symbol, history request or record check failed, or the
  script was stopped. Preserve the manifest/log for diagnosis and rerun after
  correcting the issue. A disk failure can also prevent the metadata status
  from being saved; the final Experts-log line takes precedence.

M1 spreads are bar snapshots, not an executable bid/ask path. OHLC cannot tell
which of a stop or target was reached first inside a bar. These files support
fresh M15 hypothesis development, aggregation checks and data-quality review;
they do **not** constitute a real-tick execution backtest, a verified commission
schedule or proof of profitability. Broker contract settings can change over
time; the specs file is a current snapshot.

The August–October 2026 windows have already been consumed in strategy
selection. Treat this export as **development/research data**, preserve a run
manifest, and reserve genuinely later unseen dates for eventual holdout and
forward-demo evaluation. Do not relabel reused dates as untouched evidence.
