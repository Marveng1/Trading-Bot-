// Integer-tick monetary target search. No broker calls or single-tick ratios.
// Each observation must be the actual estimated net P/L at state.probe ticks.
#ifndef MGS_CASH_SEARCH_MQH
#define MGS_CASH_SEARCH_MQH
struct MGSCashSearch
{
   long lower;
   long upper;
   long probe;
   long maximum;
   int observations;
   bool bracketed;
   bool finished;
   bool failed;
};

bool MGSBeginCashSearch(MGSCashSearch &s,long maximum)
{
   s.lower=-1; s.upper=0; s.probe=0; s.maximum=maximum;
   s.observations=0; s.bracketed=false; s.finished=false; s.failed=false;
   if(maximum<0 || maximum>1000000)
   { s.finished=true; s.failed=true; return false; }
   return true;
}

void MGSObserveCashSearch(MGSCashSearch &s,double net,double target)
{
   if(s.finished) return;
   s.observations++;
   if(!MathIsValidNumber(net) || !MathIsValidNumber(target) || target<0 ||
      s.observations>64)
   { s.finished=true; s.failed=true; return; }
   if(net+1e-8>=target)
   { s.upper=s.probe; s.bracketed=true; }
   else s.lower=s.probe;
   if(s.bracketed)
   {
      if(s.upper-s.lower<=1) { s.finished=true; return; }
      s.probe=s.lower+(s.upper-s.lower)/2;
      return;
   }
   if(s.probe>=s.maximum) { s.finished=true; s.failed=true; return; }
   s.probe=(s.probe==0?1:s.probe*2);
   if(s.probe>s.maximum) s.probe=s.maximum;
}
#endif
