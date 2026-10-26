//+------------------------------------------------------------------+
//| MarvGoldScalper_V062_CashFix.mq5                                          |
//| V06.2 CASHFIX CANDIDATE. DEMO ONLY. NOT MT5-COMPILED.       |
//| V05 controls plus 10s EMA-PSAR / EMA Fibonacci / FVG-OB       |
//| Risk ceiling cash + equity pct, broker sizing, exit models.  |
//| Do not trade live: needs independent review and real tick tests.     |
//+------------------------------------------------------------------+
#property copyright "Independent demo research"
#property version   "1.062"
#property strict
#include <Trade/Trade.mqh>
#include "MGSCore.mqh"
#include "MGSCashSearch.mqh"

enum ENUM_MGS_MODE
{
   MGS_EMA_BASELINE = 0,
   MGS_EMA_RSI_M5 = 1,
   MGS_ADVANCED = 2,
   MGS_RANGE_BREAKOUT = 3,
   MGS_EMA_PSAR_10S = 4,
   MGS_FIB_EMA = 5,
   MGS_FVG_OB = 6
};

enum ENUM_MGS_EXIT
{
   MGS_EXIT_LEGACY_R = 0,      // same exit behavior as V0.4
   MGS_EXIT_FIXED_CASH = 1,   // market-close at estimated net cash profit
   MGS_EXIT_CASH_LOCK = 2,    // trail money-based stop; no fixed cash TP
   MGS_EXIT_HYBRID = 3        // money-based protection plus ATR/R trailing
};

// GENERAL: OFF means print candidates only. Real-money accounts are BLOCKED.
input ENUM_MGS_MODE InpMode = MGS_EMA_PSAR_10S;
input bool   InpEnableDemoOrders = false;
input string InpExpectedSymbol = "GOLD";  // FxPro demo symbol, not necessarily XAUUSD
input ulong  InpMagic = 20261023;
input int    InpDeviationPoints = 30;
input bool   InpLogDecisions = true;
input bool   InpCSVLog = true; // MT5 Files sandbox; no credentials

// ACCOUNT PROTECTION: limits are not guarantees under gaps/slippage.
input double InpRiskCash = 15.00;          // MAX RISK in account currency: GBP account = GBP 15
input double InpRiskPct = 1.50;              // ALSO cap risk at 1.5% of equity; GBP500 -> GBP7.50
input double InpMaxLots = 0.01;              // preferred upper limit; actual risk sizing may skip
input double InpDayLossPct = 3.00;           // hard floor relative to broker-day starting EQUITY
input double InpProfitLockActivatePct = 0.50;// profit lock activates above 0.5% of day-start equity
input double InpProfitKeepPct = 70.0;        // protect 70% of maximum accumulated daily profit
input double InpRoundTripFeePerLot = 7.0;    // fee ESTIMATE in ACCOUNT currency per 1.00 lot
input double InpSlipReserveTicks = 10.0;     // planned adverse SL slippage reserve in ticks
input double InpMaxMarginPctFree = 35.0;
input bool   InpRequireExclusiveAccount = true; // no other open positions while initiating trades
input int    InpMaxTradesPerDay = 100;       // emergency ceiling, not a trade target
input int    InpMinSecondsBetweenEntries = 45;

// ELIGIBLE HOURS: if InpUseSessions=false, trading is still constrained by broker hours,
// weekends, manual news blackouts, spread, and a midnight rollover exclusion.
input bool   InpUseSessions = true;
input int    InpSession1Start = 7;
input int    InpSession1End = 11;
input int    InpSession2Start = 13;
input int    InpSession2End = 17;
input int    InpAvoidRolloverMinutes = 20;    // skip entry 23:40-00:20 server time
input datetime InpManualBlackoutStart = 0;
input datetime InpManualBlackoutEnd = 0;

// TRADE EXECUTION AND TRAILING (NO fixed TP by default)
input double InpMaxSpreadATR = 0.20;
input int    InpMaxSpreadPoints = 80; // absolute spread ceiling in symbol points
input double InpMaxM1SpikeATR = 3.0; // skip entries immediately after unusual M1 moves
input double InpStopATR = 1.50;
input bool   InpUseFixedTP = false;
input double InpTargetR = 1.80;              // used only when InpUseFixedTP=true
input double InpBreakEvenR = 1.00;
input double InpTrailStartR = 1.50;
input double InpTrailATR = 1.20;
input double InpMinModifyTicks = 20.0;
input int    InpMinModifySeconds = 15;
input double InpBEExtraTicks = 10.0;

// V0.5 EXIT EXPERIMENTS. All money amounts are in TESTER ACCOUNT CURRENCY.
// Demo/backtest only. Targets are estimated net of an assumed round-trip fee.
// 0 holding seconds disables the time exit (needed to reproduce V0.4 exits).
input ENUM_MGS_EXIT InpExitMode = MGS_EXIT_HYBRID;
input double InpCashTakeProfit = 1.00;     // fixed-cash mode: net account currency
input double InpCashLockTrigger = 0.50;   // cash-lock modes: activate at peak net P/L
input double InpCashLockKeepPct = 65.0;   // protect this percentage of peak net P/L
input double InpCashLockMinNet = 0.10;    // minimum net profit requested at SL
input int    InpMaxHoldingSeconds = 0;  // 0=off, test 30/60/120/180


// EMA, RSI, M5 and advanced confirmation filters
input double InpRSIBuyAbove = 52.0;
input double InpRSISellBelow = 48.0;
input double InpRSIUpperLimit = 75.0;
input double InpRSILowerLimit = 25.0;
input double InpADXMinimum = 18.0;
input double InpMinCandleBodyFraction = 0.50;
input double InpMinImpulseRangeATR = 0.45;
input int    InpStructureLookback = 12;
input double InpMinRoomToLevelATR = 0.75;
input int    InpRequiredAdvancedExtras = 2;
input bool   InpCheckSRRoom = true;

// INDEPENDENT OPENING RANGE BREAKOUT EXPERIMENT: ALL HOURS BELOW ARE BROKER SERVER TIME.
// Based only on completed M15 bars in a finished range, then M1 close confirms breakout.
input int    InpBORangeStartHour = 7;
input int    InpBORangeEndHour = 9;
input int    InpBOLastEntryHour = 15;
input double InpBOBreakoutBufferATR = 0.10;

// V06 RESEARCH MODES: closed 10-second bars are assembled FROM INCOMING REAL TICKS.
// These are synthetic mid-price candles, not native MT5 10-second indicator buffers.
input bool   Inp10sRequireTwoBars = true;
input double Inp10sMinRangeSpreadMult = 1.50;
input int    InpFibLookbackM5 = 48;
input bool   InpFibRequireM15Confirmation = true;
input int    InpFVGMaxAgeM5Bars = 8;
input double InpFVGMinImpulseATR = 0.70;
input bool   InpFVGRequireOrderBlock = false; // hypothesis test, not proven improvement
input int    InpOBLookbackBars = 12;


CTrade trade;
int hEma9=INVALID_HANDLE, hEma21=INVALID_HANDLE, hEma20M5=INVALID_HANDLE;
int hEma50M5=INVALID_HANDLE, hRsi=INVALID_HANDLE, hAtr=INVALID_HANDLE;
int hAdxM5=INVALID_HANDLE;
int hEma5M1=INVALID_HANDLE,hEma20M1=INVALID_HANDLE,hEma40M1=INVALID_HANDLE;
int hEma5M5=INVALID_HANDLE,hEma40M5=INVALID_HANDLE;
int hSarM1=INVALID_HANDLE,hSarM5=INVALID_HANDLE;
int hEma50M15=INVALID_HANDLE,hEma50H1=INVALID_HANDLE,hEma200H1=INVALID_HANDLE;
int hAtrM5=INVALID_HANDLE;
MGSTenState gTenState;
double gSignalZoneLower=0.0,gSignalZoneUpper=0.0;
double gLastTenRange=0.0;
int gPrevTenDir=0,gLastTenDir=0;
bool gTenBarClosed=false;

datetime lastBar=0;
string gStartKey="", gPeakKey="", gHaltKey="";
string gDay="";
string gInstanceKey="",gFlightKey="";
double gInstanceToken=0.0,gFlightBudget=0.0;
ulong gFlightOrder=0;
bool gSubmitting=false;
int gLogHandle=INVALID_HANDLE;
string gRunId="";
datetime gLastEquityLog=0;

// V062 intentionally shares the V061 mutex/day/quarantine namespace: no reset
// of existing safety state. Only one owner per account in THIS terminal. Separate terminals/VPSs
// cannot coordinate through terminal globals and must not share this account.
string AccountPrefix()
{
   string server=AccountInfoString(ACCOUNT_SERVER);
   uint hash=2166136261;
   for(int i=0;i<StringLen(server);i++)
      hash=(hash^(uint)StringGetCharacter(server,i))*16777619;
   return "MGS061_"+(string)AccountInfoInteger(ACCOUNT_LOGIN)+"_"+(string)hash+"_";
}

bool AcquireInstance()
{
   gInstanceKey=AccountPrefix()+"owner";
   if(!GlobalVariableTemp(gInstanceKey)) return false;
   gInstanceToken=(double)ChartID();
   if(gInstanceToken==0.0) gInstanceToken=1.0;
   if(!GlobalVariableSetOnCondition(gInstanceKey,gInstanceToken,0.0))
   {
      Print("SAFETY: another V061/V062 instance owns this account in this terminal.");
      gInstanceToken=0.0;
      return false;
   }
   return true;
}

void ReleaseInstance()
{
   if(gInstanceToken!=0.0)
      GlobalVariableSetOnCondition(gInstanceKey,0.0,gInstanceToken);
   gInstanceToken=0.0;
}

