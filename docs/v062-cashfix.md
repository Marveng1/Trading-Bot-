# V062 cash-stop pricing repair candidate

This build repairs a monetary-price calculation and adds diagnostic logging.
It is demo-only. It has not been compiled in MetaEditor or backtested here.
It does not establish a profitable strategy. Keep V061 for reproducing its results.

## Why this correction was prepared

Two supplied tester runs genuinely selected V061 hybrid exit mode 3 and legacy
mode 0, yet all recorded trade actions matched. This establishes that cash
protection produced no different accepted stop in those runs; it does not by
itself identify the cause.

The original cash-stop function divides the cash target by the profit calculated
for a ONE-tick move, then allows only six corrective ticks. Such a tiny profit
may be distorted by account-currency rounding or may round to zero. A rounded
profit simulation reproduces a failure with the exact V061 function: a feasible
cash target is rejected despite valid prices existing. The logs' first
break-even moves are consistent with this explanation. The actual broker API
rounding must still be confirmed using the new diagnostics.

## Changes

- Cash stops now search the tick grid using direct account-currency profit
  valuations. They bracket the target, bisect, and verify the final estimated
  net amount. They do not extrapolate from a one-tick profit ratio.
- Search is bounded to one million favorable ticks and 64 observations; short
  candidates must remain positive. Missing/invalid valuation produces no candidate.
- Break-even uses the same verified zero-net target, including the existing
  fee estimate and stop-slippage reserve, then adds the existing extra-tick buffer.
  This corrects the related precision issue; it also means V062 legacy behavior
  can differ from V061 legacy. Compare modes within the SAME build.
- Once per cash-activated position, `CASH_DIAGNOSTIC` records one-tick and
  100-tick profit probes, desired net, proposed stop/net, broker minimum distance,
  candidate selection and modification eligibility. A found target is not a
  claim that the broker permits its placement or guarantees its execution.
- Entry strategy, demo-only gate, 15-account-currency/1.5% risk ceilings, 0.01 lot
  ceiling and daily protections are retained. The existing account mutex,
  daily state and uncertain-submission quarantine remain shared with V061.
  A new version does not reset a halt or permit simultaneous V061/V062 instances.

Costs are still research estimates. The previously observed stop fills sometimes
exceeded the ten-tick reserve. This arithmetic correction does not make that
reserve sufficient or make losses guaranteed. No slippage setting was retuned.

## Install

Use `MarvGoldScalper_V062_CashFix_Standalone.mq5`, which embeds both supporting
headers. Copy it to the current MT5 terminal's `MQL5/Experts` folder, open that
exact file in MetaEditor, and press F7. The first line says SINGLE-FILE V062
CASHFIX. MT5's standard `Trade/Trade.mqh` remains required. Refresh Navigator
after a successful compile; retain the complete compilation result.

Use Strategy Tester for this check. Do not replace a running EA with open
positions, and do not run old and new EA instances on the same demo account.
Source orders default OFF; the two clearly named DEMO_TESTER presets enable
orders only within the EA's existing demo restrictions.

## Matched tests, with no parameter optimization

Use exact FxPro GOLD, M1, GBP1,000 when supported, 12 October 2026 00:00 to
16 October 2026 00:00, real ticks, optimization OFF, same leverage/delay/cost
assumptions for both runs. These reused dates are mechanical development data.
Record actual currency and settings; the presets do not configure tester dates,
deposit, leverage, currency, modelling or delay.

1. Select the V062 CashFix standalone expert in Strategy Tester.
2. Under the TESTER Inputs tab, right-click > Load (or the available Load control)
   and choose `DEMO_TESTER_V062_EMA_Legacy.set`. Verify `InpMode=0`, exit mode
   **same exit behavior as V0.4** (0), and demo orders true. Run and save results.
3. Load `DEMO_TESTER_V062_EMA_Hybrid.set`. The only input difference is exit mode
   **money-based protection plus ATR/R trailing** (3). Run and save results.
4. Save the complete tester journal and original HTML/deal report for each.
   The hybrid journal should identify `MGS V062 CASHFIX`, `EXIT TEST: mode=3`
   and, when a position reaches its trigger, `CASH_DIAGNOSTIC` records.

No activated trigger means no such diagnostic is expected; that is not a passing
cash-logic check. Target found, legality, selected candidate and actual broker
modification are separate steps. Compare these before interpreting performance.
Do not select new parameters just because one short result improves.

## Local verification boundary

Host tests execute extracted broker-wrapper functions with controlled rounded
profit calculations and execute the exact shared search header. They reproduce
the old failure and exercise the correction, including invalid/unreachable
targets. These tests are neither MetaEditor compilation nor an FxPro backtest.
Live API behavior, broker constraints and any performance benefit remain unverified.
