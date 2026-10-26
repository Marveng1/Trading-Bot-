# Fresh strategy research: baseline specification B01

Prepared 26 October 2026. Status: specification only. No new EA implementation,
MetaEditor compilation, historical backtest or profitability result is claimed.

## Why reset

The seven V062 entry-plus-legacy-exit systems lost over the supplied development
period. A matched hybrid-exit test also remained negative despite a higher win
rate. Its build, inputs and corrected cash-stop operation were confirmed in the
tester journal. Preserve the original sources and private research evidence;
do not tune those historical results away.

## One hypothesis

A completed M15 close beyond the previous twenty completed M15 bars may exhibit
continuation sufficient to cover actual execution costs. This is an unverified
hypothesis. The purpose is to test it with few moving parts, not to present it
as an established edge. No H1/EMA/RSI/FVG/AI filter is included in this baseline.
Any later filter must be a separately registered comparison.

## Frozen benchmark rules

- Exact FxPro GOLD contract; M15 signals on closed bars. Decide once on the first
  valid tick after each M15 close. Changing the old EA's chart timeframe alone
  does not implement these rules because its entries are hardcoded to M1.
- Buy if completed M15 close[1] strictly exceeds max(high[2..21]). Sell if it
  strictly falls below min(low[2..21]). The signal candle is excluded from its
  own breakout threshold. No entry at a retrospectively known candle-close price.
- Execute buys at Ask and sells at Bid, subject to current spread, session,
  blackout, account, pending-order, risk and margin eligibility.
- Initial stop: 1.5 times completed-M15 ATR14, widened outward where necessary
  for broker stop-distance/tick rules BEFORE sizing. Recheck final cash risk.
- Initial target: two times final initial stop distance from actual filled entry.
  This is gross price geometry, not a guaranteed net 2R outcome.
- No per-position break-even, cash lock, trailing, partial exit, automatic
  reversal, averaging or recovery in this baseline.
- Existing account-level daily loss/profit floors can override the position
  stop/target. Record those exits separately; do not assume all wins reach 2R.
- Broker-server entry sessions remain 07:00-11:00 and 13:00-17:00 as a fixed
  control, with existing rollover exclusion and manual event blackouts. They
  are not automatically London time or evidence of optimal sessions.
- At most one account exposure, counting pending orders; dedicated hedging demo,
  instance coordination, persistent risk state and uncertain-order quarantine.
- Lot ceiling 0.01. Planned cash risk is min(15 GBP, 1.5% equity, daily floor room)
  on a GBP test account. GBP500 initially permits at most GBP7.50 and GBP1000
  at most GBP15. If broker-minimum volume exceeds budget or margin, SKIP.
  Do not tighten the model's stop or increase volume merely to make it trade.

20, ATR14, 1.5 ATR and 2R are unoptimized benchmark constants, not claimed optimal
settings. Stop/target prices and the win rate cannot be chosen independently.
The account protections also make the equity path affect later eligibility.

## Evidence required before judging the hypothesis

1. Exact broker specifications, account currency/leverage and actual commissions.
2. Timestamped price coverage, session/DST mapping, and bid/ask ticks for execution
   validation. Broker OHLC can screen signals and minimum-lot stop feasibility,
   but cannot resolve changing spreads, slippage, or SL/TP ordering within a bar.
3. A tested fill/accounting engine or MT5 implementation. Verify forced closes,
   actual fills/volume, fees, currency conversion, daily accounting and failure
   handling separately from signal logic.
4. Closed-position/deal and equity exports. The current text journals do not
   contain complete actual GBP profit/commission fields or tick-exact MFE/MAE.
5. Freeze source, settings, costs, date partitions and trial count before looking
   at validation outcomes. August-October is development/selection data now.
   Earlier unseen dates can support retrospective robustness, while stronger
   chronological confirmation requires reserved later/prospective data.

Reject the hypothesis if realistic net economics or minimum-lot feasibility fail.
Do not search parameter grids until the first frozen baseline has been evaluated.
Risk-adjusted improvement, uncertainty, execution tails and regime coverage matter;
a higher win rate alone is not an acceptance condition. Gemini remains a future,
separately measured experiment after a deterministic baseline is established.