bool InFlight()
{
   return gFlightKey!="" && GlobalVariableGet(gFlightKey)>0.5;
}

bool SetFlight(bool pending)
{
   if(GlobalVariableSet(gFlightKey,pending?1.0:0.0)==0)
   {
      Print("SAFETY: cannot persist entry quarantine; error=",GetLastError());
      return false;
   }
   GlobalVariablesFlush();
   return true;
}

bool TradeAttemptDue(string key,int seconds)
{
   datetime now=TimeCurrent();
   if(GlobalVariableCheck(key) &&
      now-(datetime)GlobalVariableGet(key)<seconds) return false;
   // Throttle attempts, including failures. This is not a success timestamp.
   GlobalVariableSet(key,(double)now);
   return true;
}

// CSV timestamps are BROKER SERVER timestamps; no UTC offset is guessed.
void MGSLog(string event,string detail,ulong ticket=0,ulong order=0,ulong deal=0,
            uint retcode=0,double volume=0.0,double price=0.0,double sl=0.0,
            double tp=0.0,double risk=0.0,double budget=0.0)
{
   if(gLogHandle==INVALID_HANDLE) return;
   MqlTick q={};
   SymbolInfoTick(_Symbol,q);
   StringReplace(detail,",",";"); StringReplace(detail,"\r"," "); StringReplace(detail,"\n"," ");
   ResetLastError();
   uint written=FileWrite(gLogHandle,gRunId,event,TimeToString(TimeCurrent(),TIME_DATE|TIME_SECONDS),
             AccountInfoString(ACCOUNT_CURRENCY),(int)InpMode,(int)InpExitMode,
             _Symbol,InpMagic,ticket,order,deal,retcode,
             DoubleToString(q.bid,_Digits),DoubleToString(q.ask,_Digits),
             DoubleToString(volume,8),DoubleToString(price,_Digits),
             DoubleToString(sl,_Digits),DoubleToString(tp,_Digits),
             DoubleToString(risk,8),DoubleToString(budget,8),
             DoubleToString(AccountInfoDouble(ACCOUNT_EQUITY),8),detail);
   if(event!="EQUITY") FileFlush(gLogHandle);
   if(written==0 || GetLastError()!=0)
   {
      Print("CSV WRITE/FLUSH FAILURE: new entries blocked while enabled.");
      FileClose(gLogHandle); gLogHandle=INVALID_HANDLE;
   }
}

void OpenEventLog()
{
   if(!InpCSVLog) return;
   gRunId=(string)(long)TimeLocal()+"_"+(string)GetTickCount64()+"_"+(string)ChartID();
   string filename="MGS062_events_"+(string)AccountInfoInteger(ACCOUNT_LOGIN)+"_"+
                   (string)InpMagic+"_"+_Symbol+"_"+gRunId+".csv";
   if(FileIsExist(filename)) { Print("CSV NAME COLLISION: new entries blocked."); return; }
   gLogHandle=FileOpen(filename,FILE_READ|FILE_WRITE|FILE_CSV|FILE_ANSI|FILE_SHARE_READ,',');
   if(gLogHandle==INVALID_HANDLE)
   { Print("CSV LOG UNAVAILABLE: new entries blocked; existing management remains active."); return; }
   if(FileSize(gLogHandle)==0)
   {
      ResetLastError();
      uint headerWritten=FileWrite(gLogHandle,"run_id","event","broker_time","account_currency","mode","exit_mode",
                "symbol","magic","ticket","order","deal","retcode","bid","ask",
                "volume","price","sl","tp","risk","budget","equity","detail");
      if(headerWritten==0 || GetLastError()!=0)
      { FileClose(gLogHandle); gLogHandle=INVALID_HANDLE; return; }
   }
   FileSeek(gLogHandle,0,SEEK_END);
}

// UTILITIES ---------------------------------------------------------
double TickSize()
{
   double t=SymbolInfoDouble(_Symbol,SYMBOL_TRADE_TICK_SIZE);
   return (t>0.0?t:_Point);
}

double SnapPrice(double price)
{
   return NormalizeDouble(MathRound(price/TickSize())*TickSize(),_Digits);
}

bool ReadIndicator(int h,int shift,double &out,int buffer=0)
{
   double temp[];
   if(CopyBuffer(h,buffer,shift,1,temp)!=1) return false;
   out=temp[0];
   return MathIsValidNumber(out) && out!=EMPTY_VALUE;
}

bool DemoEnvironment()
{
   return AccountInfoInteger(ACCOUNT_TRADE_MODE)==ACCOUNT_TRADE_MODE_DEMO;
}

string Prefix()
{
   return "MGS06_"+(string)AccountInfoInteger(ACCOUNT_LOGIN)+"_"+
          (string)InpMagic+"_"+_Symbol+"_";
}

string PositionRiskKey()
{
   return Prefix()+"risk_"+(string)PositionGetInteger(POSITION_IDENTIFIER);
}

string PositionModifyKey()
{
   return Prefix()+"mod_"+(string)PositionGetInteger(POSITION_IDENTIFIER);
}

string PositionPeakNetKey()
{
   return Prefix()+"peaknet_"+(string)PositionGetInteger(POSITION_IDENTIFIER);
}

string PositionForceCloseKey()
{
   return Prefix()+"close_"+(string)PositionGetInteger(POSITION_IDENTIFIER);
}

// Persistent terminal global variables preserve the day's thresholds on restart.
// Research caveat: deposits/withdrawals and foreign-account trades distort equity tracking.
void RefreshDay()
{
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(),dt);
   string day=StringFormat("%04d%02d%02d",dt.year,dt.mon,dt.day);
   if(day==gDay) return;
   bool firstAttach=(gDay=="");
   gDay=day;
   string stem=AccountPrefix()+day;
   gStartKey=stem+"_start";
   gPeakKey=stem+"_peak";
   gHaltKey=stem+"_halt";
   if(!GlobalVariableCheck(gStartKey))
   {
      string legacy=Prefix()+day;
      bool migrate=(GlobalVariableCheck(legacy+"_start") &&
                    GlobalVariableCheck(legacy+"_peak") &&
                    GlobalVariableCheck(legacy+"_halt"));
      if(migrate)
      {
         GlobalVariableSet(gStartKey,GlobalVariableGet(legacy+"_start"));
         GlobalVariableSet(gPeakKey,GlobalVariableGet(legacy+"_peak"));
         GlobalVariableSet(gHaltKey,GlobalVariableGet(legacy+"_halt"));
         Print("DAY STATE: migrated matching V06 state; no daily allowance reset.");
      }
      else
      {
         GlobalVariableSet(gStartKey,AccountInfoDouble(ACCOUNT_EQUITY));
         Print("DAY START EQUITY CAPTURED: ",DoubleToString(GlobalVariableGet(gStartKey),2),
               " ",AccountInfoString(ACCOUNT_CURRENCY),
               ". If EA starts mid-session, earlier P/L is not reconstructed.");
         // A fresh demo attach cannot reconstruct midnight floating equity.
         // Quarantine that broker day. Tester runs are explicitly independent.
         if(firstAttach && !MQLInfoInteger(MQL_TESTER))
         {
            GlobalVariableSet(gHaltKey,1.0);
            Print("SAFETY: no saved broker-day baseline; new entries halted until next broker day.");
         }
      }
   }
   if(!GlobalVariableCheck(gPeakKey)) GlobalVariableSet(gPeakKey,0.0);
   if(!GlobalVariableCheck(gHaltKey)) GlobalVariableSet(gHaltKey,0.0);
   GlobalVariablesFlush();
}

double DayStartEquity()
{
   RefreshDay();
   return GlobalVariableGet(gStartKey);
}

// Prospective risk must preserve BOTH the day-loss floor and any active
// profit-lock floor. A new trade must not knowingly spend locked-in profit.
double AccountRiskFloor()
{
   RefreshDay();
   double start=GlobalVariableGet(gStartKey);
   double floor=start*(1.0-InpDayLossPct/100.0);
   double peak=MathMax(0.0,GlobalVariableGet(gPeakKey));
   if(peak>=start*InpProfitLockActivatePct/100.0)
      floor=MathMax(floor,start+peak*InpProfitKeepPct/100.0);
   return floor;
}

bool DailyHalt()
{
   RefreshDay();
   double start=GlobalVariableGet(gStartKey);
   double equity=AccountInfoDouble(ACCOUNT_EQUITY);
   if(start<=0.0 || equity<=0.0) return true;
   double today=equity-start;
   double peak=MathMax(0.0,GlobalVariableGet(gPeakKey));
   if(today>peak)
   {
      peak=today;
      GlobalVariableSet(gPeakKey,peak);
   }
   bool hardLoss=(equity<=start*(1.0-InpDayLossPct/100.0));
   bool lockActive=(peak>=start*InpProfitLockActivatePct/100.0);
   bool gaveBack=(lockActive && today<=peak*(InpProfitKeepPct/100.0));
   if((hardLoss || gaveBack) && GlobalVariableGet(gHaltKey)<0.5)
   {
      GlobalVariableSet(gHaltKey,1.0);
      GlobalVariablesFlush();
      PrintFormat("DAILY HALT %s | start=%.2f peakPnL=%.2f nowPnL=%.2f | trading blocked until next BROKER day",
                  hardLoss?"LOSS LIMIT":"PROFIT LOCK",start,peak,today);
   }
   return GlobalVariableGet(gHaltKey)>=0.5;
}

bool OurPosition(const ulong ticket)
{
   if(!PositionSelectByTicket(ticket)) return false;
   return PositionGetString(POSITION_SYMBOL)==_Symbol &&
          (ulong)PositionGetInteger(POSITION_MAGIC)==InpMagic;
}

