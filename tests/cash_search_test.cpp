// Host tests of extracted EA functions and the actual shared MQL search header.
// OrderCalcProfit here is an explicit monetary-rounding MOCK, not MT5 execution.
#include <algorithm>
#include <cmath>
#include <iostream>
#include <limits>
#include <stdexcept>
#include <string>

double MathMin(double a,double b) { return std::min(a,b); }
double MathMax(double a,double b) { return std::max(a,b); }
double MathFloor(double x) { return std::floor(x); }
double MathCeil(double x) { return std::ceil(x); }
bool MathIsValidNumber(double x) { return std::isfinite(x); }
#include "MGSCashSearch.mqh"

enum ENUM_ORDER_TYPE { ORDER_TYPE_BUY, ORDER_TYPE_SELL };
const char* _Symbol="GOLD";
double InpRoundTripFeePerLot=7.0;
double InpSlipReserveTicks=10.0;
double InpBEExtraTicks=10.0;
double conversion=.755;
int valuationCalls=0, failAtCall=0;
bool invalidValuation=false;
double TickSize() { return .01; }
double SnapPrice(double price) { return std::round(price/.01)*.01; }

bool OrderCalcProfit(ENUM_ORDER_TYPE side,const char*,double lots,
                     double entry,double close,double &profit)
{
    ++valuationCalls;
    if(valuationCalls==failAtCall || entry<=0 || close<=0) return false;
    if(invalidValuation) { profit=std::numeric_limits<double>::quiet_NaN(); return true; }
    // 0.01 gold lot = one ounce in this fixture. Full cash profit is converted
    // then rounded to account pennies, unlike extrapolating a rounded one-tick P/L.
    double dollars=(close-entry)*(side==ORDER_TYPE_BUY?1:-1)*(lots/.01);
    profit=std::round(dollars*conversion*100.0)/100.0;
    return true;
}

// Generated at test time by extracting original and revised EA function bodies.
#include "cash_functions_extracted.inc"

int checks=0;
void check(bool value,const char* message)
{
    ++checks;
    if(!value) throw std::runtime_error(message);
}
bool near(double a,double b) { return std::abs(a-b)<1e-7; }
double netAt(bool buy,double entry,double price,double swap,bool stopExecution=true)
{
    double net=0;
    check(EstimateNetExit(buy,.01,entry,price,swap,stopExecution,net),"valuation available");
    return net;
}
void verifyMinimal(bool buy,double entry,double swap,double target)
{
    double stop=0;
    check(CashStopPrice(buy,.01,entry,swap,target,stop),"cash target must be reachable");
    check(stop>0 && near(stop/TickSize(),std::round(stop/TickSize())),"positive tick-grid stop");
    check(netAt(buy,entry,stop,swap)+1e-8>=target,"actual rounded net covers target");
    double sign=buy?1:-1;
    if(sign*(stop-entry)>TickSize()/2)
        check(netAt(buy,entry,stop-sign*TickSize(),swap)+1e-8<target,
              "one less favorable grid tick cannot cover target");
    else check(near(stop,SnapPrice(entry)),"minimal favorable offset is zero");
}

void oldRegression()
{
    for(bool buy:{true,false})
    {
        double oneTick=0;
        check(OrderCalcProfit(buy?ORDER_TYPE_BUY:ORDER_TYPE_SELL,_Symbol,.01,
                              4200,4200+(buy?.01:-.01),oneTick),"one-tick fixture valuation");
        check(near(oneTick,.01),"one tick rounds .00755 to .01 GBP");
        double stop=0;
        check(!OldCashStopPrice(buy,.01,4200,0,.754,stop),
              "archived cash function fails attainable target after six adjustments");
        verifyMinimal(buy,4200,0,.754);
        double oldBE=OldBreakevenPrice(buy,4200,.01);
        check(netAt(buy,4200,oldBE,0)<0,"archived BE stop does not cover modeled costs/slippage");
    }
}

void targets()
{
    for(bool buy:{true,false})
        for(double target:{0.0,.1,.5,.754,1.0,2.5,15.0})
            verifyMinimal(buy,4200,0,target);
}

void zeroTick()
{
    conversion=.25;
    for(bool buy:{true,false})
    {
        double oneTick=1;
        check(OrderCalcProfit(buy?ORDER_TYPE_BUY:ORDER_TYPE_SELL,_Symbol,.01,
                              4200,4200+(buy?.01:-.01),oneTick),"zero rounded tick valuation");
        check(oneTick==0,"single tick rounds to zero");
        double stop=0;
        check(!OldCashStopPrice(buy,.01,4200,0,.754,stop),"old function rejects zero tick gain");
        verifyMinimal(buy,4200,0,.754);
    }
}

