// Pure policy code shared by the EA and executable host tests.
// No broker, account, clock, filesystem or network calls.
#ifndef MGS_CORE_MQH
#define MGS_CORE_MQH

bool MGSInZone(double executablePrice,double lower,double upper)
{
   return MathIsValidNumber(executablePrice) && MathIsValidNumber(lower) &&
          MathIsValidNumber(upper) && lower>0 && upper>lower &&
          executablePrice>=lower && executablePrice<=upper;
}

bool MGSFillVolumeMatches(double initial,double remaining,double observed,double step)
{
   if(!MathIsValidNumber(initial) || !MathIsValidNumber(remaining) ||
      !MathIsValidNumber(observed) || !MathIsValidNumber(step) || initial<=0 ||
      remaining<0 || remaining>initial || observed<=0 || step<=0) return false;
   double filled=initial-remaining;
   return filled>0 && MathAbs(filled-observed)<=MathMax(1e-9,step*1e-6);
}

double MGSRiskBudget(double equity,double cashCap,double percent,double floor)
{
   if(!MathIsValidNumber(equity) || !MathIsValidNumber(cashCap) ||
      !MathIsValidNumber(percent) || !MathIsValidNumber(floor) ||
      equity<=0 || cashCap<=0 || percent<=0 || floor<0) return 0.0;
   return MathMax(0.0,MathMin(cashCap,MathMin(equity*percent/100.0,equity-floor)));
}

double MGSVolumeFloor(double raw,double minimum,double maximum,double step,double cap)
{
   if(!MathIsValidNumber(raw) || !MathIsValidNumber(minimum) ||
      !MathIsValidNumber(maximum) || !MathIsValidNumber(step) ||
      !MathIsValidNumber(cap) || minimum<=0 || step<=0 || maximum<minimum || cap<minimum)
      return 0.0;
   double volume=MathFloor(MathMin(raw,MathMin(maximum,cap))/step+1e-9)*step;
   if(volume<minimum-1e-10 || volume>raw+1e-10 || volume>cap+1e-10 ||
      volume>maximum+1e-10) return 0.0;
   return volume;
}

double MGSSnapStop(double price,double tick,bool buy)
{
   if(!MathIsValidNumber(price) || !MathIsValidNumber(tick) || price<=0 || tick<=0)
      return 0.0;
   return (buy?MathFloor(price/tick+1e-9):MathCeil(price/tick-1e-9))*tick;
}

// Consider each protection independently: an illegal tight cash lock must not
// suppress a different legal ATR/BE improvement. No promise of a cash lock is
// inferred from choosing a different candidate.
double MGSConsiderStop(double current,double proposed,bool buy,double oldStop,
                       double exitQuote,double minimumDistance,double tick)
{
   double snapped=MGSSnapStop(proposed,tick,buy);
   if(snapped<=0) return current;
   bool legal=(buy?snapped<=exitQuote-minimumDistance:
                    snapped>=exitQuote+minimumDistance);
   bool improved=(buy?snapped>oldStop:snapped<oldStop);
   if(!legal || !improved) return current;
   return (buy?MathMax(current,snapped):MathMin(current,snapped));
}

struct MGSTenState
{
   long bucketMsc;
   long lastTickMsc;
   bool active;
   bool observedFromPriorBucket;
   double open;
   double high;
   double low;
   double close;
   double lastRange;
   int previousDirection;
   int lastDirection;
};

void MGSResetTen(MGSTenState &s)
{
   s.bucketMsc=0; s.lastTickMsc=0; s.active=false;
   s.observedFromPriorBucket=false;
   s.open=0; s.high=0; s.low=0; s.close=0; s.lastRange=0;
   s.previousDirection=0; s.lastDirection=0;
}

// Empty intervals are not filled with artificial ticks. A gap resets signal
// continuity. Initial/reconnect partial buckets are discarded. Return true
// only when a usable prior bucket closes; current tick never enters its OHLC.
bool MGSFeedTen(MGSTenState &s,long timeMsc,double bid,double ask,double tick)
{
   if(timeMsc<=0 || bid<=0 || ask<=bid || tick<=0 ||
      !MathIsValidNumber(bid) || !MathIsValidNumber(ask) || !MathIsValidNumber(tick))
      return false;
   if(s.active && timeMsc<s.lastTickMsc) return false;
   long bucket=(timeMsc/10000)*10000;
   double mid=(bid+ask)/2.0;
   s.lastTickMsc=timeMsc;
   if(!s.active)
   {
      s.active=true; s.bucketMsc=bucket;
      s.open=mid; s.high=mid; s.low=mid; s.close=mid;
      return false;
   }
   if(bucket==s.bucketMsc)
   {
      s.high=MathMax(s.high,mid); s.low=MathMin(s.low,mid); s.close=mid;
      return false;
   }
   bool contiguous=(bucket-s.bucketMsc==10000);
   bool publish=(contiguous && s.observedFromPriorBucket);
   if(publish)
   {
      s.previousDirection=s.lastDirection;
      double diff=s.close-s.open;
      s.lastDirection=(diff>tick?1:(diff<-tick?-1:0));
      s.lastRange=s.high-s.low;
   }
   else
   {
      s.previousDirection=0; s.lastDirection=0; s.lastRange=0;
   }
   s.observedFromPriorBucket=contiguous;
   s.bucketMsc=bucket;
   s.open=mid; s.high=mid; s.low=mid; s.close=mid;
   return publish;
}
#endif