bool HasAnySymbolPosition()
{
   for(int i=PositionsTotal()-1;i>=0;i--)
   {
      ulong ticket=PositionGetTicket(i);
      if(ticket>0 && PositionSelectByTicket(ticket) &&
         PositionGetString(POSITION_SYMBOL)==_Symbol) return true;
   }
   return false;
}

bool CanUseAccount()
{
   // Pending orders can create exposure after a position-only check.
   // V061 supports a dedicated account only; external terminals remain outside
   // this terminal lock and are prohibited by the operating instructions.
   return InpRequireExclusiveAccount && PositionsTotal()==0 && OrdersTotal()==0;
}

bool InWindow(int hour,int begin,int end)
{
   if(begin==end) return false;
   if(begin<end) return hour>=begin && hour<end;
   return hour>=begin || hour<end;
}

bool SessionOK()
{
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(),dt);
   if(dt.day_of_week==0 || dt.day_of_week==6) return false;
   int mins=dt.hour*60+dt.min;
   if(InpAvoidRolloverMinutes>0 &&
      (mins<InpAvoidRolloverMinutes || mins>=1440-InpAvoidRolloverMinutes)) return false;
   if(InpManualBlackoutStart>0 && InpManualBlackoutEnd>InpManualBlackoutStart &&
      TimeCurrent()>=InpManualBlackoutStart && TimeCurrent()<InpManualBlackoutEnd) return false;
   if(!InpUseSessions) return true;
   return InWindow(dt.hour,InpSession1Start,InpSession1End) ||
          InWindow(dt.hour,InpSession2Start,InpSession2End);
}

int TradesToday()
{
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(),dt);
   dt.hour=0; dt.min=0; dt.sec=0;
   if(!HistorySelect(StructToTime(dt),TimeCurrent())) return InpMaxTradesPerDay;
   int count=0;
   for(int i=HistoryDealsTotal()-1;i>=0;i--)
   {
      ulong d=HistoryDealGetTicket(i);
      if(d==0 || HistoryDealGetString(d,DEAL_SYMBOL)!=_Symbol) continue;
      if((ulong)HistoryDealGetInteger(d,DEAL_MAGIC)!=InpMagic) continue;
      if((ENUM_DEAL_ENTRY)HistoryDealGetInteger(d,DEAL_ENTRY)==DEAL_ENTRY_IN) count++;
   }
   return count;
}

bool CooldownOK()
{
   datetime now=TimeCurrent();
   if(!HistorySelect(now-86400,now)) return false;
   for(int i=HistoryDealsTotal()-1;i>=0;i--)
   {
      ulong d=HistoryDealGetTicket(i);
      if(d==0 || HistoryDealGetString(d,DEAL_SYMBOL)!=_Symbol) continue;
      if((ulong)HistoryDealGetInteger(d,DEAL_MAGIC)!=InpMagic) continue;
      if((ENUM_DEAL_ENTRY)HistoryDealGetInteger(d,DEAL_ENTRY)!=DEAL_ENTRY_IN) continue;
      return (now-(datetime)HistoryDealGetInteger(d,DEAL_TIME))>=InpMinSecondsBetweenEntries;
   }
   return true;
}

// ACCOUNT-CURRENCY RISK using OrderCalcProfit plus slippage/commission allowance.
// Slippage reserve and estimated fees are not guarantees of the eventual loss.
bool ProjectedLoss(ENUM_ORDER_TYPE side,double lots,double entry,double stop,double &risk)
{
   bool buy=(side==ORDER_TYPE_BUY);
   double worstStop=stop+(buy?-1.0:1.0)*InpSlipReserveTicks*TickSize();
   double gross=0.0;
   if(!OrderCalcProfit(side,_Symbol,lots,entry,worstStop,gross)) return false;
   risk=MathMax(0.0,-gross)+lots*InpRoundTripFeePerLot;
   return (risk>0.0 && MathIsValidNumber(risk));
}

// V062 corrects the shared single-tick monetary conversion approximation.
// Zero means no verified candidate; there is deliberately no price-only fallback.
double BreakevenPrice(bool buy,double entry,double lots,double swap)
{
   double stop=0.0;
   if(!FindNetStop(buy,lots,entry,swap,0.0,true,stop)) return 0.0;
   double sign=(buy?1.0:-1.0);
   stop=SnapPrice(stop+sign*InpBEExtraTicks*TickSize());
   double verified=0.0;
   if(stop<=0.0 || !MathIsValidNumber(stop) ||
      !EstimateNetExit(buy,lots,entry,stop,swap,true,verified) || verified+1e-8<0.0)
      return 0.0;
   return stop;
}

// Estimate the net P/L if the position is closed at a specified price.
// OrderCalcProfit incorporates contract and currency-conversion rules, but
// the round-trip fee is only an estimate. Swaps are read from this position.
// At the SL we also model adverse slippage. This is NOT guaranteed protection.
bool EstimateNetExit(bool buy,double lots,double entry,double closePrice,
                     double swap,bool stopExecution,double &net)
{
   double worstClose=closePrice;
   if(stopExecution)
      worstClose+=(buy?-1.0:1.0)*InpSlipReserveTicks*TickSize();
   double gross=0.0;
   ENUM_ORDER_TYPE side=(buy?ORDER_TYPE_BUY:ORDER_TYPE_SELL);
   if(!OrderCalcProfit(side,_Symbol,lots,entry,worstClose,gross)) return false;
   net=gross-lots*InpRoundTripFeePerLot+swap;
   return MathIsValidNumber(net);
}

// Evaluate actual account-currency net P/L at integer tick offsets. The shared
// search brackets the target, then bisects; no one-tick ratio is extrapolated.
// This assumes net P/L is monotone with a favorable GOLD price move under the
// current conversion context. Final valuation is checked again and fails closed.
bool FindNetStop(bool buy,double lots,double entry,double swap,double wantedNet,
                 bool stopExecution,double &stop)
{
   stop=0.0;
   double tick=TickSize();
   if(!MathIsValidNumber(lots) || lots<=0.0 || !MathIsValidNumber(entry) || entry<=0.0 ||
      !MathIsValidNumber(swap) || !MathIsValidNumber(wantedNet) || wantedNet<0.0 ||
      !MathIsValidNumber(tick) || tick<=0.0 ||
      !MathIsValidNumber(InpRoundTripFeePerLot) || InpRoundTripFeePerLot<0.0 ||
      !MathIsValidNumber(InpSlipReserveTicks) || InpSlipReserveTicks<0.0) return false;
   long maximum=1000000;
   if(!buy)
   {
      double positiveTicks=MathFloor(entry/tick)-1.0;
      if(!MathIsValidNumber(positiveTicks) || positiveTicks<0.0) return false;
      maximum=(long)MathMin((double)maximum,positiveTicks);
   }
   MGSCashSearch search;
   if(!MGSBeginCashSearch(search,maximum)) return false;
   double sign=(buy?1.0:-1.0);
   while(!search.finished)
   {
      double price=SnapPrice(entry+sign*(double)search.probe*tick);
      double estimated=0.0;
      if(price<=0.0 || !MathIsValidNumber(price) ||
         !EstimateNetExit(buy,lots,entry,price,swap,stopExecution,estimated)) return false;
      MGSObserveCashSearch(search,estimated,wantedNet);
   }
   if(search.failed) return false;
   double price=SnapPrice(entry+sign*(double)search.upper*tick);
   double verified=0.0;
   if(price<=0.0 || !MathIsValidNumber(price) ||
      !EstimateNetExit(buy,lots,entry,price,swap,stopExecution,verified) ||
      verified+1e-8<wantedNet) return false;
   stop=price;
   return true;
}

// Broker minimum-stop/freeze rules are checked separately by ManagePositions.
bool CashStopPrice(bool buy,double lots,double entry,double swap,
                   double wantedNet,double &stop)
{
   return FindNetStop(buy,lots,entry,swap,wantedNet,true,stop);
}

bool CloseWithReason(ulong ticket,string why)
{
   if(!OurPosition(ticket)) return true;
   GlobalVariableSet(PositionForceCloseKey(),1.0);
   GlobalVariablesFlush();
   if(!TradeAttemptDue(Prefix()+"exittry_"+(string)ticket,3)) return false;
   MGSLog("EXIT_ATTEMPT",why,ticket);
   if(!trade.PositionClose(ticket) ||
      (trade.ResultRetcode()!=TRADE_RETCODE_DONE &&
       trade.ResultRetcode()!=TRADE_RETCODE_DONE_PARTIAL))
   {
      MGSLog("EXIT_RESULT",why+" FAILED",ticket,0,0,trade.ResultRetcode());
      Print("EXIT FAILED [",why,"] ticket=",ticket," code=",trade.ResultRetcodeDescription());
      return false;
   }
   bool flat=!PositionSelectByTicket(ticket);
   MGSLog("EXIT_RESULT",why+(flat?" FLAT":" RESIDUAL"),ticket,0,0,trade.ResultRetcode());
   if(InpLogDecisions)
      Print("EXIT [",why,"] ticket=",ticket," flat=",flat,
            " retcode=",trade.ResultRetcode());
   // A partial close retains its close intent and is retried after throttling.
   return flat;
}