void failures()
{
    for(bool buy:{true,false})
    {
        double stop=123;
        valuationCalls=0; failAtCall=1;
        check(!CashStopPrice(buy,.01,4200,0,.754,stop) && stop==0,"first broker failure fails closed");
        failAtCall=0; valuationCalls=0;
        check(CashStopPrice(buy,.01,4200,0,.754,stop),"baseline before final-check failure");
        int finalCall=valuationCalls;
        valuationCalls=0; failAtCall=finalCall; stop=123;
        check(!CashStopPrice(buy,.01,4200,0,.754,stop) && stop==0,"final valuation failure fails closed");
        failAtCall=0; invalidValuation=true; stop=123;
        check(!CashStopPrice(buy,.01,4200,0,.754,stop) && stop==0,"NaN broker valuation fails closed");
        invalidValuation=false;
    }
}

void invalidInputs()
{
    double nan=std::numeric_limits<double>::quiet_NaN();
    double inf=std::numeric_limits<double>::infinity();
    for(bool buy:{true,false})
    {
        for(double target:{nan,inf,-1.0})
        {
            double stop=123; valuationCalls=0;
            check(!CashStopPrice(buy,.01,4200,0,target,stop) && stop==0,"invalid target fails closed");
            check(valuationCalls==0,"invalid target rejected before broker valuation");
        }
        double stop=123;
        check(!CashStopPrice(buy,0,4200,0,.1,stop),"zero lots rejected");
        check(!CashStopPrice(buy,.01,nan,0,.1,stop),"nonfinite entry rejected");
        check(!CashStopPrice(buy,.01,4200,nan,.1,stop),"nonfinite swap rejected");
    }
}

void bounded()
{
    for(bool buy:{true,false})
    {
        double stop=123; valuationCalls=0;
        check(!CashStopPrice(buy,.01,4200,0,1e9,stop) && stop==0,"unreachable target fails closed");
        check(valuationCalls<=65,"bounded search plus verification has bounded broker calls");
    }
    double stop=123;
    check(!CashStopPrice(false,.01,.005,0,.1,stop) && stop==0,"short has no positive grid price");
    check(!CashStopPrice(false,.01,.01,0,.1,stop) && stop==0,"short cannot reach beyond positive price bound");
    verifyMinimal(false,.10,1.0,0); // Positive swap permits zero-offset short stop.
}

void swaps()
{
    for(bool buy:{true,false})
        for(double swap:{-.25,0.0,.25,1.0})
            for(double target:{0.0,.754}) verifyMinimal(buy,4200,swap,target);
}

void breakeven()
{
    for(bool buy:{true,false})
        for(double swap:{-.25,0.0,.25})
        {
            double stop=BreakevenPrice(buy,4200,.01,swap);
            check(stop>0,"new breakeven returns verified stop");
            check(netAt(buy,4200,stop,swap)>=-1e-8,"BE covers estimated fees, slip and swap");
            double base=0;
            check(FindNetStop(buy,.01,4200,swap,0,true,base),"base net-zero target reachable");
            check(near(stop,base+(buy?1:-1)*InpBEExtraTicks*TickSize()),"configured extra ticks added after cash coverage");
            check(netAt(buy,4200,stop,swap)>=netAt(buy,4200,base,swap),"extra ticks cannot reduce modeled net");
        }
    failAtCall=1; valuationCalls=0;
    check(BreakevenPrice(true,4200,.01,0)==0,"BE has no unverified price fallback");
}

void helper()
{
    for(long desired:{0L,1L,2L,3L,99999L,999999L,1000000L})
    {
        MGSCashSearch search;
        check(MGSBeginCashSearch(search,1000000),"valid helper bounds");
        while(!search.finished)
        {
            check(search.observations<64,"natural helper search finishes within 64 observations");
            MGSObserveCashSearch(search,(double)search.probe,(double)desired);
        }
        check(!search.failed && search.upper==desired,"helper finds first qualifying integer");
    }
    MGSCashSearch search;
    check(!MGSBeginCashSearch(search,-1),"negative helper maximum rejected");
    check(!MGSBeginCashSearch(search,1000001),"oversized helper maximum rejected");
    check(MGSBeginCashSearch(search,1000000),"bounded unreachable helper setup");
    while(!search.finished)
    {
        check(search.observations<64,"unreachable helper stays bounded");
        MGSObserveCashSearch(search,(double)search.probe,1000001.0);
    }
    check(search.failed,"unreachable helper target rejected");
    check(MGSBeginCashSearch(search,100),"nonfinite helper setup");
    MGSObserveCashSearch(search,std::numeric_limits<double>::quiet_NaN(),1);
    check(search.failed && search.finished,"nonfinite helper observation fails closed");
}

int main(int argc,char** argv)
{
    try
    {
        std::string scenario=argc==2?argv[1]:"";
        if(scenario=="old") oldRegression();
        else if(scenario=="targets") targets();
        else if(scenario=="zero_tick") zeroTick();
        else if(scenario=="failures") failures();
        else if(scenario=="invalid") invalidInputs();
        else if(scenario=="bounded") bounded();
        else if(scenario=="swaps") swaps();
        else if(scenario=="breakeven") breakeven();
        else if(scenario=="helper") helper();
        else throw std::runtime_error("unknown scenario");
        std::cout<<scenario<<": "<<checks<<" cash-search host assertions passed\n";
    }
    catch(const std::exception& error)
    {
        std::cerr<<error.what()<<"\n";
        return 1;
    }
}