// Reconcile the exact order and enumerate owned tickets; never infer ownership
// from PositionSelect(symbol), which chooses a ticket on hedging accounts.
// An unknown outcome survives restart. Absence of a position alone is NOT proof
// that a timed-out request cannot subsequently execute.
void ReconcileFlight()
{
   if(!InFlight() || gSubmitting || gFlightOrder==0) return;
   bool active=OrderSelect(gFlightOrder);
   if(!active && !HistoryOrderSelect(gFlightOrder)) return;
   string symbol=(active?OrderGetString(ORDER_SYMBOL):HistoryOrderGetString(gFlightOrder,ORDER_SYMBOL));
   ulong magic=(ulong)(active?OrderGetInteger(ORDER_MAGIC):HistoryOrderGetInteger(gFlightOrder,ORDER_MAGIC));
   ulong identifier=(ulong)(active?OrderGetInteger(ORDER_POSITION_ID):
                                   HistoryOrderGetInteger(gFlightOrder,ORDER_POSITION_ID));
   if(symbol!=_Symbol || magic!=InpMagic) return;
   double observedVolume=0.0;
   bool protectionOK=true;
   for(int i=PositionsTotal()-1;i>=0;i--)
   {
      ulong ticket=PositionGetTicket(i);
      if(!OurPosition(ticket)) continue;
      if(identifier==0 || (ulong)PositionGetInteger(POSITION_IDENTIFIER)!=identifier) continue;
      double entry=PositionGetDouble(POSITION_PRICE_OPEN);
      double sl=PositionGetDouble(POSITION_SL);
      double volume=PositionGetDouble(POSITION_VOLUME);
      observedVolume+=volume;
      bool buy=((ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE)==POSITION_TYPE_BUY);
      double risk=0.0;
      bool valid=(sl>0.0 && gFlightBudget>0.0 &&
                  ProjectedLoss(buy?ORDER_TYPE_BUY:ORDER_TYPE_SELL,
                                volume,entry,sl,risk) && risk<=gFlightBudget+0.0001);
      if(!valid)
      {
         protectionOK=false;
         CloseWithReason(ticket,"POST-FILL PROTECTION/RISK RECONCILIATION");
         continue;
      }
      if(!GlobalVariableCheck(PositionRiskKey()))
         GlobalVariableSet(PositionRiskKey(),MathAbs(entry-sl));
   }
   if(!protectionOK || active) return;
   ENUM_ORDER_STATE state=(ENUM_ORDER_STATE)HistoryOrderGetInteger(gFlightOrder,ORDER_STATE);
   if(state!=ORDER_STATE_FILLED && state!=ORDER_STATE_CANCELED &&
      state!=ORDER_STATE_REJECTED && state!=ORDER_STATE_EXPIRED) return;
   double initial=HistoryOrderGetDouble(gFlightOrder,ORDER_VOLUME_INITIAL);
   double remaining=HistoryOrderGetDouble(gFlightOrder,ORDER_VOLUME_CURRENT);
   // A final historical order can appear before its position snapshot. Positive
   // matching identity/volume evidence is mandatory. A fast open-and-stop-out
   // before this observation intentionally needs operator review.
   bool zeroFill=(state!=ORDER_STATE_FILLED && initial>0 && initial==remaining && observedVolume==0);
   if(!zeroFill && !MGSFillVolumeMatches(initial,remaining,observedVolume,
                                         SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_STEP))) return;
   if(!SetFlight(false)) return;
   MGSLog("RECONCILED","FINAL ORDER AND MATCHING EXPOSURE",0,gFlightOrder);
   gFlightOrder=0;
   gFlightBudget=0.0;
}

void OnTradeTransaction(const MqlTradeTransaction &trans,
                        const MqlTradeRequest &request,
                        const MqlTradeResult &result)
{
   if(trans.symbol==_Symbol)
      MGSLog("TRANSACTION",EnumToString(trans.type),trans.position,trans.order,trans.deal,
             result.retcode,trans.volume,trans.price,trans.price_sl,trans.price_tp);
   ReconcileFlight();
}

// TRADE MANAGEMENT ---------------------------------------------------
void ManagePositions(bool closeForHalt)
{
   if(!InpEnableDemoOrders || !DemoEnvironment()) return;
   MqlTick q;
   if(!SymbolInfoTick(_Symbol,q) || q.bid<=0 || q.ask<=0) return;
   double atr=0.0;
   bool atrReady=(ReadIndicator(hAtr,1,atr) && atr>0.0);
   double minDistance=(MathMax((double)SymbolInfoInteger(_Symbol,SYMBOL_TRADE_STOPS_LEVEL),
                               (double)SymbolInfoInteger(_Symbol,SYMBOL_TRADE_FREEZE_LEVEL))+2.0)*_Point;
   for(int i=PositionsTotal()-1;i>=0;i--)
   {
      ulong ticket=PositionGetTicket(i);
      if(!OurPosition(ticket)) continue;
      if(InFlight() && gFlightOrder==0)
      {
         CloseWithReason(ticket,"UNKNOWN SUBMISSION STATE AFTER RESTART/TIMEOUT");
         continue;
      }
      if(closeForHalt)
      {
         CloseWithReason(ticket,"DAILY HALT");
         continue;
      }
      if(GlobalVariableCheck(PositionForceCloseKey()) &&
         GlobalVariableGet(PositionForceCloseKey())>0.5)
      {
         CloseWithReason(ticket,"PERSISTENT CLOSE INTENT");
         continue;
      }
      double oldSL=PositionGetDouble(POSITION_SL);
      if(oldSL<=0.0)
      {
         Print("EMERGENCY: owned position without broker SL, closing ticket ",ticket);
         CloseWithReason(ticket,"NO PROTECTIVE SL");
         continue;
      }
      bool buy=((ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE)==POSITION_TYPE_BUY);
      double lots=PositionGetDouble(POSITION_VOLUME);
      double entry=PositionGetDouble(POSITION_PRICE_OPEN);
      double swap=PositionGetDouble(POSITION_SWAP);
      double tp=PositionGetDouble(POSITION_TP);
      double current=(buy?q.bid:q.ask);
      int heldSeconds=(int)(TimeCurrent()-(datetime)PositionGetInteger(POSITION_TIME));
      if(InpMaxHoldingSeconds>0 && heldSeconds>=InpMaxHoldingSeconds)
      {
         CloseWithReason(ticket,"TIME LIMIT");
         continue;
      }
      double netNow=0.0;
      if(!EstimateNetExit(buy,lots,entry,current,swap,false,netNow)) continue;

      if(InpExitMode==MGS_EXIT_FIXED_CASH && netNow>=InpCashTakeProfit)
      {
         CloseWithReason(ticket,"NET CASH TARGET");
         continue;
      }

      double candidate=oldSL;
      bool cashTriggered=false,cashFound=false,cashLegal=false,cashImproves=false;
      double desiredCash=0.0,cashStop=0.0,cashEstimated=0.0;
      string cashStatus="NOT_TRIGGERED";
      // Money-based trailing never loosens the original SL.
      if(InpExitMode==MGS_EXIT_CASH_LOCK || InpExitMode==MGS_EXIT_HYBRID)
      {
         string key=PositionPeakNetKey();
         double peak=(GlobalVariableCheck(key)?GlobalVariableGet(key):0.0);
         if(netNow>peak)
         {
            peak=netNow;
            GlobalVariableSet(key,peak);
         }
         if(peak>=InpCashLockTrigger)
         {
            cashTriggered=true;
            desiredCash=MathMax(InpCashLockMinNet,peak*InpCashLockKeepPct/100.0);
            cashFound=CashStopPrice(buy,lots,entry,swap,desiredCash,cashStop);
            cashStatus=(cashFound?"TARGET_FOUND":"SEARCH_FAILED");
            if(cashFound)
            {
               cashLegal=(buy?cashStop<=current-minDistance:cashStop>=current+minDistance);
               cashImproves=(buy?cashStop>oldSL:cashStop<oldSL);
               if(!cashLegal) cashStatus="REJECTED_DISTANCE";
               else if(!cashImproves) cashStatus="ALREADY_PROTECTED";
               double proposed=MGSConsiderStop(candidate,cashStop,buy,oldSL,current,minDistance,TickSize());
               double projectedNet=0.0;
               if(EstimateNetExit(buy,lots,entry,proposed,swap,true,projectedNet) &&
                  projectedNet+1e-8>=desiredCash)
               {
                  candidate=proposed;
                  if(cashLegal && cashImproves) cashStatus="LEGAL_CANDIDATE";
               }
               else if(cashLegal && cashImproves) cashStatus="TARGET_RECHECK_FAILED";
               EstimateNetExit(buy,lots,entry,cashStop,swap,true,cashEstimated);
            }
         }
      }
      // The legacy R/ATR-based stops remain available as a CONTROL, or in HYBRID.
      if(atrReady && (InpExitMode==MGS_EXIT_LEGACY_R || InpExitMode==MGS_EXIT_HYBRID))
      {
         string riskKey=PositionRiskKey();
         if(!GlobalVariableCheck(riskKey))
         {
            // Never reconstruct original risk from a stop already moved.
            if(InpLogDecisions)
               Print("Missing initial-risk key, R-based trailing suspended ticket=",ticket);
         }
         else
         {
            double initialRisk=GlobalVariableGet(riskKey);
            if(initialRisk>0.0)
            {
               double favourable=(buy?current-entry:entry-current);
               if(favourable>=InpBreakEvenR*initialRisk)
               {
                  double be=BreakevenPrice(buy,entry,lots,swap);
                  candidate=MGSConsiderStop(candidate,be,buy,oldSL,current,minDistance,TickSize());
               }
               if(favourable>=InpTrailStartR*initialRisk)
               {
                  double trail=(buy?q.bid-InpTrailATR*atr:q.ask+InpTrailATR*atr);
                  candidate=MGSConsiderStop(candidate,trail,buy,oldSL,current,minDistance,TickSize());
               }
            }
         }
      }
      candidate=SnapPrice(candidate);
      double step=InpMinModifyTicks*TickSize();
      bool improved=(buy?candidate>oldSL+step:candidate<oldSL-step);
      bool legal=(buy?candidate<=q.bid-minDistance:candidate>=q.ask+minDistance);
      string modKey=PositionModifyKey();
      string diagKey=Prefix()+"diag_"+(string)PositionGetInteger(POSITION_IDENTIFIER);
      if(cashTriggered && !GlobalVariableCheck(diagKey))
      {
         if(cashStatus=="LEGAL_CANDIDATE" &&
            (buy?candidate>cashStop+TickSize()*1e-7:candidate<cashStop-TickSize()*1e-7))
            cashStatus="DOMINATED_BY_R_ATR";
         if(cashFound && cashLegal && cashImproves && !improved)
            cashStatus+=";MIN_MODIFY_STEP";
         bool cooldownReady=(!GlobalVariableCheck(modKey) ||
            TimeCurrent()-(datetime)GlobalVariableGet(modKey)>=MathMax(1,InpMinModifySeconds));
         if(cashFound && cashLegal && cashImproves && !cooldownReady)
            cashStatus+=";MODIFY_COOLDOWN";
         double tick=TickSize(),sign=(buy?1.0:-1.0),gain1=0.0,gain100=0.0;
         ENUM_ORDER_TYPE side=(buy?ORDER_TYPE_BUY:ORDER_TYPE_SELL);
         bool oneOK=OrderCalcProfit(side,_Symbol,lots,entry,entry+sign*tick,gain1);
         bool hundredOK=(entry+sign*100.0*tick>0.0 &&
            OrderCalcProfit(side,_Symbol,lots,entry,entry+sign*100.0*tick,gain100));
         string detail=StringFormat("probe1_ok=%s;probe1_gain=%.8f;probe100_ok=%s;probe100_gain=%.8f;probe100_per_tick=%.8f;target=%.8f;cash_stop=%.8f;cash_net=%.8f;status=%s;chosen_stop=%.8f;min_distance=%.8f;tick=%.8f;modify_improved=%s;modify_legal=%s;cooldown_ready=%s",
            oneOK?"true":"false",gain1,hundredOK?"true":"false",gain100,gain100/100.0,
            desiredCash,cashStop,cashEstimated,cashStatus,candidate,minDistance,tick,
            improved?"true":"false",legal?"true":"false",cooldownReady?"true":"false");
         MGSLog("CASH_DIAGNOSTIC",detail,ticket,0,0,0,lots,entry,cashStop,tp);
         if(InpLogDecisions) Print("CASH_DIAGNOSTIC ticket=",ticket," ",detail);
         GlobalVariableSet(diagKey,(double)TimeCurrent());
      }
      if(improved && legal &&
         TradeAttemptDue(modKey,MathMax(1,InpMinModifySeconds)))
      {
         if(!trade.PositionModify(ticket,candidate,tp) ||
            trade.ResultRetcode()!=TRADE_RETCODE_DONE)
         {
            MGSLog("MODIFY_RESULT","REJECTED",ticket,0,0,trade.ResultRetcode(),lots,entry,candidate,tp);
            Print("SL update rejected ticket=",ticket,": ",trade.ResultRetcodeDescription());
         }
         else
         {
            MGSLog("MODIFY_RESULT","ACCEPTED",ticket,0,0,trade.ResultRetcode(),lots,entry,candidate,tp);
            if(InpLogDecisions)
               PrintFormat("SL LOCK ticket=%I64u old=%.*f new=%.*f peakNowNet=%.2f held=%d sec",
                           ticket,_Digits,oldSL,_Digits,candidate,netNow,heldSeconds);
         }
      }
   }
}

// Fixed ten-second buckets from observed quotes, not a lossless tick replay.
// Mid-price still changes when one quote side widens. Empty buckets reset
// continuity; initial/reconnect partial buckets cannot produce a signal.
void UpdateSynthetic10s()
{
   gTenBarClosed=false;
   MqlTick q;
   if(!SymbolInfoTick(_Symbol,q)) return;
   long stamp=(q.time_msc>0?q.time_msc:(long)q.time*1000);
   gTenBarClosed=MGSFeedTen(gTenState,stamp,q.bid,q.ask,TickSize());
   gPrevTenDir=gTenState.previousDirection;
   gLastTenDir=gTenState.lastDirection;
   gLastTenRange=gTenState.lastRange;
}

bool FastTenSignal(int &direction,double atr)
{
   direction=0;
   if(!gTenBarClosed || gLastTenDir==0) return true;
   if(Inp10sRequireTwoBars && gPrevTenDir!=gLastTenDir) return true;
   MqlTick q;
   if(!SymbolInfoTick(_Symbol,q)) return false;
   if(gLastTenRange<(q.ask-q.bid)*Inp10sMinRangeSpreadMult ||
      gLastTenRange>atr*0.90) return true;
   double e5,e20,e40,e5M5,e20M5,e40M5,sar1,sar5;
   if(!ReadIndicator(hEma5M1,1,e5) || !ReadIndicator(hEma20M1,1,e20) ||
      !ReadIndicator(hEma40M1,1,e40) || !ReadIndicator(hEma5M5,1,e5M5) ||
      !ReadIndicator(hEma20M5,1,e20M5) || !ReadIndicator(hEma40M5,1,e40M5) ||
      !ReadIndicator(hSarM1,1,sar1) || !ReadIndicator(hSarM5,1,sar5)) return false;
   double close1=iClose(_Symbol,PERIOD_M1,1);
   double close5=iClose(_Symbol,PERIOD_M5,1);
   bool bull=e5>e20 && e20>e40 && e5M5>e20M5 && e20M5>e40M5 &&
             close1>sar1 && close5>sar5;
   bool bear=e5<e20 && e20<e40 && e5M5<e20M5 && e20M5<e40M5 &&
             close1<sar1 && close5<sar5;
   if(bull && gLastTenDir==1) direction=1;
   if(bear && gLastTenDir==-1) direction=-1;
   return true;
}

// Fibonacci is measured only from COMPLETED M5 bars. Swing chronology matters.
// BUY: latest high formed after latest low, price retraces into 38.2%-61.8% zone.
// SELL: latest low formed after latest high, price bounces into zone.
bool FibSignal(int &direction)
{
   direction=0;
   int highest=iHighest(_Symbol,PERIOD_M5,MODE_HIGH,InpFibLookbackM5,1);
   int lowest=iLowest(_Symbol,PERIOD_M5,MODE_LOW,InpFibLookbackM5,1);
   if(highest<0 || lowest<0 || highest==lowest) return false;
   double high=iHigh(_Symbol,PERIOD_M5,highest);
   double low=iLow(_Symbol,PERIOD_M5,lowest);
   if(high<=low) return true;
   double ema20,ema50,ema15=0.0,rsi;
   if(!ReadIndicator(hEma20M5,1,ema20) || !ReadIndicator(hEma50M5,1,ema50) ||
      !ReadIndicator(hRsi,1,rsi)) return false;
   if(InpFibRequireM15Confirmation && !ReadIndicator(hEma50M15,1,ema15)) return false;
   MqlTick quote;
   if(!SymbolInfoTick(_Symbol,quote)) return false;
   double close=iClose(_Symbol,PERIOD_M1,1),open=iOpen(_Symbol,PERIOD_M1,1);
   double prevClose=iClose(_Symbol,PERIOD_M1,2);
   double m15=iClose(_Symbol,PERIOD_M15,1);
   double range=high-low;
   double buyLower=high-0.618*range,buyUpper=high-0.382*range;
   double sellLower=low+0.382*range,sellUpper=low+0.618*range;
   bool bull=highest<lowest && ema20>ema50 &&
             (!InpFibRequireM15Confirmation || m15>ema15) &&
             close>=buyLower && close<=buyUpper && close>open &&
             close>prevClose && rsi>=50.0 && rsi<75.0;
   bool bear=lowest<highest && ema20<ema50 &&
             (!InpFibRequireM15Confirmation || m15<ema15) &&
             close>=sellLower && close<=sellUpper && close<open &&
             close<prevClose && rsi<=50.0 && rsi>25.0;
   if(bull && MGSInZone(quote.ask,buyLower,buyUpper))
   { direction=1; gSignalZoneLower=buyLower; gSignalZoneUpper=buyUpper; }
   if(bear && MGSInZone(quote.bid,sellLower,sellUpper))
   { direction=-1; gSignalZoneLower=sellLower; gSignalZoneUpper=sellUpper; }
   return true;
}

// Optional OB confluence: at least one prior M5 counter-direction candle
// touching the FVG zone. This is a transparent approximation, not a proof
// that actual institutional order flow exists.
bool HasOBOverlap(bool buy,double gapLo,double gapHi,int formedShift)
{
   for(int j=formedShift+2;j<=formedShift+InpOBLookbackBars+2;j++)
   {
      double o=iOpen(_Symbol,PERIOD_M5,j),c=iClose(_Symbol,PERIOD_M5,j);
      double hi=iHigh(_Symbol,PERIOD_M5,j),lo=iLow(_Symbol,PERIOD_M5,j);
      if(o<=0 || c<=0) break;
      if((buy && c<o) || (!buy && c>o))
      {
         if(hi>=gapLo && lo<=gapHi) return true;
      }
   }
   return false;
}

// Detect a three-CLOSED-candle fair value gap on M5; enter on M1 candle
// reversal when price revisits the zone. EMA bias on M5 and H1.
bool FVGSignal(int &direction)
{
   direction=0;
   double m5Fast,m5Slow,h1Fast,h1Slow,atr5;
   if(!ReadIndicator(hEma20M5,1,m5Fast) || !ReadIndicator(hEma50M5,1,m5Slow) ||
      !ReadIndicator(hEma50H1,1,h1Fast) || !ReadIndicator(hEma200H1,1,h1Slow) ||
      !ReadIndicator(hAtrM5,1,atr5)) return false;
   double closeM1=iClose(_Symbol,PERIOD_M1,1);
   double openM1=iOpen(_Symbol,PERIOD_M1,1);
   MqlTick tick;
   if(!SymbolInfoTick(_Symbol,tick)) return false;
   for(int k=1;k<=InpFVGMaxAgeM5Bars;k++)
   {
      double olderHi=iHigh(_Symbol,PERIOD_M5,k+2);
      double olderLo=iLow(_Symbol,PERIOD_M5,k+2);
      double newerHi=iHigh(_Symbol,PERIOD_M5,k);
      double newerLo=iLow(_Symbol,PERIOD_M5,k);
      double midO=iOpen(_Symbol,PERIOD_M5,k+1);
      double midC=iClose(_Symbol,PERIOD_M5,k+1);
      if(olderHi<=0 || olderLo<=0 || newerHi<=0 || newerLo<=0) return false;
      double impulse=MathAbs(midC-midO);
      if(impulse<InpFVGMinImpulseATR*atr5) continue;
      bool bull=(olderHi<newerLo && midC>midO && m5Fast>m5Slow && h1Fast>h1Slow);
      bool bear=(olderLo>newerHi && midC<midO && m5Fast<m5Slow && h1Fast<h1Slow);
      if(bull)
      {
         double gapLo=olderHi,gapHi=newerLo;
         if(InpFVGRequireOrderBlock && !HasOBOverlap(true,gapLo,gapHi,k)) continue;
         if(MGSInZone(tick.ask,gapLo,gapHi) && closeM1>openM1)
         { direction=1; gSignalZoneLower=gapLo; gSignalZoneUpper=gapHi; return true; }
      }
      if(bear)
      {
         double gapLo=newerHi,gapHi=olderLo;
         if(InpFVGRequireOrderBlock && !HasOBOverlap(false,gapLo,gapHi,k)) continue;
         if(MGSInZone(tick.bid,gapLo,gapHi) && closeM1<openM1)
         { direction=-1; gSignalZoneLower=gapLo; gSignalZoneUpper=gapHi; return true; }
      }
   }
   return true;
}

// SIGNALS -----------------------------------------------------------
// Intentionally retains V0.3's completed-M1-bar EMA baseline for A/B tests.
// No claims that these indicators predict winning trades.
bool RangeBreakoutSignal(int &direction,double atr)
{
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(),dt);
   if(dt.hour<InpBORangeEndHour || dt.hour>=InpBOLastEntryHour) return true;
   dt.hour=0; dt.min=0; dt.sec=0;
   datetime midnight=StructToTime(dt);
   datetime from=midnight+InpBORangeStartHour*3600;
   datetime to=midnight+InpBORangeEndHour*3600-1;
   MqlRates m15[];
   int expected=(InpBORangeEndHour-InpBORangeStartHour)*4;
   int got=CopyRates(_Symbol,PERIOD_M15,from,to,m15);
   if(got!=expected) return false;  // full closed range required, no future OHLC
   double hi=m15[0].high, lo=m15[0].low;
   for(int i=1;i<got;i++)
   {
      hi=MathMax(hi,m15[i].high);
      lo=MathMin(lo,m15[i].low);
   }
   MqlRates m1[];
   ArraySetAsSeries(m1,true);
   if(CopyRates(_Symbol,PERIOD_M1,0,4,m1)!=4) return false;
   double pad=InpBOBreakoutBufferATR*atr;
   if(m1[2].close<=hi+pad && m1[1].close>hi+pad) direction=1;
   if(m1[2].close>=lo-pad && m1[1].close<lo-pad) direction=-1;
   return true;
}

bool Signal(int &direction,double &atr)
{
   direction=0;
   gSignalZoneLower=0.0; gSignalZoneUpper=0.0;
   if(!ReadIndicator(hAtr,1,atr)||atr<=0.0) return false;
   if(InpMode==MGS_RANGE_BREAKOUT) return RangeBreakoutSignal(direction,atr);
   if(InpMode==MGS_EMA_PSAR_10S) return FastTenSignal(direction,atr);
   if(InpMode==MGS_FIB_EMA) return FibSignal(direction);
   if(InpMode==MGS_FVG_OB) return FVGSignal(direction);
   int needed=MathMax(InpStructureLookback+4,20);
   MqlRates bars[];
   ArraySetAsSeries(bars,true);
   if(CopyRates(_Symbol,PERIOD_M1,0,needed,bars)<needed) return false;
   double e9_1,e9_2,e21_1,e20_5=0.0,e50_5=0.0,rsi=0.0;
   if(!ReadIndicator(hEma9,1,e9_1) || !ReadIndicator(hEma9,2,e9_2) ||
      !ReadIndicator(hEma21,1,e21_1)) return false;
   if(InpMode!=MGS_EMA_BASELINE &&
      (!ReadIndicator(hEma20M5,1,e20_5) || !ReadIndicator(hEma50M5,1,e50_5) ||
       !ReadIndicator(hRsi,1,rsi))) return false;
   bool buy=e9_1>e21_1 && bars[2].low<=e9_2 &&
            bars[1].close>bars[2].high && bars[1].close>e9_1;
   bool sell=e9_1<e21_1 && bars[2].high>=e9_2 &&
             bars[1].close<bars[2].low && bars[1].close<e9_1;
   if(InpMode>=MGS_EMA_RSI_M5)
   {
      buy=buy && e20_5>e50_5 && rsi>=InpRSIBuyAbove && rsi<=InpRSIUpperLimit;
      sell=sell && e20_5<e50_5 && rsi<=InpRSISellBelow && rsi>=InpRSILowerLimit;
   }
   if(InpMode==MGS_ADVANCED && (buy||sell))
   {
      double adx,plusDI,minusDI;
      if(!ReadIndicator(hAdxM5,1,adx,0) ||
         !ReadIndicator(hAdxM5,1,plusDI,1) ||
         !ReadIndicator(hAdxM5,1,minusDI,2)) return false;
      double range=bars[1].high-bars[1].low;
      double body=MathAbs(bars[1].close-bars[1].open);
      bool strong=(range>0 && range>=InpMinImpulseRangeATR*atr &&
                   body/range>=InpMinCandleBodyFraction);
      double pastHigh=bars[3].high, pastLow=bars[3].low;
      for(int i=4;i<InpStructureLookback+3;i++)
      {
         pastHigh=MathMax(pastHigh,bars[i].high);
         pastLow=MathMin(pastLow,bars[i].low);
      }
      bool bosBuy=bars[1].close>pastHigh, bosSell=bars[1].close<pastLow;
      bool roomBuy=(pastHigh<=bars[1].close ||
                    pastHigh-bars[1].close>=InpMinRoomToLevelATR*atr);
      bool roomSell=(pastLow>=bars[1].close ||
                     bars[1].close-pastLow>=InpMinRoomToLevelATR*atr);
      int buyExtras=((adx>=InpADXMinimum && plusDI>minusDI)?1:0)+(strong?1:0)+(bosBuy?1:0);
      int sellExtras=((adx>=InpADXMinimum && minusDI>plusDI)?1:0)+(strong?1:0)+(bosSell?1:0);
      buy=buy && buyExtras>=InpRequiredAdvancedExtras && (!InpCheckSRRoom || roomBuy);
      sell=sell && sellExtras>=InpRequiredAdvancedExtras && (!InpCheckSRRoom || roomSell);
   }
   if(buy) direction=1;
   if(sell) direction=-1;
   return true;
}

// ENTRY: reject entire setup whenever 0.01 lot would risk too much.
void TryEnter(int direction,double atr)
{
   if(direction==0 || InFlight() || DailyHalt() || HasAnySymbolPosition() || !CanUseAccount())
   { MGSLog("SKIP","ENTRY STATE/EXPOSURE GUARD"); return; }
   if(InpCSVLog && gLogHandle==INVALID_HANDLE) return;
   if(!DemoEnvironment() && InpEnableDemoOrders) return;
   MqlTick q;
   if(!SymbolInfoTick(_Symbol,q) || q.ask<=q.bid)
   { MGSLog("SKIP","INVALID QUOTE"); return; }
   double spread=q.ask-q.bid;
   if(spread>InpMaxSpreadATR*atr ||
      spread>InpMaxSpreadPoints*_Point) { MGSLog("SKIP","SPREAD"); return; }
   double prevM1Range=iHigh(_Symbol,PERIOD_M1,1)-iLow(_Symbol,PERIOD_M1,1);
   if(prevM1Range>InpMaxM1SpikeATR*atr) { MGSLog("SKIP","PREVIOUS M1 SPIKE"); return; }
   bool buy=(direction==1);
   ENUM_ORDER_TYPE side=(buy?ORDER_TYPE_BUY:ORDER_TYPE_SELL);
   double entry=(buy?q.ask:q.bid);
   if((InpMode==MGS_FIB_EMA || InpMode==MGS_FVG_OB) &&
      !MGSInZone(entry,gSignalZoneLower,gSignalZoneUpper))
   { MGSLog("SKIP","EXECUTABLE QUOTE LEFT SIGNAL ZONE"); return; }
   double minDistance=(SymbolInfoInteger(_Symbol,SYMBOL_TRADE_STOPS_LEVEL)+3.0)*_Point;
   double stopWidth=MathMax(InpStopATR*atr,spread+3.0*TickSize());
   double sl=NormalizeDouble(MGSSnapStop(buy?MathMin(entry-stopWidth,q.bid-minDistance)
                           :MathMax(entry+stopWidth,q.ask+minDistance),TickSize(),buy),_Digits);
   if(sl<=0.0 || (buy && sl>q.bid-minDistance+TickSize()*1e-7) ||
      (!buy && sl<q.ask+minDistance-TickSize()*1e-7)) return;
   double riskAtMin=0.0;
   double minLot=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MIN);
   double maxLot=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MAX);
   double step=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_STEP);
   if(minLot<=0 || step<=0 || maxLot<=0 || InpMaxLots<minLot) return;
   if(!ProjectedLoss(side,minLot,entry,sl,riskAtMin)) return;
   double equity=AccountInfoDouble(ACCOUNT_EQUITY);
   double riskFloor=AccountRiskFloor();
   double budget=MGSRiskBudget(equity,InpRiskCash,InpRiskPct,riskFloor);
   if(budget<=0 || riskAtMin>budget+1e-7)
   {
      MGSLog("SKIP","MINIMUM LOT EXCEEDS BUDGET",0,0,0,0,minLot,entry,sl,0,riskAtMin,budget);
      if(InpLogDecisions)
         PrintFormat("NO TRADE: min lot %.3f risk %.3f %s > allowed %.3f; equity %.2f",
                     minLot,riskAtMin,AccountInfoString(ACCOUNT_CURRENCY),budget,equity);
      return;
   }
   double rawLots=minLot*budget/riskAtMin;
   double cap=MathMin(InpMaxLots,maxLot);
   double volume=MGSVolumeFloor(rawLots,minLot,maxLot,step,cap);
   volume=NormalizeDouble(volume,8);
   double risk=0.0;
   if(volume<minLot || volume>cap+1e-8 || !ProjectedLoss(side,volume,entry,sl,risk) ||
      risk>budget+1e-7) return;
   double margin=0.0;
   if(!OrderCalcMargin(side,_Symbol,volume,entry,margin)) return;
   if(margin>AccountInfoDouble(ACCOUNT_MARGIN_FREE)*InpMaxMarginPctFree/100.0) return;
   double tp=0.0; // trailing-only by default; broker-side stop loss is ALWAYS set
   if(InpUseFixedTP)
      tp=SnapPrice(buy?entry+InpTargetR*MathAbs(entry-sl):entry-InpTargetR*MathAbs(entry-sl));
   if(InpLogDecisions)
      PrintFormat("CANDIDATE: %s %s lots=%.3f price=%.*f SL=%.*f TP=%.*f risk<=%.2f %s",
                  _Symbol,buy?"BUY":"SELL",volume,_Digits,entry,_Digits,sl,_Digits,tp,
                  risk,AccountInfoString(ACCOUNT_CURRENCY));
   MGSLog("CANDIDATE",InpEnableDemoOrders?"DEMO ORDERS ENABLED":"OBSERVE ONLY",0,0,0,0,volume,entry,sl,tp,risk,budget);
   if(!InpEnableDemoOrders) return;
   if(!DemoEnvironment()) return; // hard live/contest account block
   // Final guard immediately before submitting an order, accounting for prospective SL risk.
   if(InFlight() || DailyHalt() || AccountInfoDouble(ACCOUNT_EQUITY)-risk<AccountRiskFloor()-1e-7 ||
      HasAnySymbolPosition() || !CanUseAccount()) return;
   MqlTradeRequest request={};
   MqlTradeCheckResult check={};
   MqlTradeResult result={};
   request.action=TRADE_ACTION_DEAL;
   request.magic=InpMagic;
   request.symbol=_Symbol;
   request.volume=volume;
   request.type=side;
   request.price=entry;
   request.sl=sl;
   request.tp=tp;
   request.deviation=(ulong)InpDeviationPoints;
   request.comment="MGS V062 CASHFIX DEMO";
   long filling=SymbolInfoInteger(_Symbol,SYMBOL_FILLING_MODE);
   ENUM_SYMBOL_TRADE_EXECUTION execution=(ENUM_SYMBOL_TRADE_EXECUTION)
      SymbolInfoInteger(_Symbol,SYMBOL_TRADE_EXEMODE);
   if((filling & SYMBOL_FILLING_FOK)!=0) request.type_filling=ORDER_FILLING_FOK;
   else if((filling & SYMBOL_FILLING_IOC)!=0) request.type_filling=ORDER_FILLING_IOC;
   else if(execution!=SYMBOL_TRADE_EXECUTION_MARKET) request.type_filling=ORDER_FILLING_RETURN;
   else { Print("ENTRY SKIP: no supported market filling policy."); return; }
   if(!OrderCheck(request,check) || (check.retcode!=0 && check.retcode!=TRADE_RETCODE_DONE))
   {
      MGSLog("PREFLIGHT_FAILED",check.comment,0,0,0,check.retcode,volume,entry,sl,tp,risk,budget);
      Print("ENTRY PREFLIGHT FAILED retcode=",check.retcode," comment=",check.comment);
      return;
   }
   // Save quarantine BEFORE submitting: crashes/timeouts must not permit retries.
   gFlightBudget=budget;
   gFlightOrder=0;
   if(!SetFlight(true)) return;
   gSubmitting=true;
   bool sent=OrderSend(request,result);
   gSubmitting=false;
   gFlightOrder=result.order;
   MGSLog("ENTRY_RESULT",result.comment,0,result.order,result.deal,result.retcode,volume,entry,sl,tp,risk,budget);
   Print("ENTRY RESULT sent=",sent," order=",result.order," deal=",result.deal,
         " retcode=",result.retcode," comment=",result.comment);
   bool definitiveReject=(result.retcode==TRADE_RETCODE_REQUOTE ||
      result.retcode==TRADE_RETCODE_REJECT || result.retcode==TRADE_RETCODE_INVALID ||
      result.retcode==TRADE_RETCODE_INVALID_VOLUME || result.retcode==TRADE_RETCODE_INVALID_PRICE ||
      result.retcode==TRADE_RETCODE_INVALID_STOPS || result.retcode==TRADE_RETCODE_TRADE_DISABLED ||
      result.retcode==TRADE_RETCODE_MARKET_CLOSED || result.retcode==TRADE_RETCODE_NO_MONEY ||
      result.retcode==TRADE_RETCODE_PRICE_CHANGED || result.retcode==TRADE_RETCODE_PRICE_OFF ||
      result.retcode==TRADE_RETCODE_INVALID_FILL);
   if(definitiveReject && result.order==0 && result.deal==0)
   {
      SetFlight(false);
      gFlightBudget=0.0;
      return;
   }
   ReconcileFlight();
   if(InFlight())
      Print("ENTRY QUARANTINE: awaiting proven final order state; no automatic resubmission.");
}

int OnInit()
{
   if((int)InpMode<0 || (int)InpMode>6 ||
      (int)InpExitMode<0 || (int)InpExitMode>3 ||
      InpCashTakeProfit<=0.0 || InpCashLockTrigger<=0.0 ||
      InpCashLockKeepPct<=0.0 || InpCashLockKeepPct>=100.0 ||
      InpCashLockMinNet<0.0 || InpMaxHoldingSeconds<0 || InpMaxHoldingSeconds>3600 ||
      InpRiskCash<=0.0 || InpRiskCash>15.0 || InpRiskPct<=0.0 || InpRiskPct>1.5 ||
      !InpRequireExclusiveAccount || InpDeviationPoints<0 ||
      InpDayLossPct<=0.0 || InpDayLossPct>5.0 ||
      InpMaxSpreadPoints<=0 || InpMaxM1SpikeATR<1.0 ||
      Inp10sMinRangeSpreadMult<0.0 || InpFibLookbackM5<10 || InpFibLookbackM5>200 ||
      InpFVGMaxAgeM5Bars<1 || InpFVGMaxAgeM5Bars>100 ||
      InpFVGMinImpulseATR<0.1 || InpOBLookbackBars<2 || InpOBLookbackBars>60 ||
      InpProfitLockActivatePct<=0.0 || InpProfitLockActivatePct>5.0 ||
      InpProfitKeepPct<=0.0 || InpProfitKeepPct>=100.0 ||
      InpMaxLots<=0.0 || InpMaxLots>0.01 || InpMaxMarginPctFree<=0.0 || InpMaxMarginPctFree>80.0 ||
      InpMaxTradesPerDay<1 || InpMaxTradesPerDay>300 ||
      InpRoundTripFeePerLot<0.0 || InpSlipReserveTicks<0.0 ||
      InpStopATR<=0 || InpTrailATR<=0 || InpMaxSpreadATR<=0 || InpTargetR<=0 ||
      InpBreakEvenR<=0 || InpTrailStartR<=0 || InpBEExtraTicks<0 ||
      InpMinModifyTicks<0 || InpMinModifySeconds<0 || InpMinSecondsBetweenEntries<0 ||
      InpAvoidRolloverMinutes<0 || InpAvoidRolloverMinutes>60 ||
      InpSession1Start<0 || InpSession1Start>23 || InpSession1End<0 || InpSession1End>24 ||
      InpSession2Start<0 || InpSession2Start>23 || InpSession2End<0 || InpSession2End>24 ||
      InpBORangeStartHour<0 || InpBORangeStartHour>22 ||
      InpBORangeEndHour<=InpBORangeStartHour || InpBORangeEndHour>23 ||
      InpBOLastEntryHour<=InpBORangeEndHour || InpBOLastEntryHour>24 ||
      InpBOBreakoutBufferATR<0 ||
      InpStructureLookback<4 || InpStructureLookback>200 ||
      InpRequiredAdvancedExtras<1 || InpRequiredAdvancedExtras>3 ||
      InpRSIUpperLimit<=InpRSIBuyAbove || InpRSILowerLimit>=InpRSISellBelow ||
      InpMinCandleBodyFraction<0 || InpMinCandleBodyFraction>1 ||
      InpMinRoomToLevelATR<0 || InpMinImpulseRangeATR<0)
      return INIT_PARAMETERS_INCORRECT;
   if(_Symbol!=InpExpectedSymbol)
   {
      Print("SAFETY: Wrong chart symbol: expected ",InpExpectedSymbol," actual ",_Symbol);
      return INIT_FAILED;
   }
   if(!DemoEnvironment() ||
      AccountInfoInteger(ACCOUNT_MARGIN_MODE)!=ACCOUNT_MARGIN_MODE_RETAIL_HEDGING)
   {
      Print("SAFETY: V062 CASHFIX requires a dedicated HEDGING DEMO account; live/contest/netting blocked.");
      return INIT_FAILED;
   }
   MGSResetTen(gTenState);
   if(!AcquireInstance()) return INIT_FAILED;
   gFlightKey=AccountPrefix()+"inflight";
   hEma9=iMA(_Symbol,PERIOD_M1,9,0,MODE_EMA,PRICE_CLOSE);
   hEma21=iMA(_Symbol,PERIOD_M1,21,0,MODE_EMA,PRICE_CLOSE);
   hEma20M5=iMA(_Symbol,PERIOD_M5,20,0,MODE_EMA,PRICE_CLOSE);
   hEma50M5=iMA(_Symbol,PERIOD_M5,50,0,MODE_EMA,PRICE_CLOSE);
   hRsi=iRSI(_Symbol,PERIOD_M1,14,PRICE_CLOSE);
   hAtr=iATR(_Symbol,PERIOD_M1,14);
   hAdxM5=iADX(_Symbol,PERIOD_M5,14);
   hEma5M1=iMA(_Symbol,PERIOD_M1,5,0,MODE_EMA,PRICE_CLOSE);
   hEma20M1=iMA(_Symbol,PERIOD_M1,20,0,MODE_EMA,PRICE_CLOSE);
   hEma40M1=iMA(_Symbol,PERIOD_M1,40,0,MODE_EMA,PRICE_CLOSE);
   hEma5M5=iMA(_Symbol,PERIOD_M5,5,0,MODE_EMA,PRICE_CLOSE);
   hEma40M5=iMA(_Symbol,PERIOD_M5,40,0,MODE_EMA,PRICE_CLOSE);
   hSarM1=iSAR(_Symbol,PERIOD_M1,0.02,0.20);
   hSarM5=iSAR(_Symbol,PERIOD_M5,0.02,0.20);
   hEma50M15=iMA(_Symbol,PERIOD_M15,50,0,MODE_EMA,PRICE_CLOSE);
   hEma50H1=iMA(_Symbol,PERIOD_H1,50,0,MODE_EMA,PRICE_CLOSE);
   hEma200H1=iMA(_Symbol,PERIOD_H1,200,0,MODE_EMA,PRICE_CLOSE);
   hAtrM5=iATR(_Symbol,PERIOD_M5,14);
   if(hEma5M1==INVALID_HANDLE || hEma20M1==INVALID_HANDLE ||
      hEma40M1==INVALID_HANDLE || hEma5M5==INVALID_HANDLE ||
      hEma40M5==INVALID_HANDLE || hSarM1==INVALID_HANDLE ||
      hSarM5==INVALID_HANDLE || hEma50M15==INVALID_HANDLE ||
      hEma50H1==INVALID_HANDLE || hEma200H1==INVALID_HANDLE ||
      hAtrM5==INVALID_HANDLE) return INIT_FAILED;
   if(hEma9==INVALID_HANDLE || hEma21==INVALID_HANDLE ||
      hEma20M5==INVALID_HANDLE || hEma50M5==INVALID_HANDLE ||
      hRsi==INVALID_HANDLE || hAtr==INVALID_HANDLE || hAdxM5==INVALID_HANDLE)
      return INIT_FAILED;
   trade.SetExpertMagicNumber(InpMagic);
   trade.SetDeviationInPoints(InpDeviationPoints);
   trade.SetTypeFillingBySymbol(_Symbol);
   trade.SetAsyncMode(false);
   // Each new tester run must start with independent day/peak/stop state.
   // Non-tester demo restarts retain persistent daily risk state.
   if(MQLInfoInteger(MQL_TESTER))
   {
      GlobalVariablesDeleteAll(Prefix());
      for(int i=GlobalVariablesTotal()-1;i>=0;i--)
      {
         string name=GlobalVariableName(i);
         if(StringFind(name,AccountPrefix())==0 && name!=gInstanceKey)
            GlobalVariableDel(name);
      }
   }
   if(!GlobalVariableCheck(gFlightKey)) GlobalVariableSet(gFlightKey,0.0);
   if(InFlight())
      Print("SAFETY: persistent entry quarantine restored. Reconcile broker orders/deals before an operator clears it.");
   OpenEventLog();
   RefreshDay();
   MGSLog("INITIALIZED","V062 CASHFIX CANDIDATE; NOT PERFORMANCE VALIDATED");
   PrintFormat("CONTRACT: minLots=%.3f maxLots=%.3f volumeStep=%.3f, tickSize=%.5f",
               SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MIN),
               SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MAX),
               SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_STEP),TickSize());
   PrintFormat("MGS V062 CASHFIX RESEARCH: %s mode=%d demoOrders=%s equity=%.2f %s; maxLots=%.3f risk=MIN(%.2f cash, %.2f%% equity), hardDayLoss=%.2f%% keepPeak=%.1f%%",
               _Symbol,(int)InpMode,InpEnableDemoOrders?"ON":"OFF",AccountInfoDouble(ACCOUNT_EQUITY),
               AccountInfoString(ACCOUNT_CURRENCY),InpMaxLots,InpRiskCash,InpRiskPct,InpDayLossPct,InpProfitKeepPct);
   PrintFormat("EXIT TEST: mode=%d cashTP=%.2f lockTrigger=%.2f keep=%.1f%% minNet=%.2f maxHold=%d sec",
               (int)InpExitMode,InpCashTakeProfit,InpCashLockTrigger,
               InpCashLockKeepPct,InpCashLockMinNet,InpMaxHoldingSeconds);
   Print("WARNING: NO AUTOMATIC ECONOMIC NEWS FILTER. DEMO ONLY. GBP 15 is a CAP, NOT REQUIRED LOSS. 0.01 LOT IS MAX, NOT FIXED. V062 CASHFIX unvalidated.");
   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
   MGSLog("DEINITIALIZED",(string)reason);
   if(gLogHandle!=INVALID_HANDLE) { FileClose(gLogHandle); gLogHandle=INVALID_HANDLE; }
   ReleaseInstance();
   GlobalVariablesFlush();
   if(hEma9!=INVALID_HANDLE) IndicatorRelease(hEma9);
   if(hEma21!=INVALID_HANDLE) IndicatorRelease(hEma21);
   if(hEma20M5!=INVALID_HANDLE) IndicatorRelease(hEma20M5);
   if(hEma50M5!=INVALID_HANDLE) IndicatorRelease(hEma50M5);
   if(hRsi!=INVALID_HANDLE) IndicatorRelease(hRsi);
   if(hAtr!=INVALID_HANDLE) IndicatorRelease(hAtr);
   if(hAdxM5!=INVALID_HANDLE) IndicatorRelease(hAdxM5);
   if(hEma5M1!=INVALID_HANDLE) IndicatorRelease(hEma5M1);
   if(hEma20M1!=INVALID_HANDLE) IndicatorRelease(hEma20M1);
   if(hEma40M1!=INVALID_HANDLE) IndicatorRelease(hEma40M1);
   if(hEma5M5!=INVALID_HANDLE) IndicatorRelease(hEma5M5);
   if(hEma40M5!=INVALID_HANDLE) IndicatorRelease(hEma40M5);
   if(hSarM1!=INVALID_HANDLE) IndicatorRelease(hSarM1);
   if(hSarM5!=INVALID_HANDLE) IndicatorRelease(hSarM5);
   if(hEma50M15!=INVALID_HANDLE) IndicatorRelease(hEma50M15);
   if(hEma50H1!=INVALID_HANDLE) IndicatorRelease(hEma50H1);
   if(hEma200H1!=INVALID_HANDLE) IndicatorRelease(hEma200H1);
   if(hAtrM5!=INVALID_HANDLE) IndicatorRelease(hAtrM5);
}

void OnTick()
{
   if(!DemoEnvironment()) return; // hard block all live-account execution
   if(TimeCurrent()!=gLastEquityLog)
   { gLastEquityLog=TimeCurrent(); MGSLog("EQUITY","OBSERVED; BROKER TIME"); }
   UpdateSynthetic10s();
   ReconcileFlight();
   bool halted=DailyHalt();
   ManagePositions(halted);        // positions handled on EVERY tick, not just M1 closes
   if(InpMode==MGS_EMA_PSAR_10S)
   {
      if(!gTenBarClosed) return;  // a single decision on each completed 10s bar
   }
   else
   {
      datetime bar=iTime(_Symbol,PERIOD_M1,0);
      if(bar==0 || bar==lastBar) return;
      lastBar=bar;
   }
   if(InFlight()) { MGSLog("SKIP","IN-FLIGHT QUARANTINE"); return; }
   if(halted) { MGSLog("SKIP","DAILY HALT"); return; }
   if(!SessionOK()) { MGSLog("SKIP","SESSION/ROLLOVER/BLACKOUT"); return; }
   if(HasAnySymbolPosition() || !CanUseAccount()) { MGSLog("SKIP","EXISTING/PENDING EXPOSURE"); return; }
   int today=TradesToday();
   if(today>=InpMaxTradesPerDay || (InpMode==MGS_RANGE_BREAKOUT && today>=1) ||
      !CooldownOK()) { MGSLog("SKIP","TRADE CEILING/COOLDOWN"); return; }
   int direction=0;
   double atr=0.0;
   if(!Signal(direction,atr)) { MGSLog("SKIP","SIGNAL DATA UNAVAILABLE"); return; }
   if(direction==0) { MGSLog("SKIP","NO SIGNAL"); return; }
   TryEnter(direction,atr);
}
